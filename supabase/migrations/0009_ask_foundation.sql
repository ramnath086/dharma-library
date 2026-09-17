-- ---------------------------------------------------------------------------
-- 0009 Ask Dharma foundation
--
-- Operational plumbing for the grounded Q&A feature that ships in the `ask`
-- Edge Function and the app's Ask screen. No content tables change here; this
-- migration only adds a usage view-function and default suggested questions.
--
--   * public.qa_answers_today() — how many grounded answers the *calling*
--     user received today (UTC). The Edge Function uses it to apply a daily
--     cap per signed-in account. SECURITY INVOKER so RLS keeps scoping it to
--     the caller; anonymous callers always get 0.
--   * app_config['ask.suggested_questions'] — question starters shown on the
--     empty Ask thread. Seeded with ON CONFLICT DO NOTHING so any admin edit
--     made in production is never clobbered by a re-run.
-- ---------------------------------------------------------------------------

create or replace function public.qa_answers_today()
returns bigint
language sql
stable
security invoker
set search_path = public
as $$
  select count(*)
    from public.qa_messages m
    join public.qa_sessions s on s.id = m.session_id
   where s.user_id = auth.uid()
     and m.role = 'assistant'
     and m.created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc';
$$;

grant execute on function public.qa_answers_today() to anon, authenticated, service_role;

insert into public.app_config (key, value) values
  ('ask.suggested_questions', $j${
    "en": [
      "For whose benefit was the Bhagavatam recited in the Naimisha forest?",
      "What is the highest truth (param satyam) described in the opening verses?",
      "Who compiled the Vedas into four, and why?",
      "What makes this purana different from other scriptures?",
      "Why did the sages gather at Naimisharanya?"
    ],
    "ml": [
      "നൈമിഷാരണ്യത്തിൽ ഭാഗവതം ആർക്കുള്ളതിനാണ് ചൊല്ലിയത്?",
      "ആദ്യ ശ്ലോകങ്ങളിൽ വിവരിക്കുന്ന പരമസത്യം എന്താണ്?",
      "വേടങ്ങളെ നാലായി തിരിച്ചത് ആരാണ്, എന്തിനാണ്?",
      "ഈ പുരാണം മറ്റ് ശാസ്ത്രങ്ങളിൽനിന്ന് എന്തുകൊണ്ട് വ്യത്യസ്തമാണ്?",
      "ഋഷിമാർ നൈമിഷാരണ്യത്തിൽ കൂടിയതിന്റെ കാരണം എന്താണ്?"
    ]
  }$j$)
on conflict (key) do nothing;

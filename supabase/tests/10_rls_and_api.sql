-- RLS + API regression tests. Runs on the local harness (plain assertions,
-- no pgTAP needed). Every `perform assert_*` raises on failure.
\set ON_ERROR_STOP on
set client_min_messages = notice;

create or replace function pg_temp.assert_eq(actual anyelement, expected anyelement, msg text) returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'ASSERT FAILED: % — expected %, got %', msg, expected, actual;
  end if;
  raise notice 'ok — %', msg;
end $$;

-- ---------------------------------------------------------------------------
-- fixtures: three users (reader, editor, admin) + a restricted edition
-- ---------------------------------------------------------------------------
-- clean any leftovers from an aborted previous run
delete from public.bookmarks where user_id = '00000000-0000-0000-0000-000000000001';
delete from public.reading_progress where user_id = '00000000-0000-0000-0000-000000000001';
delete from public.verse_reads where user_id = '00000000-0000-0000-0000-000000000001';
delete from public.qa_sessions where user_id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
delete from public.analytics_events where user_id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
delete from public.editions where slug like 'test-%';
delete from public.rights where id in ('11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111112');
delete from public.sources where slug = 'test-restricted-src';
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'reader@test'),
  ('00000000-0000-0000-0000-000000000002', 'editor@test'),
  ('00000000-0000-0000-0000-000000000003', 'admin@test')
on conflict do nothing;
update public.profiles set role = 'editor' where id = '00000000-0000-0000-0000-000000000002';
update public.profiles set role = 'admin'  where id = '00000000-0000-0000-0000-000000000003';

-- a copyrighted edition that must never leak
insert into public.sources (slug, title, kind) values ('test-restricted-src', 'Some copyrighted translation', 'book') on conflict (slug) do nothing;
insert into public.rights (id, source_id, status, license, attribution_text)
values ('11111111-1111-1111-1111-111111111111', (select id from sources where slug='test-restricted-src'), 'restricted', 'Proprietary', '© Publisher. All rights reserved.')
on conflict (id) do nothing;
insert into public.editions (id, work_id, slug, kind, language_code, script_code, title, rights_id, status)
values ('22222222-2222-2222-2222-222222222222', (select id from works where slug='bhagavata-purana'), 'test-restricted-en', 'translation', 'en', 'Latn', 'Restricted EN', '11111111-1111-1111-1111-111111111111', 'published')
on conflict (slug) do nothing;
insert into public.verse_contents (verse_id, edition_id, body, status)
values ((select id from verses where ref='1.1.1'), '22222222-2222-2222-2222-222222222222', 'SECRET COPYRIGHTED TEXT', 'published')
on conflict (verse_id, edition_id) do nothing;

-- pending-permission edition: also not servable
insert into public.rights (id, status, attribution_text) values ('11111111-1111-1111-1111-111111111112', 'pending', 'awaiting permission') on conflict (id) do nothing;
insert into public.editions (id, work_id, slug, kind, language_code, script_code, title, rights_id, status)
values ('22222222-2222-2222-2222-222222222223', (select id from works where slug='bhagavata-purana'), 'test-pending-en', 'translation', 'en', 'Latn', 'Pending EN', '11111111-1111-1111-1111-111111111112', 'published')
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------------
-- anon
-- ---------------------------------------------------------------------------
set role anon;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.assert_eq((select count(*) from public.verses where work_id = (select id from works where slug='bhagavata-purana')), 10::bigint, 'anon sees 10 published verses in bhagavata-purana');
select pg_temp.assert_eq((select count(*) from public.verses where work_id = (select id from works where slug='bhagavad-gita')), 700::bigint, 'anon sees 700 published verses in bhagavad-gita');
select pg_temp.assert_eq((select count(*) from public.verses), 710::bigint, 'anon sees 710 published verses total');
select pg_temp.assert_eq((select count(*) from public.editions where slug like 'test-%'), 0::bigint, 'anon cannot see restricted/pending editions');
select pg_temp.assert_eq((select count(*) from public.verse_contents where body like 'SECRET%'), 0::bigint, 'anon cannot read restricted content');
select pg_temp.assert_eq((select count(*) from public.v_editions where rights_status in ('restricted','pending')), 0::bigint, 'v_editions hides uncleared editions');
select pg_temp.assert_eq((select count(*) from public.editions where public.edition_is_public(id)), (select count(*) from public.editions), 'all visible editions are public');
select pg_temp.assert_eq((select count(*) from public.profiles), 0::bigint, 'anon sees no profiles');
select pg_temp.assert_eq((select count(*) from public.bookmarks), 0::bigint, 'anon sees no bookmarks');
select pg_temp.assert_eq((select jsonb_array_length(public.get_toc('bhagavata-purana')->'sections')), 1, 'toc has 1 canto');
select pg_temp.assert_eq((select jsonb_array_length(public.get_section_verses((select id from sections where ref='1.1'))->'verses')), 10, 'chapter has 10 verses');
select pg_temp.assert_eq((select jsonb_array_length(public.get_published_works())), 2, 'catalogue lists both published works');
select pg_temp.assert_eq((
  select bool_and(w->>'slug' in ('bhagavata-purana','bhagavad-gita'))
    from jsonb_array_elements(public.get_published_works()) w
), true, 'catalogue slugs are the published works, not hard-coded in the client');
select pg_temp.assert_eq((
  select v->'metadata'->'audio'->>'important'
    from jsonb_array_elements(public.get_section_verses((select id from sections where ref='1.1' and work_id=(select id from works where slug='bhagavata-purana')))->'verses') v
   where v->>'ref' = '1.1.1'
), 'true', 'editorial mangala cue metadata travels with the chapter payload');
select pg_temp.assert_eq((select public.get_verse('bhagavata-purana','1.1.4')->>'next_ref'), '1.1.5', 'next_ref');
select pg_temp.assert_eq((select public.get_verse('bhagavata-purana','1.1.1')->>'prev_ref'), null::text, 'prev_ref of first verse is null');
select pg_temp.assert_eq((select count(*) > 0 from public.search_verses('naimisa')), true, 'search: diacritic-insensitive');
select pg_temp.assert_eq((select count(*) > 0 from public.search_verses('കലിയുഗ')), true, 'search: malayalam');
select pg_temp.assert_eq((select count(*) > 0 from public.search_verses('सूतमासीनं')), true, 'search: devanagari');
select pg_temp.assert_eq((select count(*) from public.search_verses('SECRET COPYRIGHTED') where edition_title = 'Restricted EN' or snippet ilike '%COPYRIGHTED%'), 0::bigint, 'search never surfaces restricted content');
select pg_temp.assert_eq((select count(*) > 0 from public.search_entities('vyasa')), true, 'entity search');
select pg_temp.assert_eq((select public.get_entity('person','suta')->'entity'->>'slug'), 'suta', 'get_entity');
select pg_temp.assert_eq((select jsonb_array_length(public.get_entity('person','suta')->'verses') >= 5), true, 'suta mentioned in >=5 verses');

-- Ask Dharma: anonymous callers have no personal counter, and no sessions
select pg_temp.assert_eq(public.qa_answers_today(), 0::bigint, 'anon: qa_answers_today is 0');
select pg_temp.assert_eq((select jsonb_array_length(value->'en') from public.app_config where key = 'ask.suggested_questions') >= 3, true, 'anon reads suggested questions');
do $$ begin
  begin
    insert into public.qa_sessions (user_id) values (null);
    raise exception 'ASSERT FAILED: anon could open a qa session';
  exception when insufficient_privilege or check_violation then raise notice 'ok — anon cannot open qa sessions'; end;
end $$;

do $$ begin
  begin
    insert into public.analytics_events (user_id, event) values ('00000000-0000-0000-0000-000000000001', 'daily_open');
    raise exception 'ASSERT FAILED: anon could log an analytics event';
  exception when insufficient_privilege or check_violation then raise notice 'ok — anon cannot log analytics events'; end;
end $$;

-- anon cannot write
do $$ begin
  begin
    insert into public.verses (work_id, section_id, ordinal, ref) values ((select id from works limit 1), (select id from sections where ref='1.1'), 99, '1.1.99');
    raise exception 'ASSERT FAILED: anon could insert verse';
  exception when insufficient_privilege or check_violation then raise notice 'ok — anon cannot insert verses'; end;
end $$;

-- ---------------------------------------------------------------------------
-- reader (authenticated)
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);

select pg_temp.assert_eq((select count(*) from public.profiles), 1::bigint, 'reader sees only own profile');
select pg_temp.assert_eq((select count(*) from public.verse_contents where body like 'SECRET%'), 0::bigint, 'reader cannot read restricted content');

insert into public.bookmarks (user_id, verse_id, note) values ('00000000-0000-0000-0000-000000000001', (select id from verses where ref='1.1.3'), 'lovely');
select pg_temp.assert_eq((select count(*) from public.bookmarks), 1::bigint, 'reader can bookmark');
do $$ begin
  begin
    insert into public.bookmarks (user_id, verse_id) values ('00000000-0000-0000-0000-000000000002', (select id from verses where ref='1.1.3'));
    raise exception 'ASSERT FAILED: reader could bookmark as another user';
  exception when insufficient_privilege or check_violation then raise notice 'ok — cannot forge bookmark owner'; end;
end $$;

select public.upsert_progress((select id from works where slug='bhagavata-purana'), (select id from verses where ref='1.1.5'), '{}', 'dev-1');
select pg_temp.assert_eq((select percent from public.reading_progress), 50.00::numeric, 'progress 5/10 = 50%');
select pg_temp.assert_eq((select jsonb_array_length(public.sync_pull()->'bookmarks')), 1, 'sync_pull returns own bookmarks');

-- cannot self-promote
do $$ begin
  begin
    update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000001';
    if (select role from public.profiles where id = '00000000-0000-0000-0000-000000000001') = 'admin' then
      raise exception 'ASSERT FAILED: reader self-promoted';
    end if;
    raise notice 'ok — self-promotion blocked (no-op)';
  exception when insufficient_privilege or check_violation then raise notice 'ok — self-promotion blocked'; end;
end $$;

do $$ begin
  begin
    update public.verse_contents set body = 'vandalised' where verse_id = (select id from verses where ref='1.1.1');
    if exists (select 1 from public.verse_contents where body = 'vandalised') then raise exception 'ASSERT FAILED: reader edited content'; end if;
    raise notice 'ok — reader cannot edit content';
  exception when insufficient_privilege then raise notice 'ok — reader cannot edit content'; end;
end $$;

-- Ask Dharma: own conversations, the daily answer counter, and feedback
do $$
declare sid uuid;
begin
  insert into public.qa_sessions (user_id, language, title)
    values ('00000000-0000-0000-0000-000000000001', 'en', 'test qa') returning id into sid;
  insert into public.qa_messages (session_id, role, content, grounded) values
    (sid, 'user', 'who recited the text in the test?', null),
    (sid, 'assistant', 'A test assistant answer citing [SB 1.1.2].', true);
  perform pg_temp.assert_eq((select count(*) from public.qa_sessions), 1::bigint, 'reader sees only own qa sessions');
  perform pg_temp.assert_eq((select count(*) from public.qa_messages), 2::bigint, 'reader sees own qa messages');
  perform pg_temp.assert_eq(public.qa_answers_today(), 1::bigint, 'qa_answers_today counts today''s assistant answers');

  update public.qa_messages set feedback = 1 where session_id = sid and role = 'assistant';
  perform pg_temp.assert_eq((select count(*) from public.qa_messages where feedback = 1), 1::bigint, 'reader can rate own answer');

  begin
    insert into public.qa_sessions (user_id) values ('00000000-0000-0000-0000-000000000002');
    raise exception 'ASSERT FAILED: reader forged qa session owner';
  exception when insufficient_privilege or check_violation then raise notice 'ok — cannot forge qa session owner'; end;
end $$;

-- Analytics: opt-in events are insert-only and invisible to their own owner
do $$
begin
  insert into public.analytics_events (user_id, event, payload) values
    ('00000000-0000-0000-0000-000000000001', 'daily_open', '{}'),
    ('00000000-0000-0000-0000-000000000001', 'search', '{"hits": 3, "offline": true}');
  perform pg_temp.assert_eq((select count(*) from public.analytics_events), 0::bigint, 'events are write-only for their owner');
  begin
    insert into public.analytics_events (user_id, event) values ('00000000-0000-0000-0000-000000000002', 'daily_open');
    raise exception 'ASSERT FAILED: reader forged analytics owner';
  exception when insufficient_privilege or check_violation then raise notice 'ok — cannot forge analytics owner'; end;
  begin
    insert into public.analytics_events (user_id, event) values ('00000000-0000-0000-0000-000000000001', 'Free text, not snake_case!');
    raise exception 'ASSERT FAILED: analytics accepted a non-snake_case event';
  exception when check_violation then raise notice 'ok — analytics events must be snake_case'; end;
end $$;

-- ---------------------------------------------------------------------------
-- editor
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
select pg_temp.assert_eq(public.is_editor(), true, 'editor role resolves');
select pg_temp.assert_eq((select count(*) from public.editions where slug like 'test-%'), 2::bigint, 'editor sees restricted editions (for CMS)');
select pg_temp.assert_eq((select count(*) from public.qa_sessions), 0::bigint, 'editor cannot see reader qa sessions');
select pg_temp.assert_eq(public.qa_answers_today(), 0::bigint, 'editor counter excludes reader answers');
update public.qa_messages set feedback = -1;
select pg_temp.assert_eq((select count(*) from public.qa_messages), 0::bigint, 'editor cannot see or rate reader qa messages');
update public.verse_contents set notes = 'editor note' where verse_id = (select id from verses where ref='1.1.1') and edition_id = (select id from editions where slug='sb-en-dl');
select pg_temp.assert_eq((select notes from public.verse_contents where verse_id = (select id from verses where ref='1.1.1') and edition_id = (select id from editions where slug='sb-en-dl')), 'editor note', 'editor can edit content');
select pg_temp.assert_eq((select count(*) from public.bookmarks), 0::bigint, 'editor cannot see reader bookmarks');
do $$ begin
  begin
    update public.rights set status = 'public_domain' where id = '11111111-1111-1111-1111-111111111111';
    if (select status from public.rights where id='11111111-1111-1111-1111-111111111111') = 'public_domain' then raise exception 'ASSERT FAILED: editor changed rights'; end if;
    raise notice 'ok — editor cannot change rights';
  exception when insufficient_privilege then raise notice 'ok — editor cannot change rights'; end;
end $$;
select pg_temp.assert_eq((select count(*) from public.audit_log), 0::bigint, 'editor cannot read audit log');

-- ---------------------------------------------------------------------------
-- admin
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select pg_temp.assert_eq(public.is_admin(), true, 'admin role resolves');
select pg_temp.assert_eq((select count(*) > 0 from public.audit_log), true, 'admin reads audit log');
select pg_temp.assert_eq((select count(*) from public.audit_log where table_name='verse_contents' and action='UPDATE' and actor_id='00000000-0000-0000-0000-000000000002' and new_data->>'notes' = 'editor note') >= 1, true, 'audit captured editor update with actor');
select pg_temp.assert_eq((select count(*) from public.profiles), 3::bigint, 'admin sees all profiles');
select pg_temp.assert_eq((select count(*) from public.analytics_events), 2::bigint, 'admin reads analytics events (reader logged 2)');

reset role;
-- cleanup fixtures
delete from public.qa_sessions where user_id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
delete from public.analytics_events where user_id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
delete from public.editions where slug like 'test-%';
delete from public.rights where id in ('11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111112');
delete from public.sources where slug = 'test-restricted-src';
delete from public.bookmarks where user_id = '00000000-0000-0000-0000-000000000001';
delete from public.reading_progress where user_id = '00000000-0000-0000-0000-000000000001';
delete from public.verse_reads where user_id = '00000000-0000-0000-0000-000000000001';
update public.verse_contents set notes = null where notes = 'editor note';
select 'RLS/API tests passed' as result;

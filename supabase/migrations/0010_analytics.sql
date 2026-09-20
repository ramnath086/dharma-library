-- ---------------------------------------------------------------------------
-- 0010 Privacy-first usage analytics
--
-- One append-only table for opt-in, content-free usage events. Design rules:
--   * The app only logs when the user opts in (Settings → Privacy) AND is
--     signed in. Events carry action counts/facts, never what was read,
--     searched, or asked — no verse refs, no query text, no free text.
--   * Writers can only insert as themselves (RLS with check); users cannot
--     read rows back; only admins can review. No update/delete anywhere:
--     the log is append-only for everyone.
-- ---------------------------------------------------------------------------

create table public.analytics_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  event       text not null check (event ~ '^[a-z][a-z0-9_]{1,31}$'),  -- snake_case name only
  payload     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index analytics_events_user_idx on public.analytics_events (user_id, created_at desc);

alter table public.analytics_events enable row level security;

create policy "analytics: insert own" on public.analytics_events for insert
  with check (user_id = auth.uid());
create policy "analytics: admin read" on public.analytics_events for select
  using (public.is_admin());

grant insert on public.analytics_events to authenticated;
grant select on public.analytics_events to authenticated; -- rows still gated by RLS

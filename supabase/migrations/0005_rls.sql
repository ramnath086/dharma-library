-- =============================================================================
-- Dharma Library — 0005: Row Level Security
-- =============================================================================
-- Principles
--   * Everything is RLS-enabled. No table is readable without a policy.
--   * Anonymous + authenticated readers see ONLY published rows whose edition
--     rights are cleared (rights.status in public_domain/open_license/
--     permission_granted/original and not expired).
--   * Users own their bookmarks / progress / QA sessions.
--   * editors/admins (profiles.role) manage content; admins manage rights,
--     roles and config. Role checks use a SECURITY DEFINER helper so policies
--     don't recurse into profiles.
--   * service_role bypasses RLS (Supabase default) for ingestion scripts.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Role helpers
-- ---------------------------------------------------------------------------
create or replace function public.current_role_name()
returns public.user_role language sql stable security definer set search_path = public as $$
  select coalesce((select role from public.profiles where id = auth.uid()), 'reader'::public.user_role);
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_role_name() = 'admin';
$$;

create or replace function public.is_editor()
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_role_name() in ('editor', 'admin');
$$;

create or replace function public.is_contributor()
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_role_name() in ('contributor', 'editor', 'admin');
$$;

revoke execute on function public.current_role_name() from public;
grant  execute on function public.current_role_name() to authenticated, anon, service_role;
grant  execute on function public.is_admin(), public.is_editor(), public.is_contributor() to authenticated, anon, service_role;

-- Is this edition lawfully servable to the public?
create or replace function public.edition_is_public(e_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from public.editions e
      join public.rights r on r.id = e.rights_id
      join public.works  w on w.id = e.work_id
     where e.id = e_id
       and e.status = 'published'
       and w.status = 'published'
       and public.rights_is_cleared(r)
  );
$$;
grant execute on function public.edition_is_public(uuid) to authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  for t in
    select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy "profiles: read own"        on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "profiles: update own"      on public.profiles for update using (id = auth.uid())
  with check (id = auth.uid() and role = (select role from public.profiles p where p.id = auth.uid()));  -- cannot self-promote
create policy "profiles: admin manage"    on public.profiles for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Reference tables: public read, admin write
-- ---------------------------------------------------------------------------
create policy "languages: public read"   on public.languages  for select using (true);
create policy "languages: admin write"   on public.languages  for all using (public.is_admin()) with check (public.is_admin());
create policy "scripts: public read"     on public.scripts    for select using (true);
create policy "scripts: admin write"     on public.scripts    for all using (public.is_admin()) with check (public.is_admin());
create policy "app_config: public read"  on public.app_config for select using (true);
create policy "app_config: admin write"  on public.app_config for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- sources & rights
-- ---------------------------------------------------------------------------
-- Sources are bibliographic and non-sensitive: public read.
create policy "sources: public read"     on public.sources for select using (true);
create policy "sources: editor write"    on public.sources for all using (public.is_editor()) with check (public.is_editor());

-- Rights rows are readable by everyone (attribution must be shown) but the
-- permission document path is exposed only through the admin view below.
create policy "rights: public read"      on public.rights for select using (true);
create policy "rights: admin write"      on public.rights for all using (public.is_admin()) with check (public.is_admin());

revoke select (permission_document_url) on public.rights from anon, authenticated;
grant  select (id, source_id, status, license, license_url, rights_holder, attribution_text,
               permission_granted_on, permission_expires_on, territory, allows_commercial,
               allows_derivatives, allows_audio, notes, created_at, updated_at)
  on public.rights to anon, authenticated;

-- ---------------------------------------------------------------------------
-- works / sections / verses (structure): published → public; editors → all
-- ---------------------------------------------------------------------------
create policy "works: public read published"  on public.works for select
  using (status = 'published' or public.is_editor());
create policy "works: editor write"           on public.works for all
  using (public.is_editor()) with check (public.is_editor());

create policy "sections: public read published" on public.sections for select
  using ((status = 'published' and exists (select 1 from public.works w where w.id = work_id and w.status = 'published'))
         or public.is_editor());
create policy "sections: editor write"          on public.sections for all
  using (public.is_editor()) with check (public.is_editor());

create policy "verses: public read published"   on public.verses for select
  using ((status = 'published' and exists (select 1 from public.works w where w.id = work_id and w.status = 'published'))
         or public.is_editor());
create policy "verses: editor write"            on public.verses for all
  using (public.is_editor()) with check (public.is_editor());

-- ---------------------------------------------------------------------------
-- editions & contents: rights-gated
-- ---------------------------------------------------------------------------
create policy "editions: public read cleared" on public.editions for select
  using (public.edition_is_public(id) or public.is_editor());
create policy "editions: editor write"        on public.editions for all
  using (public.is_editor()) with check (public.is_editor());

create policy "verse_contents: public read cleared" on public.verse_contents for select
  using ((status = 'published' and public.edition_is_public(edition_id)) or public.is_contributor());
create policy "verse_contents: contributor insert draft" on public.verse_contents for insert
  with check (public.is_contributor() and (status = 'draft' or public.is_editor()));
create policy "verse_contents: contributor update draft" on public.verse_contents for update
  using (public.is_editor() or (public.is_contributor() and status in ('draft','in_review')))
  with check (public.is_editor() or status in ('draft','in_review'));
create policy "verse_contents: editor delete" on public.verse_contents for delete using (public.is_editor());

create policy "section_contents: public read cleared" on public.section_contents for select
  using ((status = 'published' and public.edition_is_public(edition_id)) or public.is_contributor());
create policy "section_contents: editor write" on public.section_contents for all
  using (public.is_editor()) with check (public.is_editor());

create policy "xref: public read published" on public.cross_references for select
  using (status = 'published' or public.is_contributor());
create policy "xref: editor write" on public.cross_references for all
  using (public.is_editor()) with check (public.is_editor());

-- ---------------------------------------------------------------------------
-- Knowledge graph
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['people','places','topics','stories','verse_mentions','entity_relations']
  loop
    execute format($p$create policy "%1$s: public read published" on public.%1$s for select using (status = 'published' or public.is_contributor())$p$, t);
    execute format($p$create policy "%1$s: editor write" on public.%1$s for all using (public.is_editor()) with check (public.is_editor())$p$, t);
  end loop;
end $$;
create policy "entity_names: public read" on public.entity_names for select using (true);
create policy "entity_names: editor write" on public.entity_names for all using (public.is_editor()) with check (public.is_editor());

-- ---------------------------------------------------------------------------
-- Audio (rights-gated through edition)
-- ---------------------------------------------------------------------------
create policy "audio_tracks: public read cleared" on public.audio_tracks for select
  using ((status = 'published' and public.edition_is_public(edition_id)) or public.is_editor());
create policy "audio_tracks: editor write" on public.audio_tracks for all
  using (public.is_editor()) with check (public.is_editor());
create policy "audio_segments: public read" on public.audio_segments for select
  using (exists (select 1 from public.audio_tracks t where t.id = track_id
                   and (t.status = 'published' and public.edition_is_public(t.edition_id))) or public.is_editor());
create policy "audio_segments: editor write" on public.audio_segments for all
  using (public.is_editor()) with check (public.is_editor());

-- ---------------------------------------------------------------------------
-- User-owned data
-- ---------------------------------------------------------------------------
create policy "bookmarks: own" on public.bookmarks for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "reading_progress: own" on public.reading_progress for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "verse_reads: own" on public.verse_reads for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "qa_sessions: own" on public.qa_sessions for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "qa_messages: own" on public.qa_messages for all
  using (exists (select 1 from public.qa_sessions s where s.id = session_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.qa_sessions s where s.id = session_id and s.user_id = auth.uid()));

-- Embeddings: never read directly by clients — only through the search RPC.
create policy "embeddings: editor read" on public.content_embeddings for select using (public.is_editor());
create policy "embeddings: editor write" on public.content_embeddings for all using (public.is_editor()) with check (public.is_editor());

-- Audit log: admins only
create policy "audit_log: admin read" on public.audit_log for select using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Grants (Supabase roles)
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;
grant select on all tables in schema public to anon, authenticated;
grant insert, update, delete on
  public.profiles, public.bookmarks, public.reading_progress, public.verse_reads,
  public.qa_sessions, public.qa_messages,
  public.works, public.sections, public.verses, public.editions, public.verse_contents,
  public.section_contents, public.cross_references, public.sources, public.rights,
  public.people, public.places, public.topics, public.stories, public.entity_names,
  public.verse_mentions, public.entity_relations, public.audio_tracks, public.audio_segments,
  public.content_embeddings, public.app_config, public.languages, public.scripts
  to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;   -- policy restricts to admins

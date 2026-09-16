-- =============================================================================
-- Dharma Library — 0008: Storage RLS Policies
-- =============================================================================
-- Buckets ('audio', 'rights-documents') are configured via config.toml / dashboard.
-- Policies:
--   * 'audio' (private):
--       - READ: public read for objects mapped to published + cleared audio tracks,
--               or editors/admins.
--       - WRITE/DELETE: editors/admins only (or service_role).
--   * 'rights-documents' (private):
--       - READ/WRITE/DELETE: admins only (or service_role).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Storage Objects Policies
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'objects') then
    execute 'alter table storage.objects enable row level security';

    -- Drop existing policies if any to ensure clean idempotent state
    drop policy if exists "audio: public read cleared" on storage.objects;
    drop policy if exists "audio: editor write" on storage.objects;
    drop policy if exists "audio: editor update" on storage.objects;
    drop policy if exists "audio: editor delete" on storage.objects;
    drop policy if exists "rights-documents: admin all" on storage.objects;

    -- Audio Bucket Policies
    execute $p$
      create policy "audio: public read cleared" on storage.objects for select
      using (
        bucket_id = 'audio'
        and (
          public.is_editor()
          or exists (
            select 1 from public.audio_tracks t
             where t.storage_bucket = 'audio'
               and t.storage_path = name
               and t.status = 'published'
               and public.edition_is_public(t.edition_id)
          )
        )
      )
    $p$;

    execute $p$
      create policy "audio: editor write" on storage.objects for insert
      with check (
        bucket_id = 'audio'
        and public.is_editor()
      )
    $p$;

    execute $p$
      create policy "audio: editor update" on storage.objects for update
      using (
        bucket_id = 'audio'
        and public.is_editor()
      )
      with check (
        bucket_id = 'audio'
        and public.is_editor()
      )
    $p$;

    execute $p$
      create policy "audio: editor delete" on storage.objects for delete
      using (
        bucket_id = 'audio'
        and public.is_editor()
      )
    $p$;

    -- Rights Documents Bucket Policies (Admins only)
    execute $p$
      create policy "rights-documents: admin all" on storage.objects for all
      using (
        bucket_id = 'rights-documents'
        and public.is_admin()
      )
      with check (
        bucket_id = 'rights-documents'
        and public.is_admin()
      )
    $p$;
  end if;
end $$;

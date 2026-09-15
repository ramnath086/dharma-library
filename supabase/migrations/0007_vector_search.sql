-- =============================================================================
-- Dharma Library — 0007: vector similarity RPC for AI retrieval
-- =============================================================================
-- Only functional when the `vector` extension is present (Supabase: yes).
-- SECURITY DEFINER so anon can search embeddings without direct table read,
-- but results are re-filtered through edition_is_public so RLS semantics hold.

do $$
begin
  if exists (select 1 from pg_extension where extname = 'vector') then
    execute $f$
      create or replace function public.match_verse_contents(
        p_embedding vector(1536), p_language text default 'en', p_work_slug text default null, p_limit int default 8, p_min_similarity real default 0.2)
      returns table (verse_id uuid, ref text, work_slug text, edition_id uuid, edition_title text, language_code text, body text, attribution_text text, rank real)
      language sql stable security definer set search_path = public as $b$
        select vc.verse_id, v.ref, w.slug, vc.edition_id, e.title, e.language_code, vc.body, e.attribution_text,
               (1 - (ce.embedding <=> p_embedding))::real as rank
          from public.content_embeddings ce
          join public.verse_contents vc on vc.id = ce.verse_content_id
          join public.verses v on v.id = vc.verse_id
          join public.works w on w.id = v.work_id
          join public.v_editions e on e.id = vc.edition_id
         where vc.status = 'published'
           and public.edition_is_public(vc.edition_id)
           and (p_work_slug is null or w.slug = p_work_slug)
           and (e.language_code = p_language or e.kind <> 'translation')
           and (1 - (ce.embedding <=> p_embedding)) >= p_min_similarity
         order by ce.embedding <=> p_embedding
         limit greatest(1, least(p_limit, 50));
      $b$;
      grant execute on function public.match_verse_contents(vector, text, text, int, real) to anon, authenticated, service_role;
    $f$;
  else
    raise notice 'vector extension absent: match_verse_contents not created (AI Q&A falls back to lexical retrieval)';
  end if;
end $$;

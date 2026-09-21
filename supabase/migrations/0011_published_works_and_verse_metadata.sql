-- =============================================================================
-- 0011: published-work catalogue + verse.metadata in chapter payloads
-- =============================================================================
-- Additive. Does not drop tables or rewrite Gita/Bhāgavata rows.
-- get_section_verses previously omitted verses.metadata, so editorial audio
-- cues never reached the app or offline bundles.

-- ---------------------------------------------------------------------------
-- Catalogue of published works (Home). Counts are live; RLS still hides drafts.
-- ---------------------------------------------------------------------------
create or replace function public.get_published_works()
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', w.id,
    'slug', w.slug,
    'short_code', w.short_code,
    'title_iast', w.title_iast,
    'title_sa', w.title_sa,
    'tradition', w.tradition,
    'description', w.description,
    'original_language', w.original_language,
    'original_script', w.original_script,
    'structure', w.structure,
    'metadata', w.metadata,
    'sort_order', w.sort_order,
    'chapter_count', (
      select count(*) from public.sections s
       where s.work_id = w.id
         and not exists (select 1 from public.sections c where c.parent_id = s.id)
    ),
    'verse_count', (select count(*) from public.verses v where v.work_id = w.id)
  ) order by w.sort_order, w.slug), '[]'::jsonb)
  from public.works w
  where w.status = 'published';
$$;
grant execute on function public.get_published_works() to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Chapter payload: include verse.metadata (audio cues, pending_xrefs, …)
-- ---------------------------------------------------------------------------
create or replace function public.get_section_verses(p_section_id uuid, p_edition_ids uuid[] default null)
returns jsonb language sql stable as $$
  with sec as (select * from public.sections where id = p_section_id),
  eds as (
    select e.* from public.editions e join sec on sec.work_id = e.work_id
     where (p_edition_ids is null or e.id = any(p_edition_ids))
  ),
  vs as (
    select v.* from public.verses v where v.section_id = p_section_id
  ),
  content as (
    select vc.verse_id,
           jsonb_agg(jsonb_build_object(
             'edition_id', vc.edition_id,
             'kind', e.kind, 'language_code', e.language_code, 'script_code', e.script_code,
             'body', vc.body, 'body_html', vc.body_html,
             'word_meanings', vc.word_meanings, 'footnotes', vc.footnotes, 'notes', vc.notes
           ) order by e.sort_order) as renderings
      from public.verse_contents vc
      join eds e on e.id = vc.edition_id
     where vc.verse_id in (select id from vs)
     group by vc.verse_id
  ),
  audio as (
    select seg.verse_id,
           jsonb_agg(jsonb_build_object('track_id', seg.track_id, 'start_ms', seg.start_ms, 'end_ms', seg.end_ms)) as segments
      from public.audio_segments seg
     where seg.verse_id in (select id from vs)
     group by seg.verse_id
  )
  select jsonb_build_object(
    'section', (select to_jsonb(sec) from sec),
    'editions', (select coalesce(jsonb_agg(to_jsonb(ve) order by ve.sort_order), '[]'::jsonb) from public.v_editions ve where ve.id in (select id from eds)),
    'verses', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', v.id, 'ref', v.ref, 'ordinal', v.ordinal, 'kind', v.kind, 'meter', v.meter,
        'speaker_id', v.speaker_id,
        'speaker', (select jsonb_build_object('id', p.id, 'slug', p.slug, 'name_iast', p.name_iast, 'name_sa', p.name_sa) from public.people p where p.id = v.speaker_id),
        'renderings', coalesce(c.renderings, '[]'::jsonb),
        'audio', coalesce(a.segments, '[]'::jsonb),
        'metadata', coalesce(v.metadata, '{}'::jsonb)
      ) order by v.ordinal), '[]'::jsonb)
      from vs v left join content c on c.verse_id = v.id left join audio a on a.verse_id = v.id
    ),
    'tracks', (
      select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
        from public.audio_tracks t where t.section_id = p_section_id
    )
  );
$$;
grant execute on function public.get_section_verses(uuid, uuid[]) to anon, authenticated, service_role;

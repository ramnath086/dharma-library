-- =============================================================================
-- Dharma Library — 0006: API (views + RPC) consumed by the Flutter app
-- =============================================================================
-- All functions are SECURITY INVOKER (default) so RLS applies to the caller,
-- unless noted. Return shapes are stable JSON so the mobile client can cache
-- them offline verbatim.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- View: editions with resolved rights (what the app shows in the layout picker)
-- ---------------------------------------------------------------------------
create or replace view public.v_editions
with (security_invoker = true) as
select e.id, e.work_id, e.slug, e.kind, e.language_code, e.script_code, e.title,
       e.contributors, e.is_default, e.is_machine, e.status, e.sort_order, e.description,
       e.derived_from, e.metadata,
       l.name_en   as language_name_en,
       l.name_native as language_name_native,
       s.name_en   as script_name_en,
       r.status    as rights_status,
       r.license, r.license_url, r.rights_holder, r.attribution_text,
       src.title   as source_title, src.url as source_url, src.archive_url as source_archive_url,
       src.authors as source_authors, src.publisher as source_publisher, src.year as source_year
  from public.editions e
  join public.languages l on l.code = e.language_code
  join public.scripts   s on s.code = e.script_code
  join public.rights    r on r.id  = e.rights_id
  left join public.sources src on src.id = e.source_id;
grant select on public.v_editions to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Table of contents for a work: nested sections with verse counts
-- ---------------------------------------------------------------------------
create or replace function public.get_toc(p_work_slug text)
returns jsonb language sql stable as $$
  with w as (select * from public.works where slug = p_work_slug),
  s as (
    select sec.* from public.sections sec join w on w.id = sec.work_id
  ),
  leaves as (
    select s.id, jsonb_build_object(
      'id', s.id, 'ref', s.ref, 'level', s.level, 'ordinal', s.ordinal,
      'title_iast', s.title_iast, 'title_sa', s.title_sa, 'summary', s.summary,
      'verse_count', (select count(*) from public.verses v where v.section_id = s.id),
      'children', '[]'::jsonb) as node
    from s where not exists (select 1 from s c where c.parent_id = s.id)
  ),
  tops as (
    select s.id, jsonb_build_object(
      'id', s.id, 'ref', s.ref, 'level', s.level, 'ordinal', s.ordinal,
      'title_iast', s.title_iast, 'title_sa', s.title_sa, 'summary', s.summary,
      'verse_count', (select count(*) from public.verses v join s c on c.id = v.section_id where c.parent_id = s.id or c.id = s.id),
      'children', coalesce((select jsonb_agg(l.node order by (l.node->>'ordinal')::int) from leaves l join s c on c.id = l.id where c.parent_id = s.id), '[]'::jsonb)
    ) as node
    from s where s.parent_id is null
  )
  select jsonb_build_object(
    'work', (select to_jsonb(w) from w),
    'sections', coalesce((select jsonb_agg(node order by (node->>'ordinal')::int) from tops), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- Chapter payload: all verses of a section with contents of chosen editions
-- ---------------------------------------------------------------------------
-- p_edition_ids null => all public editions for the work.
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
        'audio', coalesce(a.segments, '[]'::jsonb)
      ) order by v.ordinal), '[]'::jsonb)
      from vs v left join content c on c.verse_id = v.id left join audio a on a.verse_id = v.id
    ),
    'tracks', (
      select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
        from public.audio_tracks t where t.section_id = p_section_id
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Single verse detail: renderings + graph + cross references
-- ---------------------------------------------------------------------------
create or replace function public.get_verse(p_work_slug text, p_ref text)
returns jsonb language sql stable as $$
  with v as (
    select v.* from public.verses v join public.works w on w.id = v.work_id
     where w.slug = p_work_slug and v.ref = p_ref
  )
  select jsonb_build_object(
    'verse', (select to_jsonb(v) from v),
    'section', (select to_jsonb(s) from public.sections s join v on v.section_id = s.id),
    'renderings', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'edition_id', vc.edition_id, 'edition_slug', e.slug, 'edition_title', e.title,
        'kind', e.kind, 'language_code', e.language_code, 'script_code', e.script_code,
        'is_machine', e.is_machine, 'attribution_text', e.attribution_text, 'license', e.license,
        'body', vc.body, 'body_html', vc.body_html,
        'word_meanings', vc.word_meanings, 'footnotes', vc.footnotes, 'notes', vc.notes
      ) order by e.sort_order), '[]'::jsonb)
      from public.verse_contents vc join public.v_editions e on e.id = vc.edition_id
      where vc.verse_id = (select id from v)
    ),
    'mentions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'entity_kind', m.entity_kind, 'entity_id', m.entity_id, 'role', m.role, 'surface_form', m.surface_form,
        'name_iast', case m.entity_kind
            when 'person' then (select name_iast from public.people  where id = m.entity_id)
            when 'place'  then (select name_iast from public.places  where id = m.entity_id)
            when 'topic'  then (select name_iast from public.topics  where id = m.entity_id)
            when 'story'  then (select title_iast from public.stories where id = m.entity_id) end,
        'slug', case m.entity_kind
            when 'person' then (select slug from public.people  where id = m.entity_id)
            when 'place'  then (select slug from public.places  where id = m.entity_id)
            when 'topic'  then (select slug from public.topics  where id = m.entity_id)
            when 'story'  then (select slug from public.stories where id = m.entity_id) end
      )), '[]'::jsonb)
      from public.verse_mentions m where m.verse_id = (select id from v)
    ),
    'cross_references', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'kind', x.kind, 'note', x.note, 'direction', case when x.from_verse_id = (select id from v) then 'out' else 'in' end,
        'verse_id', case when x.from_verse_id = (select id from v) then x.to_verse_id else x.from_verse_id end,
        'ref', (select ref from public.verses o where o.id = case when x.from_verse_id = (select id from v) then x.to_verse_id else x.from_verse_id end),
        'work_slug', (select w.slug from public.verses o join public.works w on w.id = o.work_id where o.id = case when x.from_verse_id = (select id from v) then x.to_verse_id else x.from_verse_id end)
      )), '[]'::jsonb)
      from public.cross_references x where x.from_verse_id = (select id from v) or x.to_verse_id = (select id from v)
    ),
    'prev_ref', (select p.ref from public.verses p join v on p.work_id = v.work_id
                  where string_to_array(p.ref,'.')::int[] < string_to_array(v.ref,'.')::int[]
                  order by string_to_array(p.ref,'.')::int[] desc limit 1),
    'next_ref', (select p.ref from public.verses p join v on p.work_id = v.work_id
                  where string_to_array(p.ref,'.')::int[] > string_to_array(v.ref,'.')::int[]
                  order by string_to_array(p.ref,'.')::int[] asc limit 1)
  );
$$;

-- ---------------------------------------------------------------------------
-- Entity detail (person / place / topic / story) with localized names + verses
-- ---------------------------------------------------------------------------
create or replace function public.get_entity(p_kind public.entity_kind, p_slug text)
returns jsonb language plpgsql stable as $$
declare
  eid uuid; base jsonb;
begin
  case p_kind
    when 'person' then select id, to_jsonb(p) into eid, base from public.people  p where slug = p_slug;
    when 'place'  then select id, to_jsonb(p) into eid, base from public.places  p where slug = p_slug;
    when 'topic'  then select id, to_jsonb(p) into eid, base from public.topics  p where slug = p_slug;
    when 'story'  then select id, to_jsonb(p) into eid, base from public.stories p where slug = p_slug;
    else raise exception 'unsupported entity kind %', p_kind;
  end case;
  if eid is null then return null; end if;

  return jsonb_build_object(
    'kind', p_kind,
    'entity', base,
    'names', (select coalesce(jsonb_agg(jsonb_build_object('language_code', n.language_code, 'script_code', n.script_code, 'name', n.name, 'description', n.description)), '[]'::jsonb)
                from public.entity_names n where n.entity_kind = p_kind and n.entity_id = eid),
    'verses', (select coalesce(jsonb_agg(jsonb_build_object('verse_id', v.id, 'ref', v.ref, 'work_slug', w.slug, 'role', m.role, 'surface_form', m.surface_form)
                                         order by string_to_array(v.ref,'.')::int[]), '[]'::jsonb)
                from public.verse_mentions m join public.verses v on v.id = m.verse_id join public.works w on w.id = v.work_id
               where m.entity_kind = p_kind and m.entity_id = eid),
    'relations_out', (select coalesce(jsonb_agg(jsonb_build_object('relation', r.relation, 'to_kind', r.to_kind, 'to_id', r.to_id, 'note', r.note)), '[]'::jsonb)
                from public.entity_relations r where r.from_kind = p_kind and r.from_id = eid),
    'relations_in', (select coalesce(jsonb_agg(jsonb_build_object('relation', r.relation, 'from_kind', r.from_kind, 'from_id', r.from_id, 'note', r.note)), '[]'::jsonb)
                from public.entity_relations r where r.to_kind = p_kind and r.to_id = eid)
  );
end $$;

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------
-- Full-text + trigram + diacritic-insensitive search over verse_contents.
-- Works with any language (uses 'simple' config; IAST folded column makes
-- "krishna"/"krsna" match "kṛṣṇa"). Also matches verse refs like "1.1.3".
create or replace function public.search_verses(
  p_query        text,
  p_work_slug    text default null,
  p_language     text default null,
  p_edition_ids  uuid[] default null,
  p_limit        int default 20,
  p_offset       int default 0
)
returns table (
  verse_id uuid, ref text, work_slug text, edition_id uuid, edition_title text,
  language_code text, script_code text, kind public.edition_kind,
  snippet text, rank real
) language sql stable as $$
  with q as (
    select trim(p_query) as raw, public.iast_fold(trim(p_query)) as folded,
           -- OR-query of all terms (ranked by how many match) so natural-language
           -- queries like "kali yuga short lives" still hit verses.
           (select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' | '))
              from regexp_split_to_table(public.iast_fold(trim(p_query)), '\s+') w where length(w) >= 2) as tsq
  ),
  ref_hit as (
    select v.id as verse_id from public.verses v join public.works w on w.id = v.work_id, q
     where v.ref = q.raw and (p_work_slug is null or w.slug = p_work_slug)
  ),
  -- verses that mention an entity whose name / epithet matches the query
  entity_hit as (
    select distinct m.verse_id
      from public.verse_mentions m, q
     where length(q.folded) >= 3 and (
           exists (select 1 from public.people p where p.id = m.entity_id and m.entity_kind = 'person'
                    and (public.iast_fold(p.name_iast) like '%'||q.folded||'%' or exists (select 1 from unnest(p.epithets) ep where public.iast_fold(ep) like '%'||q.folded||'%')))
        or exists (select 1 from public.places p where p.id = m.entity_id and m.entity_kind = 'place'
                    and (public.iast_fold(p.name_iast) like '%'||q.folded||'%' or exists (select 1 from unnest(p.alt_names) ep where public.iast_fold(ep) like '%'||q.folded||'%')))
        or exists (select 1 from public.topics t where t.id = m.entity_id and m.entity_kind = 'topic' and public.iast_fold(t.name_iast) like '%'||q.folded||'%')
        or exists (select 1 from public.entity_names n where n.entity_id = m.entity_id and n.entity_kind = m.entity_kind and (n.folded like '%'||q.folded||'%' or n.name like '%'||q.raw||'%'))
     )
  ),
  hits as (
    select vc.verse_id, v.ref, w.slug as work_slug, vc.edition_id, e.title as edition_title,
           e.language_code, e.script_code, e.kind, vc.body, vc.folded,
           greatest(
             case when q.tsq is not null then ts_rank_cd(to_tsvector('simple', vc.folded), q.tsq, 32) else 0 end,
             case when vc.folded like '%' || q.folded || '%' then 0.9 else 0 end,
             case when exists (select 1 from ref_hit r where r.verse_id = vc.verse_id) then 1.0 else 0 end,
             case when exists (select 1 from entity_hit r where r.verse_id = vc.verse_id) then 0.6 else 0 end
           )::real as rank
      from public.verse_contents vc
      join public.verses v on v.id = vc.verse_id
      join public.works w on w.id = v.work_id
      join public.editions e on e.id = vc.edition_id, q
     where (p_work_slug is null or w.slug = p_work_slug)
       and (p_language is null or e.language_code = p_language)
       and (p_edition_ids is null or e.id = any(p_edition_ids))
       and (
            (q.tsq is not null and to_tsvector('simple', vc.folded) @@ q.tsq)
         or vc.folded like '%' || q.folded || '%'
         or exists (select 1 from ref_hit r where r.verse_id = vc.verse_id)
         or (exists (select 1 from entity_hit r where r.verse_id = vc.verse_id) and e.kind in ('translation','base_text','transliteration'))
       )
  )
  select h.verse_id, h.ref, h.work_slug, h.edition_id, h.edition_title, h.language_code, h.script_code, h.kind,
         case when (select tsq from q) is not null
              then ts_headline('simple', h.body, (select tsq from q), 'MaxWords=30, MinWords=12, StartSel=«, StopSel=»')
              else left(h.body, 160) end as snippet,
         h.rank
    from hits h
   order by h.rank desc, string_to_array(h.ref,'.')::int[], h.kind
   limit greatest(1, least(p_limit, 100)) offset greatest(0, p_offset);
$$;

-- Search graph entities by name in any language/script.
create or replace function public.search_entities(p_query text, p_limit int default 20)
returns table (entity_kind public.entity_kind, entity_id uuid, slug text, name_iast text, matched_name text, language_code text)
language sql stable as $$
  with q as (select public.iast_fold(trim(p_query)) as f)
  select * from (
    select 'person'::public.entity_kind, p.id, p.slug, p.name_iast, p.name_iast, 'sa'::text from public.people p, q
     where public.iast_fold(p.name_iast) like '%'||q.f||'%' or exists (select 1 from unnest(p.epithets) ep where public.iast_fold(ep) like '%'||q.f||'%')
    union
    select 'place', p.id, p.slug, p.name_iast, p.name_iast, 'sa' from public.places p, q
     where public.iast_fold(p.name_iast) like '%'||q.f||'%' or exists (select 1 from unnest(p.alt_names) ep where public.iast_fold(ep) like '%'||q.f||'%')
    union
    select 'topic', t.id, t.slug, t.name_iast, t.name_iast, 'sa' from public.topics t, q where public.iast_fold(t.name_iast) like '%'||q.f||'%'
    union
    select 'story', s.id, s.slug, s.title_iast, s.title_iast, 'sa' from public.stories s, q where public.iast_fold(s.title_iast) like '%'||q.f||'%'
    union
    select n.entity_kind, n.entity_id,
           case n.entity_kind when 'person' then (select slug from public.people where id = n.entity_id)
                              when 'place'  then (select slug from public.places where id = n.entity_id)
                              when 'topic'  then (select slug from public.topics where id = n.entity_id)
                              when 'story'  then (select slug from public.stories where id = n.entity_id) end,
           case n.entity_kind when 'person' then (select name_iast from public.people where id = n.entity_id)
                              when 'place'  then (select name_iast from public.places where id = n.entity_id)
                              when 'topic'  then (select name_iast from public.topics where id = n.entity_id)
                              when 'story'  then (select title_iast from public.stories where id = n.entity_id) end,
           n.name, n.language_code
      from public.entity_names n, q where n.folded like '%'||q.f||'%' or n.name like '%'||trim(p_query)||'%'
  ) x
  limit greatest(1, least(p_limit, 100));
$$;

-- ---------------------------------------------------------------------------
-- Reading progress / bookmarks helpers (upsert-friendly for offline sync)
-- ---------------------------------------------------------------------------
create or replace function public.upsert_progress(p_work_id uuid, p_verse_id uuid, p_edition_ids uuid[] default '{}', p_device_id text default null)
returns public.reading_progress language plpgsql security invoker as $$
declare
  rp public.reading_progress; total int; pos int; sec uuid; vref text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select section_id, ref into sec, vref from public.verses where id = p_verse_id and work_id = p_work_id;
  if sec is null then raise exception 'verse not in work'; end if;
  select count(*) into total from public.verses where work_id = p_work_id;
  pos := public.verse_seq(p_work_id, vref) + 1;
  insert into public.reading_progress (user_id, work_id, verse_id, section_id, percent, edition_ids, device_id, last_read_at)
  values (auth.uid(), p_work_id, p_verse_id, sec, round(100.0 * pos / greatest(total,1), 2), p_edition_ids, p_device_id, now())
  on conflict (user_id, work_id) do update
    set verse_id = excluded.verse_id, section_id = excluded.section_id, percent = excluded.percent,
        edition_ids = excluded.edition_ids, device_id = excluded.device_id, last_read_at = now()
  returning * into rp;
  insert into public.verse_reads (user_id, verse_id) values (auth.uid(), p_verse_id) on conflict do nothing;
  return rp;
end $$;

-- Pull everything the user owns, changed since a timestamp (delta sync).
create or replace function public.sync_pull(p_since timestamptz default '-infinity')
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'server_time', now(),
    'bookmarks', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) from public.bookmarks b where b.user_id = auth.uid() and b.updated_at > p_since),
    'progress',  (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.reading_progress p where p.user_id = auth.uid() and p.updated_at > p_since)
  );
$$;

-- ---------------------------------------------------------------------------
-- Offline bundle: everything public for one work in one call (cached on device)
-- ---------------------------------------------------------------------------
create or replace function public.get_work_bundle(p_work_slug text)
returns jsonb language sql stable as $$
  with w as (select * from public.works where slug = p_work_slug)
  select jsonb_build_object(
    'generated_at', now(),
    'toc', public.get_toc(p_work_slug),
    'editions', (select coalesce(jsonb_agg(to_jsonb(ve) order by ve.sort_order), '[]'::jsonb) from public.v_editions ve join w on w.id = ve.work_id),
    'sections', (
      select coalesce(jsonb_agg(public.get_section_verses(s.id) order by string_to_array(s.ref,'.')::int[]), '[]'::jsonb)
        from public.sections s join w on w.id = s.work_id
       where exists (select 1 from public.verses v where v.section_id = s.id)
    ),
    'people',  (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.people p),
    'places',  (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.places p),
    'topics',  (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.topics p),
    'stories', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.stories p join w on w.id = p.work_id),
    'entity_names', (select coalesce(jsonb_agg(to_jsonb(n) - 'folded'), '[]'::jsonb) from public.entity_names n),
    'mentions', (select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) from public.verse_mentions m join public.verses v on v.id = m.verse_id join w on w.id = v.work_id),
    'cross_references', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.cross_references x join public.verses v on v.id = x.from_verse_id join w on w.id = v.work_id)
  );
$$;

-- ---------------------------------------------------------------------------
-- AI retrieval: verses relevant to a question (lexical; vector added in 0008)
-- ---------------------------------------------------------------------------
create or replace function public.retrieve_for_qa(p_query text, p_work_slug text default null, p_language text default 'en', p_limit int default 8)
returns table (verse_id uuid, ref text, work_slug text, edition_id uuid, edition_title text, language_code text, body text, attribution_text text, rank real)
language sql stable as $$
  with hits as (
    -- search only the translation in the requested language + IAST, so scores
    -- reflect meaning rather than how many script variants exist
    select * from public.search_verses(p_query, p_work_slug, null,
             (select array_agg(e.id) from public.editions e join public.works w on w.id = e.work_id
               where (p_work_slug is null or w.slug = p_work_slug)
                 and ((e.kind = 'translation' and e.language_code = p_language) or (e.kind = 'transliteration' and e.script_code = 'Latn') or e.kind = 'word_meanings')),
             60, 0)
  ),
  best as (
    select h.verse_id, h.ref, h.work_slug, sum(h.rank)::real as rank
      from hits h group by h.verse_id, h.ref, h.work_slug
  ),
  top as (select * from best order by rank desc, string_to_array(ref,'.')::int[] limit greatest(1, least(p_limit, 20)))
  select b.verse_id, b.ref, b.work_slug, vc.edition_id, e.title, e.language_code, vc.body, e.attribution_text, b.rank
    from top b
    join public.verse_contents vc on vc.verse_id = b.verse_id
    join public.v_editions e on e.id = vc.edition_id
   where (e.kind = 'translation' and e.language_code = p_language)
      or (e.kind = 'transliteration' and e.script_code = 'Latn')
   order by b.rank desc, string_to_array(b.ref,'.')::int[], e.sort_order;
$$;

grant execute on all functions in schema public to anon, authenticated, service_role;

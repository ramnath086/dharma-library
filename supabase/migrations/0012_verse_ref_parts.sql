-- =============================================================================
-- 0012: verse refs may carry a duplicate suffix (1.13.40b, 7.4.32b)
-- =============================================================================
-- Wikisource sometimes prints the same number twice; we keep the second as
-- `{n}b` and must not cast that token to int.

create or replace function public.verse_ref_parts(v_ref text)
returns int[] language sql immutable parallel safe as $$
  select array[
    coalesce(nullif(split_part(regexp_replace(v_ref, '[^0-9.]+$', ''), '.', 1), '')::int, 0),
    coalesce(nullif(split_part(regexp_replace(v_ref, '[^0-9.]+$', ''), '.', 2), '')::int, 0),
    coalesce(nullif(split_part(regexp_replace(v_ref, '[^0-9.]+$', ''), '.', 3), '')::int, 0),
    case when v_ref ~ '[a-z]$' then ascii(right(v_ref, 1)) - ascii('a') + 1 else 0 end
  ];
$$;
grant execute on function public.verse_ref_parts(text) to anon, authenticated, service_role;

create or replace function public.verse_seq(v_work uuid, v_ref text)
returns int language sql stable as $$
  select count(*)::int from public.verses x
   where x.work_id = v_work
     and public.verse_ref_parts(x.ref) < public.verse_ref_parts(v_ref);
$$;

-- next/prev on get_verse used string_to_array(ref,'.')::int[] and threw on *b.
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
                  where public.verse_ref_parts(p.ref) < public.verse_ref_parts(v.ref)
                  order by public.verse_ref_parts(p.ref) desc limit 1),
    'next_ref', (select p.ref from public.verses p join v on p.work_id = v.work_id
                  where public.verse_ref_parts(p.ref) > public.verse_ref_parts(v.ref)
                  order by public.verse_ref_parts(p.ref) asc limit 1)
  );
$$;
grant execute on function public.get_verse(text, text) to anon, authenticated, service_role;

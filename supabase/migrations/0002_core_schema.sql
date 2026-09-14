-- =============================================================================
-- Dharma Library — 0002: core content schema
-- =============================================================================
-- Generic scripture model. One "work" (e.g. Śrīmad Bhāgavata Purāṇa) has a
-- hierarchy of "sections" (canto → chapter …) containing "verses". Every
-- textual rendering of a verse — base Sanskrit, transliteration, translation,
-- word-meanings, commentary — is a row in verse_contents belonging to an
-- "edition". Editions carry language, script, source and (mandatory) rights.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  display_name        text,
  role                public.user_role not null default 'reader',
  preferred_language  text not null default 'en',
  preferred_script    text not null default 'Deva',
  settings            jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile when a user signs up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Languages & scripts
-- ---------------------------------------------------------------------------
create table public.languages (
  code            text primary key,                 -- BCP-47 primary subtag: sa, en, ml, hi, ta, te, kn, bn, gu, pa
  name_en         text not null,
  name_native     text not null,
  default_script  text not null,                    -- ISO 15924
  direction       text not null default 'ltr' check (direction in ('ltr', 'rtl')),
  is_ui_locale    boolean not null default false,   -- app UI available in this language
  sort_order      int not null default 100
);

create table public.scripts (
  code        text primary key,                     -- ISO 15924: Deva, Mlym, Latn, Knda, Taml, Telu, Beng, Gujr, Guru
  name_en     text not null,
  name_native text not null,
  sample      text,                                 -- e.g. 'ॐ' shown in script picker
  sort_order  int not null default 100
);

alter table public.languages
  add constraint languages_default_script_fkey foreign key (default_script) references public.scripts (code);
alter table public.profiles
  add constraint profiles_pref_lang_fkey foreign key (preferred_language) references public.languages (code),
  add constraint profiles_pref_script_fkey foreign key (preferred_script) references public.scripts (code);

-- ---------------------------------------------------------------------------
-- Sources & rights (mandatory provenance)
-- ---------------------------------------------------------------------------
create table public.sources (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,
  title         text not null,
  authors       text[] not null default '{}',
  publisher     text,
  year          int,
  edition_note  text,
  url           text,
  isbn          text,
  archive_url   text,                               -- e.g. archive.org / GRETIL / Wikisource permalink
  kind          text not null default 'book' check (kind in ('book', 'manuscript', 'digital_text', 'website', 'recording', 'dataset', 'original')),
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger trg_sources_updated before update on public.sources
  for each row execute function public.set_updated_at();

create table public.rights (
  id                      uuid primary key default gen_random_uuid(),
  source_id               uuid references public.sources (id) on delete set null,
  status                  public.rights_status not null,
  license                 text,                     -- SPDX-ish: 'CC-BY-SA-4.0', 'CC0-1.0', 'PD', 'Proprietary'
  license_url             text,
  rights_holder           text,
  attribution_text        text not null,            -- what we must display
  permission_document_url text,                     -- private storage path of signed permission (admins only)
  permission_granted_on   date,
  permission_expires_on   date,
  territory               text not null default 'worldwide',
  allows_commercial       boolean not null default false,
  allows_derivatives      boolean not null default false,
  allows_audio            boolean not null default false,
  notes                   text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint rights_permission_needs_doc check (
    status <> 'permission_granted' or permission_document_url is not null
  )
);
create trigger trg_rights_updated before update on public.rights
  for each row execute function public.set_updated_at();

-- A rights row is "cleared" when we may lawfully serve the content.
create or replace function public.rights_is_cleared(r public.rights)
returns boolean language sql immutable parallel safe as $$
  select r.status in ('public_domain', 'open_license', 'permission_granted', 'original')
     and (r.permission_expires_on is null or r.permission_expires_on >= current_date);
$$;

-- ---------------------------------------------------------------------------
-- Works
-- ---------------------------------------------------------------------------
create table public.works (
  id                 uuid primary key default gen_random_uuid(),
  slug               text not null unique,                 -- 'bhagavata-purana'
  title_iast         text not null,                        -- 'Śrīmad Bhāgavata Purāṇa'
  title_sa           text not null,                        -- Devanagari
  short_code         text not null unique,                 -- 'SB'
  tradition          text,                                 -- 'Vaiṣṇava', 'Purāṇa'
  original_language  text not null references public.languages (code),
  original_script    text not null references public.scripts (code),
  -- Names of each hierarchy level, top-down. Bhāgavatam: canto/skandha, chapter/adhyāya.
  structure          jsonb not null default '[]'::jsonb,   -- [{"level":1,"key":"canto","label_iast":"Skandha"}, ...]
  description        text,
  status             public.publish_status not null default 'draft',
  sort_order         int not null default 100,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create trigger trg_works_updated before update on public.works
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Sections (self-referential hierarchy)
-- ---------------------------------------------------------------------------
create table public.sections (
  id          uuid primary key default gen_random_uuid(),
  work_id     uuid not null references public.works (id) on delete cascade,
  parent_id   uuid references public.sections (id) on delete cascade,
  level       int  not null check (level >= 1),
  ordinal     int  not null check (ordinal >= 0),
  ref         text not null,                                -- '1' , '1.1'
  title_iast  text,                                         -- 'Praśnaḥ — Questions by the Sages'
  title_sa    text,
  summary     text,
  verse_count int  not null default 0,
  status      public.publish_status not null default 'draft',
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (work_id, ref),
  unique (work_id, parent_id, ordinal)
);
create index sections_parent_idx on public.sections (parent_id, ordinal);
create index sections_work_level_idx on public.sections (work_id, level, ordinal);
create trigger trg_sections_updated before update on public.sections
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Verses (leaf units; language-neutral identity)
-- ---------------------------------------------------------------------------
create table public.verses (
  id          uuid primary key default gen_random_uuid(),
  work_id     uuid not null references public.works (id) on delete cascade,
  section_id  uuid not null references public.sections (id) on delete cascade,
  ordinal     int  not null check (ordinal >= 0),
  ref         text not null,                                -- '1.1.1'
  kind        public.verse_kind not null default 'verse',
  meter       text,                                         -- 'anuṣṭubh', 'triṣṭubh' …
  speaker_id  uuid,                                         -- fk to people added in 0004
  status      public.publish_status not null default 'draft',
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (work_id, ref),
  unique (section_id, ordinal)
);
create index verses_section_idx on public.verses (section_id, ordinal);
create trigger trg_verses_updated before update on public.verses
  for each row execute function public.set_updated_at();

-- Global reading order within a work (for next/prev, progress %).
create or replace function public.verse_seq(v_work uuid, v_ref text)
returns int language sql stable as $$
  select count(*)::int from public.verses x
   where x.work_id = v_work
     and string_to_array(x.ref, '.')::int[] < string_to_array(v_ref, '.')::int[];
$$;

-- ---------------------------------------------------------------------------
-- Editions — a coherent set of renderings of a work
-- ---------------------------------------------------------------------------
create table public.editions (
  id             uuid primary key default gen_random_uuid(),
  work_id        uuid not null references public.works (id) on delete cascade,
  slug           text not null unique,                      -- 'sb-mula-deva', 'sb-en-dl'
  kind           public.edition_kind not null,
  language_code  text not null references public.languages (code),
  script_code    text not null references public.scripts (code),
  title          text not null,
  contributors   text[] not null default '{}',              -- translators / editors / reciters
  source_id      uuid references public.sources (id) on delete restrict,
  rights_id      uuid not null references public.rights (id) on delete restrict,
  derived_from   uuid references public.editions (id) on delete set null,  -- e.g. transliteration of base text
  is_default     boolean not null default false,            -- default pick for its (kind, language)
  is_machine     boolean not null default false,            -- machine transliteration / draft MT (always labelled)
  status         public.publish_status not null default 'draft',
  sort_order     int not null default 100,
  description    text,
  metadata       jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index editions_work_idx on public.editions (work_id, kind, language_code);
create trigger trg_editions_updated before update on public.editions
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Verse contents — the actual text
-- ---------------------------------------------------------------------------
create table public.verse_contents (
  id            uuid primary key default gen_random_uuid(),
  verse_id      uuid not null references public.verses (id) on delete cascade,
  edition_id    uuid not null references public.editions (id) on delete cascade,
  body          text not null,                              -- plain text; lines separated by \n
  body_html     text,                                       -- optional rich rendering (sanitised)
  -- word_meanings: [{"word":"janmādy","meaning":"birth etc."}]  footnotes: [{"n":1,"text":"…"}]
  word_meanings jsonb,
  footnotes     jsonb,
  notes         text,                                       -- editorial notes (public)
  folded        text generated always as (public.iast_fold(body)) stored,
  status        public.publish_status not null default 'draft',
  metadata      jsonb not null default '{}'::jsonb,
  created_by    uuid references public.profiles (id) on delete set null,
  updated_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (verse_id, edition_id)
);
create index verse_contents_edition_idx on public.verse_contents (edition_id);
create trigger trg_verse_contents_updated before update on public.verse_contents
  for each row execute function public.set_updated_at();

-- Section-level text per edition (chapter titles, introductions, summaries)
create table public.section_contents (
  id          uuid primary key default gen_random_uuid(),
  section_id  uuid not null references public.sections (id) on delete cascade,
  edition_id  uuid not null references public.editions (id) on delete cascade,
  title       text,
  intro       text,
  summary     text,
  status      public.publish_status not null default 'draft',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (section_id, edition_id)
);
create trigger trg_section_contents_updated before update on public.section_contents
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Cross references between verses
-- ---------------------------------------------------------------------------
create table public.cross_references (
  id            uuid primary key default gen_random_uuid(),
  from_verse_id uuid not null references public.verses (id) on delete cascade,
  to_verse_id   uuid not null references public.verses (id) on delete cascade,
  kind          public.xref_kind not null default 'see_also',
  note          text,
  source_id     uuid references public.sources (id) on delete set null,
  status        public.publish_status not null default 'draft',
  created_at    timestamptz not null default now(),
  check (from_verse_id <> to_verse_id),
  unique (from_verse_id, to_verse_id, kind)
);
create index xref_to_idx on public.cross_references (to_verse_id);

-- ---------------------------------------------------------------------------
-- Audit log & content versioning (used by admin CMS)
-- ---------------------------------------------------------------------------
create table public.audit_log (
  id          bigint generated always as identity primary key,
  table_name  text not null,
  row_id      uuid,
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_data    jsonb,
  new_data    jsonb,
  actor_id    uuid,
  at          timestamptz not null default now()
);
create index audit_log_row_idx on public.audit_log (table_name, row_id, at desc);

create or replace function public.audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
begin
  if tg_op = 'DELETE' then
    rid := (to_jsonb(old) ->> 'id')::uuid;
    insert into public.audit_log (table_name, row_id, action, old_data, actor_id)
    values (tg_table_name, rid, tg_op, to_jsonb(old), auth.uid());
    return old;
  else
    rid := (to_jsonb(new) ->> 'id')::uuid;
    insert into public.audit_log (table_name, row_id, action, old_data, new_data, actor_id)
    values (tg_table_name, rid, tg_op,
            case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new), auth.uid());
    return new;
  end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['works','sections','verses','editions','verse_contents','section_contents','sources','rights','cross_references']
  loop
    execute format('create trigger trg_audit_%1$s after insert or update or delete on public.%1$s for each row execute function public.audit_row()', t);
  end loop;
end $$;

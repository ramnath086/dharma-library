-- =============================================================================
-- Dharma Library — 0003: knowledge graph (people, places, stories, topics)
-- =============================================================================
-- Entities are language-neutral rows; human-readable names live in *_names
-- tables keyed by language + script so every entity can be shown in
-- Devanagari, IAST, Malayalam, English … Mentions link entities to verses
-- and to each other.
-- =============================================================================

create table public.people (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,                 -- 'vyasa', 'suta-goswami'
  kind        public.person_kind not null default 'other',
  name_iast   text not null,
  name_sa     text not null,
  epithets    text[] not null default '{}',         -- alternate names, IAST
  gender      text check (gender in ('m','f','n','unknown')),
  description text,
  source_id   uuid references public.sources (id) on delete set null,
  status      public.publish_status not null default 'draft',
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_people_updated before update on public.people for each row execute function public.set_updated_at();

alter table public.verses
  add constraint verses_speaker_fkey foreign key (speaker_id) references public.people (id) on delete set null;

create table public.places (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,                 -- 'naimisaranya'
  kind        public.place_kind not null default 'other',
  name_iast   text not null,
  name_sa     text not null,
  alt_names   text[] not null default '{}',
  description text,
  modern_name text,                                 -- 'Nimsar, Sitapur district, Uttar Pradesh'
  latitude    double precision,
  longitude   double precision,
  source_id   uuid references public.sources (id) on delete set null,
  status      public.publish_status not null default 'draft',
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_places_updated before update on public.places for each row execute function public.set_updated_at();

create table public.topics (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,                 -- 'bhakti', 'dharma', 'satyam-param'
  parent_id   uuid references public.topics (id) on delete set null,
  name_iast   text not null,
  name_sa     text,
  description text,
  status      public.publish_status not null default 'draft',
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_topics_updated before update on public.topics for each row execute function public.set_updated_at();

-- A story is a narrative unit spanning a verse range (may cross chapters).
create table public.stories (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,               -- 'sages-question-suta-at-naimisaranya'
  work_id       uuid not null references public.works (id) on delete cascade,
  title_iast    text not null,
  title_sa      text,
  summary       text,
  start_verse_id uuid references public.verses (id) on delete set null,
  end_verse_id   uuid references public.verses (id) on delete set null,
  parent_id     uuid references public.stories (id) on delete set null,   -- nested narration frames
  narrator_id   uuid references public.people (id) on delete set null,
  place_id      uuid references public.places (id) on delete set null,
  status        public.publish_status not null default 'draft',
  metadata      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger trg_stories_updated before update on public.stories for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Localised names / descriptions for graph entities
-- ---------------------------------------------------------------------------
create table public.entity_names (
  id            uuid primary key default gen_random_uuid(),
  entity_kind   public.entity_kind not null,
  entity_id     uuid not null,
  language_code text not null references public.languages (code),
  script_code   text not null references public.scripts (code),
  name          text not null,
  description   text,
  is_primary    boolean not null default true,
  folded        text generated always as (public.iast_fold(name)) stored,
  unique (entity_kind, entity_id, language_code, script_code, name)
);
create index entity_names_lookup_idx on public.entity_names (entity_kind, entity_id, language_code);

-- ---------------------------------------------------------------------------
-- Mentions: entity ↔ verse (or ↔ section) with role
-- ---------------------------------------------------------------------------
create table public.verse_mentions (
  id          uuid primary key default gen_random_uuid(),
  verse_id    uuid not null references public.verses (id) on delete cascade,
  entity_kind public.entity_kind not null check (entity_kind in ('person','place','story','topic')),
  entity_id   uuid not null,
  role        text,                                  -- 'speaker','addressee','subject','setting','theme'
  surface_form text,                                 -- how it appears in the verse, e.g. 'satyaṁ param'
  confidence  real not null default 1.0 check (confidence between 0 and 1),
  status      public.publish_status not null default 'draft',
  created_at  timestamptz not null default now(),
  unique (verse_id, entity_kind, entity_id, role)
);
create index verse_mentions_entity_idx on public.verse_mentions (entity_kind, entity_id);
create index verse_mentions_verse_idx on public.verse_mentions (verse_id);

-- Generic entity ↔ entity relations (person→person 'son_of', story→topic, …)
create table public.entity_relations (
  id          uuid primary key default gen_random_uuid(),
  from_kind   public.entity_kind not null,
  from_id     uuid not null,
  relation    text not null,                          -- 'son_of','disciple_of','located_in','narrates','about'
  to_kind     public.entity_kind not null,
  to_id       uuid not null,
  note        text,
  source_id   uuid references public.sources (id) on delete set null,
  status      public.publish_status not null default 'draft',
  created_at  timestamptz not null default now(),
  unique (from_kind, from_id, relation, to_kind, to_id)
);
create index entity_relations_from_idx on public.entity_relations (from_kind, from_id);
create index entity_relations_to_idx   on public.entity_relations (to_kind, to_id);

-- Ensure the polymorphic entity ids actually exist.
create or replace function public.entity_exists(k public.entity_kind, i uuid)
returns boolean language plpgsql stable as $$
declare ok boolean;
begin
  case k
    when 'person'  then select exists(select 1 from public.people   where id = i) into ok;
    when 'place'   then select exists(select 1 from public.places   where id = i) into ok;
    when 'story'   then select exists(select 1 from public.stories  where id = i) into ok;
    when 'topic'   then select exists(select 1 from public.topics   where id = i) into ok;
    when 'work'    then select exists(select 1 from public.works    where id = i) into ok;
    when 'section' then select exists(select 1 from public.sections where id = i) into ok;
    when 'verse'   then select exists(select 1 from public.verses   where id = i) into ok;
  end case;
  return coalesce(ok, false);
end $$;

create or replace function public.check_entity_ref()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'entity_names' or tg_table_name = 'verse_mentions' then
    if not public.entity_exists(new.entity_kind, new.entity_id) then
      raise exception 'entity % % does not exist', new.entity_kind, new.entity_id;
    end if;
  elsif tg_table_name = 'entity_relations' then
    if not public.entity_exists(new.from_kind, new.from_id) then
      raise exception 'from entity % % does not exist', new.from_kind, new.from_id;
    end if;
    if not public.entity_exists(new.to_kind, new.to_id) then
      raise exception 'to entity % % does not exist', new.to_kind, new.to_id;
    end if;
  end if;
  return new;
end $$;

create trigger trg_entity_names_ref     before insert or update on public.entity_names     for each row execute function public.check_entity_ref();
create trigger trg_verse_mentions_ref   before insert or update on public.verse_mentions   for each row execute function public.check_entity_ref();
create trigger trg_entity_relations_ref before insert or update on public.entity_relations for each row execute function public.check_entity_ref();

do $$
declare t text;
begin
  foreach t in array array['people','places','topics','stories','entity_names','verse_mentions','entity_relations']
  loop
    execute format('create trigger trg_audit_%1$s after insert or update or delete on public.%1$s for each row execute function public.audit_row()', t);
  end loop;
end $$;

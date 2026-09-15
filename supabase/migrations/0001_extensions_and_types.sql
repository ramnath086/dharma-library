-- =============================================================================
-- Dharma Library — 0001: extensions, enums, helper functions
-- =============================================================================
-- Idempotent where possible. Designed for Supabase (PostgreSQL 15/16).
-- Extensions that may be unavailable in minimal local Postgres builds are
-- created with a guard so the migration chain still runs there.
-- =============================================================================

do $$
begin
  -- pgcrypto: gen_random_uuid() is built-in since PG13, but Supabase ships it.
  begin execute 'create extension if not exists pgcrypto'; exception when others then raise notice 'pgcrypto unavailable: %', sqlerrm; end;
  begin execute 'create extension if not exists pg_trgm';  exception when others then raise notice 'pg_trgm unavailable: %',  sqlerrm; end;
  begin execute 'create extension if not exists unaccent'; exception when others then raise notice 'unaccent unavailable: %', sqlerrm; end;
  begin execute 'create extension if not exists vector';   exception when others then raise notice 'vector unavailable: %',   sqlerrm; end;
end $$;

-- ---------------------------------------------------------------------------
-- Enumerations
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('reader', 'contributor', 'editor', 'admin');

create type public.publish_status as enum ('draft', 'in_review', 'published', 'archived');

-- Rights: how we are allowed to use a piece of content. Nothing is served to
-- readers unless its rights row is one of the "cleared" statuses
-- (public_domain, open_license, permission_granted, original).
create type public.rights_status as enum (
  'public_domain',        -- copyright expired / never applied
  'open_license',         -- CC-BY, CC-BY-SA, CC0, etc.
  'permission_granted',   -- written permission from rights holder on file
  'original',             -- created by / for Dharma Library, licensed by us
  'pending',              -- requested, awaiting answer — NOT servable
  'restricted'            -- all rights reserved — NOT servable
);

create type public.edition_kind as enum (
  'base_text',            -- the scripture itself (mūla)
  'transliteration',      -- machine/human transliteration of a base text
  'translation',
  'word_meanings',
  'commentary',
  'summary',
  'audio'
);

create type public.verse_kind as enum ('verse', 'prose', 'invocation', 'colophon', 'heading');

create type public.entity_kind as enum ('person', 'place', 'story', 'topic', 'work', 'section', 'verse');

create type public.person_kind as enum (
  'deity', 'avatara', 'sage', 'king', 'queen', 'devotee', 'demon', 'author', 'narrator', 'other'
);

create type public.place_kind as enum ('forest', 'city', 'river', 'mountain', 'tirtha', 'loka', 'kingdom', 'other');

create type public.xref_kind as enum ('parallel', 'quotation', 'commentary_ref', 'see_also', 'continuation', 'contrast');

create type public.audio_kind as enum ('recitation', 'chanting', 'translation_reading', 'discourse', 'music');

create type public.qa_role as enum ('user', 'assistant', 'system');

-- ---------------------------------------------------------------------------
-- Helper: updated_at trigger
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Helper: immutable unaccent wrapper for indexes (falls back if unaccent absent)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'unaccent') then
    execute $f$
      create or replace function public.dl_unaccent(text) returns text
      language sql immutable parallel safe as
      $b$ select public.unaccent('public.unaccent', $1) $b$;
    $f$;
  else
    execute $f$
      create or replace function public.dl_unaccent(text) returns text
      language sql immutable parallel safe as
      $b$ select $1 $b$;
    $f$;
  end if;
end $$;

-- Strip IAST diacritics to plain ASCII so "krsna" / "krishna" match "kṛṣṇa".
-- Also normalises the common popular spellings "sh" (for ś/ṣ) and "ri" (for ṛ)
-- so that "krishna" / "vishnu" match "kṛṣṇa" / "viṣṇu".
create or replace function public.iast_fold(txt text)
returns text language sql immutable parallel safe as $$
  select replace(replace(replace(lower(
    translate(
      public.dl_unaccent(coalesce(txt, '')),
      'āīūṛṝḷḹṃṁḥṅñṭḍṇśṣĀĪŪṚṜḶḸṀḤṄÑṬḌṆŚṢ''’',
      'aiurrllmmhnntdnssAIURRLLMHNNTDNSS'
    )
  ), 'sh', 's'), 'ri', 'r'), 'ee', 'i');
$$;

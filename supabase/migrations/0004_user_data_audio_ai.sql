-- =============================================================================
-- Dharma Library — 0004: user data (bookmarks, progress), audio, AI Q&A
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Bookmarks & highlights
-- ---------------------------------------------------------------------------
create table public.bookmarks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  verse_id    uuid not null references public.verses (id) on delete cascade,
  edition_id  uuid references public.editions (id) on delete set null,   -- which rendering was bookmarked
  note        text,
  color       text check (color is null or color ~ '^#[0-9a-fA-F]{6}$'),
  tags        text[] not null default '{}',
  client_id   text,                                  -- for offline sync idempotency
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, verse_id)
);
create index bookmarks_user_idx on public.bookmarks (user_id, created_at desc);
create trigger trg_bookmarks_updated before update on public.bookmarks for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Reading progress (one row per user per work — "continue reading")
-- ---------------------------------------------------------------------------
create table public.reading_progress (
  user_id         uuid not null references public.profiles (id) on delete cascade,
  work_id         uuid not null references public.works (id) on delete cascade,
  verse_id        uuid not null references public.verses (id) on delete cascade,
  section_id      uuid references public.sections (id) on delete set null,
  percent         numeric(5,2) not null default 0 check (percent between 0 and 100),
  edition_ids     uuid[] not null default '{}',      -- the reader layout the user had open
  device_id       text,
  last_read_at    timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (user_id, work_id)
);
create trigger trg_reading_progress_updated before update on public.reading_progress for each row execute function public.set_updated_at();

-- Verses the user has marked as read (for completion stats / streaks).
create table public.verse_reads (
  user_id   uuid not null references public.profiles (id) on delete cascade,
  verse_id  uuid not null references public.verses (id) on delete cascade,
  read_at   timestamptz not null default now(),
  primary key (user_id, verse_id)
);

-- ---------------------------------------------------------------------------
-- Audio
-- ---------------------------------------------------------------------------
-- audio_tracks are files (in Supabase Storage bucket 'audio' or an external
-- CDN); audio_segments map time ranges to verses so the reader can
-- highlight/seek. Every track belongs to an edition (kind = 'audio') which
-- carries language, reciter (contributors) and — mandatory — rights.
create table public.audio_tracks (
  id              uuid primary key default gen_random_uuid(),
  edition_id      uuid not null references public.editions (id) on delete cascade,
  section_id      uuid references public.sections (id) on delete cascade,   -- typically one track per chapter
  kind            public.audio_kind not null default 'recitation',
  title           text not null,
  storage_bucket  text not null default 'audio',
  storage_path    text,                                                      -- 'sb/1/1/recitation.m4a'
  external_url    text,                                                      -- alternative: CDN / archive.org
  mime_type       text not null default 'audio/mp4',
  duration_ms     int check (duration_ms is null or duration_ms >= 0),
  bitrate_kbps    int,
  size_bytes      bigint,
  checksum_sha256 text,
  status          public.publish_status not null default 'draft',
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (storage_path is not null or external_url is not null)
);
create index audio_tracks_section_idx on public.audio_tracks (section_id);
create trigger trg_audio_tracks_updated before update on public.audio_tracks for each row execute function public.set_updated_at();

create table public.audio_segments (
  id        uuid primary key default gen_random_uuid(),
  track_id  uuid not null references public.audio_tracks (id) on delete cascade,
  verse_id  uuid not null references public.verses (id) on delete cascade,
  start_ms  int not null check (start_ms >= 0),
  end_ms    int not null,
  check (end_ms > start_ms),
  unique (track_id, verse_id)
);
create index audio_segments_verse_idx on public.audio_segments (verse_id);

-- ---------------------------------------------------------------------------
-- AI Q&A
-- ---------------------------------------------------------------------------
-- Embeddings for retrieval. One row per verse_content (so each language /
-- edition can be searched). Uses pgvector when available; the column is
-- created as `vector(1536)` if the extension exists, else as float4[] so the
-- schema still applies on minimal Postgres builds.
create table public.content_embeddings (
  id               uuid primary key default gen_random_uuid(),
  verse_content_id uuid not null references public.verse_contents (id) on delete cascade,
  model            text not null,                                    -- 'text-embedding-3-small'
  chunk_index      int not null default 0,
  chunk_text       text not null,
  created_at       timestamptz not null default now(),
  unique (verse_content_id, model, chunk_index)
);

do $$
begin
  if exists (select 1 from pg_extension where extname = 'vector') then
    execute 'alter table public.content_embeddings add column embedding vector(1536)';
    execute 'create index content_embeddings_hnsw on public.content_embeddings using hnsw (embedding vector_cosine_ops)';
  else
    execute 'alter table public.content_embeddings add column embedding real[]';
  end if;
end $$;

create table public.qa_sessions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles (id) on delete cascade,      -- null => anonymous
  work_id     uuid references public.works (id) on delete set null,
  language    text not null default 'en' references public.languages (code),
  title       text,
  created_at  timestamptz not null default now()
);
create index qa_sessions_user_idx on public.qa_sessions (user_id, created_at desc);

create table public.qa_messages (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references public.qa_sessions (id) on delete cascade,
  role          public.qa_role not null,
  content       text not null,
  -- citations: [{"verse_id":"…","ref":"1.1.1","edition_id":"…","quote":"…"}]
  citations     jsonb not null default '[]'::jsonb,
  model         text,
  prompt_tokens int,
  output_tokens int,
  grounded      boolean,                                                   -- did the answer cite retrieved verses?
  feedback      smallint check (feedback in (-1, 0, 1)),
  created_at    timestamptz not null default now()
);
create index qa_messages_session_idx on public.qa_messages (session_id, created_at);

-- ---------------------------------------------------------------------------
-- Feature flags / app config (public read)
-- ---------------------------------------------------------------------------
create table public.app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
create trigger trg_app_config_updated before update on public.app_config for each row execute function public.set_updated_at();

do $$
declare t text;
begin
  foreach t in array array['audio_tracks','audio_segments','app_config']
  loop
    execute format('create trigger trg_audit_%1$s after insert or update or delete on public.%1$s for each row execute function public.audit_row()', t);
  end loop;
end $$;

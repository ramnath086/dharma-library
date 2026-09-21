# Architecture

```
┌──────────────────────────────┐        ┌─────────────────────────────────────────┐
│ Flutter app                  │        │ Supabase                                │
│  Riverpod · go_router        │  HTTPS │  PostgreSQL 15 + RLS                    │
│  Repository (net-first,      │◄──────►│   works/sections/verses/editions/…      │
│   cache-fallback)            │        │   RPC: get_toc, get_section_verses,     │
│  LocalStore (sqflite)        │        │        get_verse, search_verses,        │
│   kv cache · bookmarks ·     │        │        get_entity, upsert_progress,     │
│   progress · outbox          │        │        sync_pull, get_work_bundle,      │
│  Translit (on-device script  │        │        retrieve_for_qa, match_verse_…   │
│   conversion)                │        │  Auth (magic link / OTP, PKCE)          │
│  just_audio + audio_session  │        │  Storage: audio (private, signed URLs)  │
│  Edge fn client → /ask       │        │           rights-documents (admin)      │
└──────────────────────────────┘        │  Edge Function `ask` (Deno) → LLM       │
                                        └─────────────────────────────────────────┘
```

## Data flow
1. **Structure**: `get_toc(work)` → nested sections with verse counts (one call, cached).
2. **Reading**: `get_section_verses(section_id)` → all verses of a chapter with
   every rendering the caller may see (RLS) + audio segments + tracks. Cached
   under `chapter:<id>`. The reader picks renderings client-side by the user's
   layout (script, translation language, toggles). If the chosen Indic script has
   no server-side edition, the base Devanagari is converted on device.
3. **Study**: `get_verse(work, ref)` adds knowledge-graph mentions, cross
   references and prev/next.
4. **Search**: `search_verses` — `simple` FTS over an IAST-folded generated column
   (`krishna` = `kṛṣṇa` = `कृष्ण` via entity names), substring fallback, verse-ref
   match and entity-name expansion. Offline: substring search over cached chapters.
5. **User data**: local-first; `syncUserData()` pushes dirty rows and pulls with
   `sync_pull`, server rows win by `updated_at`. Anonymous users keep data on device.
6. **Offline**: `get_work_bundle(work)` returns everything public for a work; the
   same JSON is shipped as an asset (`app/assets/bundles/`) so first launch works
   without network. `LocalStore.importAllAssetBundles` discovers every
   `assets/bundles/*.json` at runtime (skipping a catalog manifest if present),
   so a new published work becomes a Home catalogue card without a hard-coded
   slug. Home lists **all** bundled/published works. A work overview
   (`/library/:slug`) holds that work’s TOC. Unauthenticated users can browse
   published scripture, offline bundles and local search; login is only for
   sync. For a future complete Bhāgavata (~335 chapters) verse bodies should be
   imported per chapter rather than held entirely in memory at first paint —
   the current bundles (Gītā 700 + Bhāgavata pilot 10) are small enough to
   import whole.
7. **AI Q&A** ("Ask Dharma"): Edge Function retrieves passages (`retrieve_for_qa`
   + optional pgvector `match_verse_contents`), prompts the model with those
   passages only, then validates citations with `grounding.ts`. Unsupported
   answers return `grounded=false` and the UI shows an honest "no reliable
   answer". Foundations: signed-in users get conversation continuity (prior
   turns replayed from `qa_messages`, pure logic in `context.ts`), a daily
   answer cap (`qa_answers_today()` + `ASK_DAILY_CAP`, HTTP 429 when reached),
   answer feedback (`qa_messages.feedback`, ±1), and a history screen backed by
   `qa_sessions`. Starter questions come from `app_config['ask.suggested_questions']`.
8. **Audio**: `audio_tracks` (per chapter) + `audio_segments` (time → verse). Private
   bucket; signed URL only for tracks visible under RLS. `LockCachingAudioSource`
   caches files for offline replay. Preference-gated **cues** (`launch_chime.wav`,
   `sloka_chime.wav`) are original synthesized assets. Launch sound defaults
   OFF. Śloka cues play only when `verse.metadata.audio.important` is set in
   content (pilot: 1.1.1–1.1.3) and the reader has cues enabled.
9. **Auth**: Supabase email OTP / magic link, PKCE, `dharmalibrary://auth-callback`.
   Sessions persist on device (refresh token). Reading is never gated on login.

## Security model
* All tables have RLS. Public reads are limited to `published` rows whose edition
  rights are cleared (`edition_is_public`). Private column
  `rights.permission_document_url` is revoked from anon/authenticated.
* Roles live in `profiles.role` (reader / contributor / editor / admin) and are
  checked via SECURITY DEFINER helpers; users cannot self-promote.
* Editors can edit content and publish editions; only admins change rights,
  roles, config and read the audit log. Every content table is audited with actor.
* The mobile app ships only the anon key. Ingestion/embedding use the service
  role from CI secrets.

## Adding a new work / language
1. `content/<slug>/work.json` — editions with **rights** and **sources**.
2. `content/<slug>/<canto>/<chapter>/verses.json` — Devanagari + IAST required;
   translations optional per language.
3. `content/<slug>/graph.json` — people/places/topics/stories.
4. `python3 scripts/ingest.py --apply && python3 scripts/localdb.py test`.
5. New UI locale: add `app/l10n/app_<lang>.arb`; new script: extend `translit.py`
   (+ `gen_dart_translit.py`) and add the font mapping in `AppTheme.scriptStyle`.

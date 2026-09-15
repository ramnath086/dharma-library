# Dharma Library

A production-grade, multilingual reader for Hindu scripture — starting with the
**Śrīmad Bhāgavata Purāṇa**. Flutter mobile app + Supabase/PostgreSQL backend.

**Pilot scope:** Bhāgavatam 1.1.1 – 1.1.10 in Sanskrit (Devanagari, IAST and
seven Indic scripts), English and Malayalam, with word-by-word glosses, a
people/places/stories/topics knowledge graph, search, bookmarks, reading
progress, offline support, an admin CMS, audio architecture and grounded AI Q&A.

## Repository layout

```
supabase/
  migrations/        0001…0007 — schema, knowledge graph, user data, RLS, API RPCs, pgvector
  seed.sql           languages, scripts, app config
  tests/             RLS + API regression tests (plain SQL asserts)
  functions/ask/     Edge Function: grounded Q&A with verse citations
  config.toml        Supabase CLI config (buckets, auth, functions)
content/
  bhagavata-purana/  work.json (editions, sources, RIGHTS), graph.json, 1/1/verses.json
  generated/         SQL emitted by scripts/ingest.py (committed, reproducible)
scripts/
  localdb.py         embedded Postgres harness: reset / migrate / seed / test
  ingest.py          content JSON → idempotent SQL (+ machine transliterations)
  translit.py        Devanagari → IAST / Malayalam / Kannada / Telugu / Bengali / Gujarati / Gurmukhi / Odia / Tamil
  gen_dart_translit.py  keeps the Dart port in sync with translit.py
  export_bundle.py   offline bundle (anon-role, rights-filtered) → app/assets/bundles/
  embed_contents.py  pgvector backfill for AI retrieval
app/                 Flutter app (Riverpod, go_router, supabase_flutter, sqflite, just_audio)
docs/                architecture, content model, rights policy, deployment
.github/workflows/   CI (db tests, flutter analyze/test/build, deno check) + manual Supabase deploy
```

## Quick start

### Backend (no Docker needed)
```bash
pip install --user pgserver            # embedded PostgreSQL 16
python3 scripts/localdb.py reset       # auth stub + migrations + seed
python3 scripts/ingest.py --apply      # load pilot content
python3 scripts/localdb.py test        # 39 RLS/API assertions
python3 scripts/export_bundle.py       # refresh app/assets/bundles/bhagavata-purana.json
```

### App
```bash
cd app
flutter create . --platforms=android,ios --org org.dharmalibrary --project-name dharma_library   # regenerates boilerplate only
flutter pub get && flutter gen-l10n && flutter test
flutter run                                    # bundle mode (offline, no backend)
flutter run --dart-define-from-file=../env.json   # with Supabase (see .env.example)
```

### Deploy to Supabase
See [docs/deployment.md](docs/deployment.md). In short: create a project, set
GitHub secrets (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`,
`SUPABASE_DB_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`), run the
*Deploy Supabase* workflow, then `supabase secrets set OPENAI_API_KEY=…` for AI Q&A.

## Principles

* **Rights are mandatory.** Every edition (text, translation, audio) references a
  `rights` row. Row-Level Security only serves editions whose rights are
  `public_domain`, `open_license`, `permission_granted` (with a permission
  document on file) or `original`. Nothing with `pending`/`restricted` rights
  can reach a reader, search, the AI, or the offline bundle. See
  [docs/rights-policy.md](docs/rights-policy.md).
* **Never fabricate scripture.** Sanskrit text is collated from public-domain
  witnesses (GRETIL, Wikisource, Gita Press numbering) with text-critical notes
  where they differ. AI answers are restricted to retrieved verses and every
  citation is validated against the retrieval set.
* **Original translations, clearly labelled.** English and Malayalam renderings
  are Dharma Library originals (CC BY-SA 4.0), marked *draft — pending
  scholarly review* in the UI.
* **Offline-first for readers.** Content payloads are cached verbatim;
  bookmarks/progress are local-first and synced when signed in.

## Licence
Code: MIT. Original translations, glosses and annotations: CC BY-SA 4.0.
Sanskrit base text: public domain. See `content/*/work.json` for per-edition rights.

# Play Store Release Checklist — Dharma Library

## App Identity
- **Package ID (Android):** `org.dharmalibrary.dharma_library`
  - Generated via `flutter create --org org.dharmalibrary --project-name dharma_library`
  - Verified in `app/android/app/build.gradle.kts` after `flutter create`
- **App Name:** `Dharma Library` (en), `ധർമ്മ ലൈബ്രറി` (ml)
  - Source: `app/l10n/app_en.arb` `appTitle`, `app_ml.arb`
- **Version:** `1.0.0+2` (pubspec.yaml)
  - Increment `+` build number for each Play upload, keep semver for user-visible version
- **Description (short):** Multilingual Hindu scripture reader — Śrīmad Bhāgavata Purāṇa and beyond.
- **Full description (en, draft for Play Console):**
  > Dharma Library is an offline-first, multilingual reader for Hindu scriptures.
  > 
  > • Complete Śrīmad Bhāgavata Purāṇa: 12 cantos, 335 chapters, 14,105 verses (Wikisource CC BY-SA 4.0 + 7 BBT fills for printed numbers absent on Wikisource, traditional mūla only, no BBT translation shipped)
  > • Bhagavad Gītā: 18 chapters / 700 verses (GRETIL BORI + Swarupananda 1909 public domain)
  > • Scripts: Devanagari, IAST, Malayalam, Kannada, Telugu, Bengali, Gujarati (machine transliteration CC0)
  > • Features: offline bundles, search (people/places/topics, diacritic-insensitive), bookmarks, reading history, daily verse, Ask Dharma (optional AI, needs backend), devotional audio cues (launch chime default OFF, śloka chime user-initiated)
  > • Privacy: anonymous reading allowed, sign-in optional (email OTP/magic link), no ads, analytics only when opted-in and signed-in
  > 
  > All translations beyond Gītā and SB 1.1.1–1.1.10 are marked draft pending scholarly review.

## Build & Signing (Secure)

### GitHub Secrets (never commit)
- `ANDROID_KEYSTORE_BASE64` — base64 of upload keystore `.jks`
  - Generate: `keytool -genkey -v -keystore dharma-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
  - Encode: `base64 -w 0 dharma-upload.jks > b64.txt`
- `ANDROID_KEYSTORE_PASSWORD` — storePassword
- `ANDROID_KEY_PASSWORD` — keyPassword
- `ANDROID_KEY_ALIAS` — keyAlias (default `upload`)
- `SUPABASE_URL`, `SUPABASE_ANON_KEY` — public anon key, injected via `--dart-define`, not secret in app binary beyond RLS

### CI Behavior
- `.github/workflows/ci.yml` now:
  - If `ANDROID_KEYSTORE_BASE64` present → decode to `android/app/upload-keystore.jks`, create `android/key.properties`, build **signed** APK/AAB with `signingConfigs.release`
  - Else → builds **unsigned** APK/AAB with debug keystore (smoke build, expected for PRs without release secrets)
  - Verifies APK contains `bhagavata-purana.json`, `bhagavad-gita.json`, `launch_chime.wav`, `sloka_chime.wav` and checks counts against `work.json` metadata (335/14105, 18/700)
  - Verifies AAB size >1MB and entry count

### Local Release Build
```bash
# One-time: create keystore and key.properties from template
cp app/android/key.properties.template app/android/key.properties
# edit passwords, storeFile=app/upload-keystore.jks

# Build signed AAB + APK
flutter build appbundle --release --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

## Supabase Production

- **Project:** `dharma-library` (project_id in supabase/config.toml)
- **Config:** storage buckets `audio` (private, 200MiB, audio/* mime), `rights-documents` (private), auth redirect `dharmalibrary://auth-callback`, edge function `ask` (verify_jwt=false)
- **Deployment:** GitHub Actions → `Deploy Supabase` (manual dispatch) requires secrets `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`
  - Steps: `supabase link`, `supabase db push` (migrations 0001..0012), seed + ingest via pooler host (dual-stack, session mode 5432), `supabase functions deploy ask`, optional embeddings if `OPENAI_API_KEY` set
- **Last successful deploy (as of 2026-09-21):** `35573445591` for `db53d5d` — predates full 335-chapter corpus (merged 2026-09-23 e9badce). **Production needs re-deploy** after budget fix.
- **Verification:** After deploy, run `psql $PGURI -f supabase/tests/10_rls_and_api.sql` and `python3 -m unittest discover -s scripts/tests -v` (54 tests)

## Corpus Verification (CI enforced)
- Bhāgavata: 335 chapters, 14105 unique verses, 0 printed gaps, 10 suffix ids (duplicate markers like 1.13.40b), 7 BBT fills verified
- Gītā: 18 chapters / 700 verses
- Rights: all editions `public_domain`/`open_license`/`permission_granted`/`original`

## Play Store Requirements

### Data Safety
- **Data collected:** Optional email for auth (OTP), reading progress/bookmarks (on-device + Supabase if signed in), analytics counts only when opted-in and signed in (never verse content, search queries, or ask history)
- **Data shared:** None with third parties, except Supabase backend (data processor) and OpenAI only if user uses Ask Dharma and `OPENAI_API_KEY` configured (function returns 503 without key)
- **Encryption:** TLS in transit, Supabase at rest
- **Account deletion:** Via `account_screen.dart` → delete account (supabase auth admin)
- **Privacy policy:** Required — must host URL (e.g., `https://github.com/ramnath086/dharma-library/blob/main/PRIVACY.md` or site)

### Content Rating
- **Category:** Books & Reference / Education
- **Content:** Religious text, no violence/sexual content, no user-generated content beyond bookmarks/notes (private)
- **Rating:** Everyone, with reference to Hindu scriptures

### Store Assets (need to create)
- Icon: 512x512 PNG (adaptive icon already in Flutter)
- Feature graphic: 1024x500
- Screenshots: phone 2-8, tablet optional, include Home, Gītā chapter, Bhāgavata verse, search, settings audio
- Short description: 80 chars
- Full description: as above
- Contact: email, privacy policy URL

### Release Tracks
- **Internal testing** first — upload signed AAB to Play Console → Internal testing → testers
- Then Closed → Open → Production

## Next Manual Actions (Owner)
1. **Create upload keystore** if not exists, add GitHub Secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`
2. **Trigger Deploy Supabase** workflow on main (after adding `SUPABASE_*` secrets) to push full 335/14105 corpus to production
3. **Trigger CI on main** (push or rerun) — should now build **signed** AAB/APK if signing secrets present
4. **Download signed AAB artifact** `dharma-library-aab` from CI run `35905192352` (currently unsigned, after signing secrets will be signed)
5. **Create Play Console app** with package `org.dharmalibrary.dharma_library`, fill listing, data safety, content rating, upload signed AAB to Internal testing
6. **Do NOT publish automatically** — verify internal test install: Home → Gītā → Bhāgavata → chapter → śloka → search → auth → settings → audio

## Blockers
- **Signing secrets missing:** CI currently builds unsigned (notice in logs). Add `ANDROID_KEYSTORE_BASE64` etc to get signed AAB.
- **Production Supabase behind:** Last deploy 2026-09-21 db53d5d, not e9badce full corpus. Needs manual `Deploy Supabase` dispatch.
- **Privacy policy URL:** Must be hosted before Play submission.
- **Actions permission:** Current GitHub token in sandbox lacks `actions:write` (403 on rerun/dispatch). Owner must reconnect GitHub in Arena or trigger workflows via UI.

## Verification Commands (local)
```bash
python3 scripts/audit_bhagavata_corpus.py
python3 -m unittest discover -s scripts/tests -v
python3 scripts/dart_lint_lite.py
# With DB:
# psql $PGURI -f supabase/tests/10_rls_and_api.sql
```

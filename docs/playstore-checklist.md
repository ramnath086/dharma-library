# Play Store release checklist

Status verified in Phase 13 (CI tip `e4dc6dc`, all jobs green on push + PR).
Everything under "Done in repo" is verifiable in CI; everything under
"Owner actions" needs an interactive session and accounts owned by the
project owner (never automated from CI).

## Phase 13 verification record

| Item | Verification |
| ---- | ------------ |
| Version | `app/pubspec.yaml` → `version: 1.0.0+2` (versionName 1.0.0, versionCode 2) |
| Application ID | `org.dharmalibrary.dharma_library` (generated from `flutter create --org org.dharmalibrary --project-name dharma_library`); `MainActivity` package matches (`app/android/app/src/main/kotlin/org/dharmalibrary/dharma_library/MainActivity.kt`) |
| Signing hygiene | No keystore/key.properties/env.json anywhere in git; `.gitignore` covers `app/android/key.properties`, `app/android/app/*.jks`/`*.keystore`, `env.json` at any depth; `key.properties.template` + `env.json.example` provide the shapes |
| Production env | `AppConfig` reads `--dart-define` values only; `.env.example` separates public app keys from server-only secrets (`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, `OPENAI_API_KEY` — Supabase secrets, never the app) |
| Android manifest | label "Dharma Library"; INTERNET/ACCESS_NETWORK_STATE/WAKE_LOCK/FOREGROUND_SERVICE(+MEDIA_PLAYBACK); no notification-permission claims (in-app reminder pref only); deep link `dharmalibrary://auth-callback` BROWSABLE; matches `supabase/config.toml` `site_url` + `additional_redirect_urls` |
| Release builds in CI | Every push: unsigned **release APK** (`dharma-library-apk`) and **release AAB** (`dharma-library-aab`) artifacts; Flutter analyze + 51 tests + build on CI tip green |
| Database/backend | Migrations 0001→0010 + seed + pilot content + RLS/API assertions green; edge `ask` deno check+tests green; storage `audio` bucket private with policies via PR #4 (`0008_storage_policies.sql`) |
| Release command | `./scripts/build_release_aab.sh` (checks for key.properties + env.json, runs analyze+tests, builds `app-release.aab`, warns if the debug signing config is still in place) |

## Done in repo

| Area | State | Verify |
| ---- | ----- | ------ |
| App builds | release APK + release AAB smoke-built on every PR (`dharma-library-apk` / `dharma-library-aab` artifacts, debug-signed — rebuild with the owner keystore for upload) | Actions → CI → artifacts |
| Launcher config | `MainActivity` package matches applicationId `org.dharmalibrary.dharma_library` (fixed 2026-09: was `org.dharmalibrary.app`, which would crash on device); app label "Dharma Library"; release internet/network/wake-lock permissions; supabase auth deep link `dharmalibrary://auth-callback` | `app/android/app/src/main/AndroidManifest.xml` |
| Tests | 40+ widget/unit tests (navigation, search, daily verse, transliteration, offline repository, chant helpers, prefetch, diagnostics, QA) | `flutter test` (CI) |
| Lint | `flutter analyze` clean | CI |
| Database | migrations apply cleanly from 0001→0010; 80+ RLS/API SQL assertions | CI db job |
| Edge functions | `deno check` on `ask`, `tts`, `embed-sync` | CI |
| Offline | bundled pilot content; download switch; adjacent-chapter prefetch | settings screen + `prefetch_test.dart` |
| Privacy | analytics default-OFF opt-in; content-free events; local-only diagnostics | settings → Privacy |
| Backend deploy | one-click `Deploy Supabase` manual workflow | Actions |

## Owner actions (in order)

1. **Accounts** — Google Play Console ($25) and a working Supabase project
   (deploy via the *Deploy Supabase* workflow; verify `ask` works with
   `OPENAI_API_KEY` secret set).
2. **Signing key** — generate with `keytool -genkey -v -keystore android/
   dharma-upload.jks -keyalg RSA -keysize 2048 -validity 10950 -alias upload`;
   store the password in a password manager; follow
   <https://docs.flutter.dev/deployment/android#signing-the-app> and commit
   only `key.properties` placeholders — never the `.jks`.
3. **Release build** — `./scripts/build_release_aab.sh` (or directly:
   `cd app && flutter build appbundle --release --dart-define-from-file=
   ../env.json`) → `app/build/app/outputs/bundle/release/app-release.aab`.
   Wire `key.properties` into `app/android/app/build.gradle(.kts)` first per
   <https://docs.flutter.dev/deployment/android#signing-the-app> (the file is
   generated locally/CI and intentionally not committed).
4. **Console setup** — create app `org.dharmalibrary.dharma_library`, internal
   testing track, add testers by email.
5. **Store listing assets** —
   - App icon: `app/android/app/src/main/res/mipmap-*/ic_launcher.png`
     (default Flutter icon in this build; replace with brand art).
   - Feature graphic 1024×500, phone screenshots (home, reading, ask, audio),
     short/full description (draft from README pilot-scope paragraph),
     category Books & Reference, content rating questionnaire, privacy policy
     URL (repository `docs/rights-policy.md` can seed it; add analytics
     paragraph referencing `supabase/migrations/0010_analytics.sql`).
6. **Data safety form** — offline reading local-only; optional email OTP sign-in;
   optional opt-in analytics events (`analytics_events`); no ads, no trackers.
7. **Notifications (optional)** — the in-app daily-verse reminder preference is
   in place; hooking it to a scheduler (e.g. Workmanager/local_notifications)
   is the only scheduled-notification step and can wait for 1.1.
8. **Ship internal build** → gather feedback → promote to production with
   staged rollout.

## First-corpus expansion gate

Before marketing the app, expand beyond Pilot 1.1.1–1.1.10 using the same
pipeline: add verses under `content/bhagavata-purana/<canto>/<chapter>/`,
run `ingest.py --apply`, `export_bundle.py`, and bump the app bundle asset.
Rights rows must be complete for every new edition — RLS refuses anything
without cleared rights.

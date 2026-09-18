# Play Store release checklist

Status at Phase 11 completion. Everything under "Done in repo" is verifiable in
CI; everything under "Owner actions" needs an interactive session and accounts
owned by the project owner (never automated from CI).

## Done in repo

| Area | State | Verify |
| ---- | ----- | ------ |
| App builds | debug APK built on every PR (`app-debug-apk` artifact) | Actions → CI → artifacts |
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
3. **Release build** — `cd app && flutter build appbundle --dart-define-from-
   file=../env.json` → `build/app/outputs/bundle/release/app-release.aab`.
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

# Deployment runbook

## 1. Supabase project
1. Create a project (region close to India, e.g. `ap-south-1`). Note the
   **project ref**, **DB password**, **URL** and **anon key**.
2. Add GitHub repository secrets: `SUPABASE_ACCESS_TOKEN` (from
   app.supabase.com/account/tokens), `SUPABASE_PROJECT_REF`,
   `SUPABASE_DB_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
3. Run **Actions → Deploy Supabase → Run workflow**. This pushes migrations
   0001–0007, seeds languages/scripts/config, loads the pilot content and
   deploys the `ask` function.
4. Storage buckets `audio` and `rights-documents` are declared in
   `supabase/config.toml` (private). Storage policies: allow `select` on
   `audio` objects to `authenticated`+`anon` **only via signed URLs** (default
   for private buckets); `insert/update` for editors:
   ```sql
   create policy "audio: editors upload" on storage.objects for insert to authenticated
     with check (bucket_id = 'audio' and public.is_editor());
   create policy "rights docs: admin" on storage.objects for all to authenticated
     using (bucket_id = 'rights-documents' and public.is_admin()) with check (bucket_id = 'rights-documents' and public.is_admin());
   ```
5. Auth → URL configuration: add redirect `dharmalibrary://auth-callback`.
6. Make yourself admin once: `update public.profiles set role='admin' where id = '<your auth uid>';`

## 2. AI Q&A
```
supabase secrets set OPENAI_API_KEY=sk-... AI_MODEL=gpt-4o-mini EMBEDDING_MODEL=text-embedding-3-small
export PGPASSWORD='<db password>'
OPENAI_API_KEY=... SUPABASE_DB_URL=postgresql://postgres@db.<ref>.supabase.co:5432/postgres \
  python3 scripts/embed_contents.py
```
Pass the DB password through `PGPASSWORD` (or `SUPABASE_DB_PASSWORD`) rather
than inlining it into the URI — Supabase passwords routinely contain URI-special
characters (`@ / : # ? %`) that truncate the host or break parsing in
`postgres://user:pw@host`. The same applies to any direct `psql "$DB_URL"`
invocation, e.g. the content updates in §4: keep `DB_URL` passwordless and
export `PGPASSWORD` alongside it.

Any OpenAI-compatible endpoint works via `OPENAI_BASE_URL`. Without a key the
function returns 503 and the app shows the offline/unavailable message.

## 3. Mobile builds
* `env.json` (git-ignored): `{"SUPABASE_URL":"…","SUPABASE_ANON_KEY":"…"}`
* Android: put `key.properties` + keystore in `app/android/` (git-ignored);
  `flutter build appbundle --release --dart-define-from-file=env.json`.
* iOS: `flutter build ipa --release --dart-define-from-file=env.json` (needs
  Xcode signing set up once in `Runner.xcworkspace`).
* CI builds an unsigned APK artifact on every push.

## 4. Content updates
Edit JSON under `content/`, run `python3 scripts/ingest.py` (commit the
generated SQL), `python3 scripts/export_bundle.py` (commit the bundle), open a
PR. CI re-runs migrations, RLS tests and verifies the bundle is rights-clean.
Apply to production with `psql "$DB_URL" -f content/generated/<work>.sql`
(the SQL is idempotent).

# Deployment runbook

## 1. Supabase project
1. Create a project (region close to India, e.g. `ap-south-1`). Note the
   **project ref**, **DB password**, **URL** and **anon key**.
2. Add GitHub repository secrets: `SUPABASE_ACCESS_TOKEN` (from
   app.supabase.com/account/tokens), `SUPABASE_PROJECT_REF`,
   `SUPABASE_DB_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
3. Run **Actions → Deploy Supabase → Run workflow**. This pushes migrations
   0001–0007, seeds languages/scripts/config, loads the pilot content and
   deploys the `ask` function. The seed/content steps connect through the
   Supavisor session pooler, not the direct host — see
   [Direct connections and IPv6](#direct-connections-and-ipv6).
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
# optional knobs for Ask Dharma (defaults: 30/day, 0 disables the cap)
supabase secrets set ASK_DAILY_CAP=30
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
function returns 503 and the app shows the offline/unavailable message. If the
machine running the backfill has no IPv6 route, swap the `db.<ref>` host in
`SUPABASE_DB_URL` for the pooler host described in
[Direct connections and IPv6](#direct-connections-and-ipv6).

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
Apply to production with `psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f content/generated/<work>.sql` (or loop `for f in content/generated/*.sql; do psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$f"; done` for all works)
(the SQL is idempotent). From a network without IPv6, `$DB_URL` has to be the
pooler URL — see
[Direct connections and IPv6](#direct-connections-and-ipv6).

## Direct connections and IPv6

Supabase retired IPv4 for the **direct** database host: `db.<ref>.supabase.co`
now resolves to IPv6 only, so any raw `psql`/`libpq` connection from a network
without an IPv6 route fails with

```
psql: error: connection to server at "db.<ref>.supabase.co" (2606:...) port 5432 failed: Network is unreachable
```

That hits CI runners and plenty of office networks, not user devices — the app
and the `ask` function talk to `*.<ref>.supabase.co` (the API host), which still
serves IPv4. Only the `db.` host moved.

Where a direct connection is needed (the embed backfill in §2, the content
updates in §4), use the Supavisor pooler, which is dual-stack:

```
export PGPASSWORD='<db password>'
for f in content/generated/*.sql; do psql "postgresql://postgres.<ref>@aws-0-<region>.pooler.supabase.com:5432/postgres" -v ON_ERROR_STOP=1 -q -f "$f"; done  # deterministic, sorted; applies all works (Bhāgavatam, Gita, …)
```

Two things differ from the direct host: the user is `postgres.<ref>` (the ref is
what tells Supavisor which project to route to) and the host carries the
project's cloud region, e.g. `ap-south-1` — read it with
`curl -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" https://api.supabase.com/v1/projects/<ref> | jq -r .region`.
Keep **session mode**, port `5432`: it behaves like a direct connection, so
multi-statement `psql -f` files, `SET` state and prepared statements keep
working. Transaction mode (`6543`) rejects session state and would break those
scripts. `supabase link` and `supabase db push` need no change at all — the CLI
pools through Supavisor by itself, which is why the *Deploy Supabase* workflow
fails at the seed step and not at `db push`.

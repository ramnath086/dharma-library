#!/usr/bin/env python3
"""Export the public offline bundle for a work (output of get_work_bundle) to
app/assets/bundles/<slug>.json, using the anon role so RLS guarantees only
cleared, published content is included.

    python3 scripts/export_bundle.py [--db URI] [--work bhagavata-purana]
"""
import argparse, json, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))

ap = argparse.ArgumentParser()
ap.add_argument('--db')
ap.add_argument('--work', default='bhagavata-purana')
a = ap.parse_args()

if a.db:
    uri, psql = a.db, 'psql'
else:
    import localdb
    uri, psql = localdb.db_uri(localdb.server()), localdb.psql_bin()

sql = f"set role anon; select public.get_work_bundle('{a.work}')::text;"
r = subprocess.run([psql, uri, '-At', '-c', sql], capture_output=True, text=True)
if r.returncode != 0:
    sys.exit(r.stderr)
bundle = json.loads(r.stdout.strip().splitlines()[-1])
# sanity: no uncleared rights may leak
for e in bundle['editions']:
    assert e['rights_status'] in ('public_domain', 'open_license', 'permission_granted', 'original'), e
out = ROOT / 'app' / 'assets' / 'bundles' / f'{a.work}.json'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(bundle, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size/1024:.0f} KB, {len(bundle['sections'])} sections, {len(bundle['editions'])} editions)")

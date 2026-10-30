#!/usr/bin/env python3
"""Export public offline bundles for published works.

With no ``--work`` argument every published work is discovered from the
Database and exported to ``app/assets/bundles/<slug>.json``.  ``--work`` is
kept as a useful narrow escape hatch for local debugging or a single-work
refresh:

    python3 scripts/export_bundle.py [--db URI]
    python3 scripts/export_bundle.py [--db URI] --work bhagavad-gita

The query runs as ``anon`` so the same RLS/publication and rights guarantees
used by the app are applied while producing the checked-in assets.
"""
import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

ap = argparse.ArgumentParser()
ap.add_argument("--db")
ap.add_argument("--work", help="export only this published work (default: all published works)")
a = ap.parse_args()

if a.db:
    uri, psql = a.db, "psql"
else:
    import localdb
    uri, psql = localdb.db_uri(localdb.server()), localdb.psql_bin()


def run_sql(sql: str) -> list[str]:
    # Quiet mode suppresses command tags from SET ROLE. Without it, "SET"
    # is mistaken for a work slug and produces an invalid SET.json bundle.
    r = subprocess.run([psql, uri, "-qAt", "-v", "ON_ERROR_STOP=1", "-c", sql], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(r.stderr)
    return [line for line in r.stdout.splitlines() if line.strip()]


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


if a.work:
    slugs = [a.work]
else:
    # works has a public-read policy limited to published rows.  Discovering
    # here, instead of baking in a pilot slug, keeps new published works in
    # the next app package automatically.
    slugs = run_sql("set role anon; select slug from public.works where status = 'published' order by sort_order, slug;")

if not slugs:
    sys.exit("no published works found")

out_dir = ROOT / "app" / "assets" / "bundles"
out_dir.mkdir(parents=True, exist_ok=True)
for slug in slugs:
    rows = run_sql(f"set role anon; select public.get_work_bundle({sql_literal(slug)})::text;")
    if not rows:
        sys.exit(f"empty bundle for published work {slug}")
    bundle = json.loads(rows[-1])

    # Sanity: no uncleared rights may leak into a shipped asset.
    for edition in bundle.get("editions", []):
        assert edition["rights_status"] in ("public_domain", "open_license", "permission_granted", "original"), edition

    out = out_dir / f"{slug}.json"
    out.write_text(json.dumps(bundle, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size / 1024:.0f} KB, {len(bundle.get('sections', []))} sections, {len(bundle.get('editions', []))} editions)")

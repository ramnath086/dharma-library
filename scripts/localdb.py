#!/usr/bin/env python3
"""Local PostgreSQL harness for Dharma Library.

Spins up an embedded Postgres (via the `pgserver` pip package) so migrations,
seeds and RLS tests can run without Docker or a Supabase project.

Usage:
  python3 scripts/localdb.py reset      # fresh DB: stub auth + migrations + seed
  python3 scripts/localdb.py migrate    # apply migrations to existing DB
  python3 scripts/localdb.py seed       # apply supabase/seed.sql
  python3 scripts/localdb.py test       # run supabase/tests/*.sql (pgTAP-free asserts)
  python3 scripts/localdb.py psql "select 1"
  python3 scripts/localdb.py uri
"""
import os, sys, glob, subprocess, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = pathlib.Path(os.environ.get("DL_PGDATA", "/tmp/dharma-pgdata"))
MIGR = ROOT / "supabase" / "migrations"
TESTS = ROOT / "supabase" / "tests"
SEED = ROOT / "supabase" / "seed.sql"


def server():
    import pgserver  # type: ignore
    return pgserver.get_server(str(DATA))


def psql_bin():
    import pgserver  # type: ignore
    return str(pathlib.Path(pgserver.__file__).parent / "pginstall" / "bin" / "psql")


def run_sql_file(uri, path, dbname="dharma"):
    cmd = [psql_bin(), uri, "-v", "ON_ERROR_STOP=1", "-q", "-f", str(path)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr, file=sys.stderr)
        raise SystemExit(f"FAILED: {path}")
    if r.stderr.strip():
        for line in r.stderr.splitlines():
            if "NOTICE" in line and "ok —" in line:
                print("  ", line.split("NOTICE:", 1)[1].strip())
            elif "NOTICE" in line:
                print("  ", line.strip())
    return r.stdout


def db_uri(srv):
    return srv.get_uri().replace("/postgres?", "/dharma?")


def ensure_db(srv):
    srv.psql("select 1")
    out = srv.psql("select 1 from pg_database where datname='dharma'")
    if "1 row" not in out:
        srv.psql("create database dharma")


def cmd_reset():
    srv = server()
    srv.psql("drop database if exists dharma")
    srv.psql("create database dharma")
    uri = db_uri(srv)
    print("== auth stub")
    run_sql_file(uri, TESTS / "00_local_auth_stub.sql")
    cmd_migrate(srv)
    if SEED.exists():
        cmd_seed(srv)


def cmd_migrate(srv=None):
    srv = srv or server()
    ensure_db(srv)
    uri = db_uri(srv)
    for f in sorted(glob.glob(str(MIGR / "*.sql"))):
        print("== migrate", os.path.basename(f))
        run_sql_file(uri, f)


def cmd_seed(srv=None):
    srv = srv or server()
    uri = db_uri(srv)
    print("== seed")
    run_sql_file(uri, SEED)
    for f in sorted(glob.glob(str(ROOT / "content" / "**" / "*.sql"), recursive=True)):
        print("== content", os.path.relpath(f, ROOT))
        run_sql_file(uri, f)


def cmd_test():
    srv = server()
    uri = db_uri(srv)
    failed = 0
    for f in sorted(glob.glob(str(TESTS / "*.sql"))):
        if os.path.basename(f).startswith("00_"):
            continue
        print("== test", os.path.basename(f))
        try:
            run_sql_file(uri, f)
        except SystemExit as e:
            print(e)
            failed += 1
    if failed:
        raise SystemExit(f"{failed} test file(s) failed")
    print("ALL TESTS PASSED")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    c = sys.argv[1]
    if c == "reset":
        cmd_reset()
    elif c == "migrate":
        cmd_migrate()
    elif c == "seed":
        cmd_seed()
    elif c == "test":
        cmd_test()
    elif c == "uri":
        print(db_uri(server()))
    elif c == "run":
        srv = server()
        r = subprocess.run([psql_bin(), db_uri(srv), "-f", sys.argv[2]], capture_output=True, text=True)
        print(r.stdout); print(r.stderr, file=sys.stderr)
    elif c == "psql":
        srv = server()
        r = subprocess.run([psql_bin(), db_uri(srv), "-c", sys.argv[2]], capture_output=True, text=True)
        print(r.stdout or r.stderr)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()

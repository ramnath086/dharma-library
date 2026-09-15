#!/usr/bin/env python3
"""Backfill content_embeddings for published verse_contents (translations +
IAST). Requires OPENAI_API_KEY and SUPABASE_DB_URL (service role / direct DB).

    OPENAI_API_KEY=... SUPABASE_DB_URL=postgresql://... python3 scripts/embed_contents.py

Idempotent: skips rows that already have an embedding for the model.
Uses only urllib + psql so no extra dependencies are needed.
"""
import json, os, subprocess, sys, urllib.request

DB = os.environ.get("SUPABASE_DB_URL")
KEY = os.environ.get("OPENAI_API_KEY")
MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-3-small")
BASE = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
if not DB or not KEY:
    sys.exit("set SUPABASE_DB_URL and OPENAI_API_KEY")


def psql(sql):
    r = subprocess.run(["psql", DB, "-At", "-v", "ON_ERROR_STOP=1", "-c", sql], capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    return r.stdout


rows = psql(f"""
  select json_agg(json_build_object('id', vc.id, 'text', v.ref || ' ' || vc.body))
    from verse_contents vc join verses v on v.id = vc.verse_id join editions e on e.id = vc.edition_id
   where vc.status = 'published' and e.kind in ('translation','transliteration')
     and not exists (select 1 from content_embeddings ce where ce.verse_content_id = vc.id and ce.model = '{MODEL}')
""").strip()
items = json.loads(rows) if rows and rows != "" else []
print(f"{len(items)} contents to embed")
for i in range(0, len(items), 64):
    batch = items[i:i + 64]
    req = urllib.request.Request(f"{BASE}/embeddings", data=json.dumps({"model": MODEL, "input": [b["text"] for b in batch]}).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.load(resp)["data"]
    values = []
    for b, d in zip(batch, data):
        vec = "[" + ",".join(f"{x:.7f}" for x in d["embedding"]) + "]"
        txt = b["text"].replace("'", "''")
        values.append(f"('{b['id']}', '{MODEL}', 0, '{txt}', '{vec}'::vector)")
    psql("insert into content_embeddings (verse_content_id, model, chunk_index, chunk_text, embedding) values " + ",".join(values) +
         " on conflict (verse_content_id, model, chunk_index) do update set embedding = excluded.embedding, chunk_text = excluded.chunk_text")
    print(f"  embedded {i + len(batch)}/{len(items)}")
print("done")

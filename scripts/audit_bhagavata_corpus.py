#!/usr/bin/env python3
"""Audit imported Bhāgavata verses against the on-disk chapter files.

Does not invent verses. Does not hit the network. Source-of-truth for
*imported* counts is content/bhagavata-purana/*/verses.json. Wikisource
page re-fetch is the ingest job; this script reports numbering gaps,
suffix refs, empty mūla, and inventory vs the 12×335 chapter map.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content" / "bhagavata-purana"
sys.path.insert(0, str(ROOT / "scripts"))
from generate_bhagavata_corpus import SKANDHA_CHAPTERS, EXPECTED_CHAPTERS  # noqa: E402

PRINTED = re.compile(r"^(\d+)([a-z])?$")


def audit() -> dict:
    rows = []
    refs: set[str] = set()
    dups: list[str] = []
    empty: list[str] = []
    malformed: list[str] = []
    suffixes: list[str] = []
    skips: list[dict] = []
    notes: list[dict] = []
    missing_files: list[str] = []
    total = 0
    by_sk: dict[str, dict] = {}

    for sk, nchap in SKANDHA_CHAPTERS.items():
        sk_verses = 0
        for adh in range(1, nchap + 1):
            path = CONTENT / str(sk) / str(adh) / "verses.json"
            rec = {
                "skandha": sk,
                "adhyaya": adh,
                "source_count": None,
                "imported_count": 0,
                "missing_ids": [],
                "extra_ids": [],
                "status": "ok",
            }
            if not path.exists():
                rec["status"] = "missing_file"
                missing_files.append(f"{sk}.{adh}")
                rows.append(rec)
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            verses = data.get("verses") or []
            rec["imported_count"] = len(verses)
            rec["source_count"] = len(verses)  # ingest parse == import; live WS re-count is GHA
            rec["revid"] = (data.get("_source") or {}).get("revid")
            rec["license"] = (data.get("_source") or {}).get("license")
            printed: list[int] = []
            for v in verses:
                ref = v.get("ref") or ""
                if ref in refs:
                    dups.append(ref)
                refs.add(ref)
                if not (v.get("deva") or "").strip():
                    empty.append(ref)
                tail = ref.split(".")[-1]
                m = PRINTED.match(tail)
                if not m:
                    malformed.append(ref)
                    rec["status"] = "malformed_id"
                    continue
                n = int(m.group(1))
                if m.group(2):
                    suffixes.append(ref)
                printed.append(n)
                note = (v.get("metadata") or {}).get("numbering_note")
                if note:
                    notes.append({"ref": ref, "note": note})
            for i in range(1, len(printed)):
                if printed[i] > printed[i - 1] + 1:
                    gap = list(range(printed[i - 1] + 1, printed[i]))
                    skips.append({"chapter": f"{sk}.{adh}", "skipped": gap})
                    rec.setdefault("skipped_printed", []).extend(gap)
                    if rec["status"] == "ok":
                        rec["status"] = "printed_gap"
            if verses and [v.get("ordinal") for v in verses] != list(range(1, len(verses) + 1)):
                rec["status"] = "nonmonotonic_ordinal"
            total += len(verses)
            sk_verses += len(verses)
            rows.append(rec)
        by_sk[str(sk)] = {"chapters": nchap, "verses": sk_verses}

    unexplained = [
        r for r in rows
        if r["status"] not in ("ok", "printed_gap", "missing_file")
    ]
    return {
        "skandhas": 12,
        "expected_chapters": EXPECTED_CHAPTERS,
        "chapters_on_disk": len(rows) - len(missing_files),
        "imported_verses": total,
        "unique_refs": len(refs),
        "duplicate_refs": dups,
        "empty_mula": empty,
        "malformed_ids": malformed,
        "suffix_ids": suffixes,
        "printed_gaps": skips,
        "missing_files": missing_files,
        "numbering_notes": len(notes),
        "unexplained": unexplained,
        "skandha_counts": by_sk,
        "chapters": rows,
    }


def main() -> int:
    report = audit()
    out = ROOT / "docs" / "bhagavata-completeness-audit.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"chapters {report['chapters_on_disk']}/{report['expected_chapters']} "
        f"verses {report['imported_verses']} unique {report['unique_refs']} "
        f"gaps {len(report['printed_gaps'])} suffixes {len(report['suffix_ids'])} "
        f"unexplained {len(report['unexplained'])} missing_files {len(report['missing_files'])}"
    )
    if report["missing_files"] or report["duplicate_refs"] or report["empty_mula"] or report["unexplained"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

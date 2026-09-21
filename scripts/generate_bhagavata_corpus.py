#!/usr/bin/env python3
"""Import the complete Śrīmad Bhāgavata Purāṇa from a rights-compatible source.

Default source
--------------
sa.wikisource.org page tree ``श्रीमद्भागवतपुराणम्`` (CC BY-SA 4.0).

This script will **not**:

* copy GRETIL / SanskritDocuments / Motilal / BBT text into ``content/``
* invent verses, translations, or chapter counts
* mark the work complete if any of the 12 skandhas is missing an adhyāya
* claim public-domain status for the Wikimedia e-text (it is CC BY-SA 4.0)

GRETIL may be pointed at with ``--collate-gretil DIR`` later for reading
checks; that path is collation-only and never written as an edition source.

Usage
-----
    python3 scripts/generate_bhagavata_corpus.py              # fetch + write
    python3 scripts/generate_bhagavata_corpus.py --dry-run    # fetch, don't write
    python3 scripts/generate_bhagavata_corpus.py --parse-file wikitext.txt --skandha 1 --adhyaya 1

Exit codes
----------
0  complete corpus written (or dry-run parsed 335 chapters)
2  SOURCE BLOCKER (network / incomplete / refused source)
3  usage / parse error on a single file
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from translit import deva_to_iast  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content" / "bhagavata-purana"
API = "https://sa.wikisource.org/w/api.php"
ORIGIN = "https://sa.wikisource.org"
WORK_PREFIX = "श्रीमद्भागवतपुराणम्"
USER_AGENT = "DharmaLibraryBot/1.0 (https://github.com/ramnath086/dharma-library; corpus ingest)"

# Adhyāya pages on sa.wikisource (स्कन्धः spelling only). Verified by
# list=allpages; see docs/bhagavata-source-research.md.
SKANDHA_CHAPTERS: dict[int, int] = {
    1: 19, 2: 10, 3: 33, 4: 31, 5: 26, 6: 19,
    7: 15, 8: 24, 9: 24, 10: 90, 11: 31, 12: 13,
}
EXPECTED_CHAPTERS = sum(SKANDHA_CHAPTERS.values())  # 335

DEVA_DIGIT = str.maketrans("0123456789", "०१२३४५६७८९")
FROM_DEVA_DIGIT = str.maketrans("०१२३४५६७८९", "0123456789")

VERSE_END = re.compile(
    r"॥\s*([०१२३४५६७८९0-9]+)\s*॥"
)
SPEAKER_LINE = re.compile(
    r"^[\s\*]*([^\n]{1,80}?)\s+(उवाच|ऊचुः)\s*[।|]?\s*$"
)
COLOPHON = re.compile(r"^इति\s+श्रीमद्भागवत")
TEMPLATE = re.compile(r"\{\{[^{}]*\}\}")
LINK = re.compile(r"\[\[(?:[^\|\]]*\|)?([^\]]+)\]\]")
TAG = re.compile(r"<[^>]+>")
BOLD = re.compile(r"'{2,}")


class SourceBlocker(RuntimeError):
    """Rights-compatible source exists but cannot be ingested in this run."""


def deva_int(n: int) -> str:
    return str(n).translate(DEVA_DIGIT)


def parse_int(token: str) -> int:
    return int(token.translate(FROM_DEVA_DIGIT))


def chapter_title(skandha: int, adhyaya: int) -> str:
    return f"{WORK_PREFIX}/स्कन्धः {deva_int(skandha)}/अध्यायः {deva_int(adhyaya)}"


def strip_wiki(text: str) -> str:
    """Reduce MediaWiki markup to plain Devanagari suitable for verse splitting."""
    # Drop <noinclude> / <ref> bodies.
    text = re.sub(r"<noinclude>.*?</noinclude>", "\n", text, flags=re.S)
    text = re.sub(r"<ref\b[^>]*>.*?</ref>", "", text, flags=re.S)
    text = re.sub(r"<ref\b[^/]*/>", "", text)
    # Nested templates are uncommon in these mūla pages; peel a few layers.
    for _ in range(6):
        nxt = TEMPLATE.sub("", text)
        if nxt == text:
            break
        text = nxt
    text = LINK.sub(r"\1", text)
    text = TAG.sub("", text)
    text = BOLD.sub("", text)
    text = text.replace("&nbsp;", " ").replace("\xa0", " ")
    text = text.replace("।।", "॥")
    # Drop heading lines (== ... ==) and category links leftover.
    lines = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("=") and s.endswith("="):
            continue
        if s.startswith("[[Category:") or s.startswith("[[वर्ग:"):
            continue
        if s.startswith("#"):
            continue
        lines.append(line)
    return "\n".join(lines)


def parse_wikitext(wikitext: str, skandha: int, adhyaya: int) -> list[dict]:
    """Split a chapter's wikitext into numbered mūla verses.

    Returns dicts with ref, ordinal, kind, speaker, deva, iast. No translations
    are invented. Speaker is a surface string (Devanagari) when ``X उवाच``
    precedes the verse; it is not resolved to a graph slug here.
    """
    body = strip_wiki(wikitext)
    verses: list[dict] = []
    speaker: str | None = None
    expected: int | None = None

    def flush_nonverse(chunk: str) -> None:
        nonlocal speaker
        for raw in chunk.splitlines():
            line = raw.strip()
            if not line:
                continue
            if COLOPHON.match(line):
                continue
            m = SPEAKER_LINE.match(line)
            if m:
                speaker = re.sub(r"\s+", " ", m.group(1)).strip(" ।|*")
                continue

    parts = VERSE_END.split(body)
    # split → [pre, num, rest, num, rest, ...]
    if len(parts) < 3:
        raise SourceBlocker(
            f"{skandha}.{adhyaya}: no numbered verses (॥ N ॥) in wikitext"
        )
    flush_nonverse(parts[0])
    i = 1
    while i + 1 < len(parts):
        num = parse_int(parts[i])
        following = parts[i + 1]
        # The verse body is `buf` accumulated since the last marker, but because
        # we split on the marker the body is the *previous* leftover. We kept
        # that leftover in `buf` via flush for speakers only; the actual verse
        # text sits immediately before the marker, which split already removed.
        # Reconstruct: everything after the previous marker and before this one
        # is parts[i-1] minus speakers/colophon already consumed for i==1.
        raw_body = parts[i - 1]
        # For verses after the first, parts[i-1] is the text *after* the
        # previous number — correct. For the first verse, parts[0] includes
        # headers + speaker + verse body.
        verse_text, leading = _verse_body(raw_body)
        if leading:
            flush_nonverse(leading)
            # speaker may have updated; re-extract body without speaker lines
            verse_text, _ = _verse_body(raw_body)
        if not verse_text:
            raise SourceBlocker(f"{skandha}.{adhyaya}.{num}: empty mūla")
        if expected is None:
            expected = num
        if num != expected:
            raise SourceBlocker(
                f"{skandha}.{adhyaya}: expected verse {expected}, found {num}"
            )
        kind = "invocation" if (skandha, adhyaya, num) in {(1, 1, 1), (1, 1, 2), (1, 1, 3)} else "verse"
        verses.append({
            "ref": f"{skandha}.{adhyaya}.{num}",
            "ordinal": num,
            "kind": kind,
            "speaker": speaker,
            "deva": verse_text,
            "iast": _iast_lines(verse_text),
        })
        expected += 1
        speaker_after, _rest = _split_trailing_speaker(following)
        if speaker_after:
            speaker = speaker_after
        i += 2

    if not verses:
        raise SourceBlocker(f"{skandha}.{adhyaya}: parser produced 0 verses")
    return verses


def _split_trailing_speaker(text: str) -> tuple[str | None, str]:
    lines = text.splitlines()
    speaker = None
    kept: list[str] = []
    for line in lines:
        m = SPEAKER_LINE.match(line.strip())
        if m:
            speaker = re.sub(r"\s+", " ", m.group(1)).strip(" ।|*")
        else:
            kept.append(line)
    return speaker, "\n".join(kept)


def _verse_body(raw: str) -> tuple[str, str]:
    """Return (deva verse, leading non-verse text)."""
    lines = [ln.rstrip() for ln in raw.splitlines()]
    leading: list[str] = []
    body_idx = 0
    for i, ln in enumerate(lines):
        s = ln.strip()
        if not s:
            leading.append(ln)
            body_idx = i + 1
            continue
        if s.startswith("==") or COLOPHON.match(s) or s.startswith("{{"):
            leading.append(ln)
            body_idx = i + 1
            continue
        if SPEAKER_LINE.match(s):
            leading.append(ln)
            body_idx = i + 1
            continue
        # first real mūla line
        body_idx = i
        break
    body_lines = [ln.strip() for ln in lines[body_idx:] if ln.strip() and not COLOPHON.match(ln.strip())]
    # Drop a trailing speaker that belongs to the *next* verse (handled elsewhere).
    while body_lines and SPEAKER_LINE.match(body_lines[-1]):
        body_lines.pop()
    deva = "\n".join(body_lines).strip()
    deva = re.sub(r"[ \t]+", " ", deva)
    deva = re.sub(r"\n{3,}", "\n\n", deva).strip()
    return deva, "\n".join(leading)


def _iast_lines(deva: str) -> str:
    return "\n".join(deva_to_iast(line) for line in deva.split("\n"))


def api_get(params: dict) -> dict:
    q = urllib.parse.urlencode({**params, "format": "json", "formatversion": 2})
    req = urllib.request.Request(
        f"{API}?{q}",
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:  # noqa: BLE001 — surface every transport failure as the blocker
        raise SourceBlocker(
            "SOURCE BLOCKER: cannot reach sa.wikisource.org "
            f"({type(e).__name__}: {e}). Rights-compatible CC BY-SA 4.0 text "
            "exists but this environment cannot download it. Not fabricating "
            "verses. See docs/bhagavata-source-research.md."
        ) from e


def fetch_chapter(skandha: int, adhyaya: int) -> str:
    title = chapter_title(skandha, adhyaya)
    data = api_get({
        "action": "query",
        "prop": "revisions",
        "rvprop": "content",
        "rvslots": "main",
        "titles": title,
    })
    pages = data.get("query", {}).get("pages", [])
    if not pages or pages[0].get("missing"):
        raise SourceBlocker(f"missing Wikisource page: {title}")
    revs = pages[0].get("revisions") or []
    if not revs:
        raise SourceBlocker(f"no revision for {title}")
    slot = revs[0].get("slots", {}).get("main", {})
    text = slot.get("content") or revs[0].get("content")
    if not text:
        raise SourceBlocker(f"empty wikitext for {title}")
    return text


def merge_pilot_translations(new_verses: list[dict], existing_path: pathlib.Path) -> list[dict]:
    """Keep Dharma Library translations on 1.1.1–1.1.10; do not invent others."""
    if not existing_path.exists():
        return new_verses
    old = {v["ref"]: v for v in json.loads(existing_path.read_text(encoding="utf-8")).get("verses", [])}
    out = []
    for v in new_verses:
        prev = old.get(v["ref"])
        if prev:
            merged = dict(v)
            for k in ("en", "ml", "word_meanings", "notes_en", "mentions", "xrefs", "meter", "metadata"):
                if prev.get(k) is not None:
                    merged[k] = prev[k]
            # Prefer the existing speaker *slug* (including null) over उवाच surface strings.
            if "speaker" in prev:
                merged["speaker"] = prev["speaker"]
            if prev.get("kind"):
                merged["kind"] = prev["kind"]
            out.append(merged)
        else:
            out.append(v)
    return out


def write_chapter(skandha: int, adhyaya: int, verses: list[dict], section_meta: dict | None = None) -> pathlib.Path:
    path = CONTENT / str(skandha) / str(adhyaya) / "verses.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    section = existing.get("section") or {
        "canto": {
            "ref": str(skandha),
            "ordinal": skandha,
            "title_iast": f"Skandha {skandha}",
            "title_sa": f"स्कन्धः {deva_int(skandha)}",
        },
        "chapter": {
            "ref": f"{skandha}.{adhyaya}",
            "ordinal": adhyaya,
            "title_iast": f"Adhyāya {adhyaya}",
            "title_sa": f"अध्यायः {deva_int(adhyaya)}",
        },
    }
    if section_meta:
        section["chapter"].update(section_meta)
    payload = {
        "_note": (
            f"Śrīmad Bhāgavata Purāṇa {skandha}.{adhyaya} — Sanskrit mūla from "
            f"sa.wikisource.org ({ORIGIN}/wiki/{urllib.parse.quote(chapter_title(skandha, adhyaya))}), "
            "CC BY-SA 4.0. IAST via scripts/translit.py. Translations, where present, "
            "are original Dharma Library work (CC BY-SA 4.0) or omitted. "
            "GRETIL was not used as the shipped file."
        ),
        "section": section,
        "verses": verses,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def ingest_all(dry_run: bool, delay: float) -> dict:
    summary = {"skandhas": {}, "chapters": 0, "verses": 0, "source": ORIGIN, "license": "CC-BY-SA-4.0"}
    for sk, nchap in SKANDHA_CHAPTERS.items():
        ch_counts = []
        for adh in range(1, nchap + 1):
            wikitext = fetch_chapter(sk, adh)
            verses = parse_wikitext(wikitext, sk, adh)
            existing = CONTENT / str(sk) / str(adh) / "verses.json"
            verses = merge_pilot_translations(verses, existing)
            if not dry_run:
                write_chapter(sk, adh, verses)
            ch_counts.append(len(verses))
            summary["chapters"] += 1
            summary["verses"] += len(verses)
            print(f"  {sk}.{adh}: {len(verses)} verses")
            if delay:
                time.sleep(delay)
        if len(ch_counts) != nchap:
            raise SourceBlocker(f"skandha {sk}: expected {nchap} chapters, got {len(ch_counts)}")
        summary["skandhas"][str(sk)] = {"chapters": nchap, "verses": sum(ch_counts)}
    if summary["chapters"] != EXPECTED_CHAPTERS:
        raise SourceBlocker(
            f"incomplete: parsed {summary['chapters']} chapters, expected {EXPECTED_CHAPTERS}"
        )
    return summary


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--delay", type=float, default=0.4, help="seconds between API calls (be polite)")
    ap.add_argument("--parse-file", type=pathlib.Path, help="parse a local wikitext file instead of fetching")
    ap.add_argument("--skandha", type=int, default=1)
    ap.add_argument("--adhyaya", type=int, default=1)
    a = ap.parse_args()

    try:
        if a.parse_file:
            text = a.parse_file.read_text(encoding="utf-8")
            verses = parse_wikitext(text, a.skandha, a.adhyaya)
            print(json.dumps({"count": len(verses), "refs": [v["ref"] for v in verses]}, ensure_ascii=False, indent=2))
            return 0
        print(f"== Bhāgavata ingest from {ORIGIN} ({EXPECTED_CHAPTERS} chapters expected)")
        print("   GRETIL will not be written. Translations will not be invented.")
        summary = ingest_all(dry_run=a.dry_run, delay=a.delay)
        print("== done", json.dumps(summary, ensure_ascii=False))
        print(f"   actual verse count from this edition: {summary['verses']}")
        return 0
    except SourceBlocker as e:
        print(str(e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

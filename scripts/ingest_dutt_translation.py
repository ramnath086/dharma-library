#!/usr/bin/env python3
"""Ingest M. N. Dutt's public-domain English prose translation of the
Śrīmad Bhāgavata Purāṇa (Calcutta: H. C. Dass, 1895 / 1896).

Why this script exists
----------------------
The corpus in ``content/bhagavata-purana`` already ships the complete Sanskrit
mūla (12 skandhas, 335 adhyāyas). What is missing for most verses is an
English rendering. The only complete, rights-cleared English translation that
could be verified is Manmatha Nath Dutt's 1895/1896 prose translation, which is
in the public domain (published 1895/1896, well past any copyright term; the
Internet Archive scans carry no copyright page).

The hard part is **alignment**. Dutt states in his own introduction:

    "I have not considered it necessary to put in the numbers of the Slokas."

So the translation is continuous, unnumbered prose. Nothing in the source says
which śloka a given sentence renders. This script therefore:

1. downloads the verified Internet Archive scans,
2. parses them into (skandha, adhyāya) units,
3. splits each adhyāya into *sentences* (Dutt renders essentially one śloka
   per sentence in the 1895 edition),
4. aligns sentences to the refs already on disk, and
5. **only** writes a mapping when the alignment is unambiguous — one sentence
   per verse, in order, with matching counts. Anything it cannot align is left
   untouched and reported, never guessed.

Nothing is invented: if a chapter cannot be aligned confidently, its verses
keep whatever they already have and the gap is reported in
``docs/dutt-translation-coverage.json``.

Usage
-----
    python3 scripts/ingest_dutt_translation.py --report      # no writes
    python3 scripts/ingest_dutt_translation.py --write       # patch verses.json
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content" / "bhagavata-purana"
DOCS = ROOT / "docs"

# Verified public-domain scans on the Internet Archive. Every entry records the
# identifier, the exact derivative file, its sha1 (as published by archive.org)
# and the bibliographic details used for the `sources` / `rights` rows.
DUTT_SOURCES = [
    {
        "key": "dutt-1895-book-1-2",
        "identifier": "proseenglishtran12dutt",
        "file": "proseenglishtran12dutt_djvu.txt",
        "sha1": "ba350bc7c5930df5dbec102375619ad42a315305",
        "title": "A prose English translation of Śrīmadbhāgabatam, Books I–II",
        "date": "1895",
        "url": "https://archive.org/details/proseenglishtran12dutt",
    },
    {
        "key": "dutt-1895-book-7-12",
        "identifier": "india.history.resource.40625",
        "file": "40625_djvu.txt",
        "sha1": "2e84af8b06a9055511720c31bf0e39195b59c8ca",
        "title": "A prose English translation of Śrīmadbhāgabatam, Books VII–XII bound in one",
        "date": "1895",
        "url": "https://archive.org/details/india.history.resource.40625",
    },
    {
        "key": "dutt-1896-book-1-7",
        "identifier": "in.ernet.dli.2015.272582",
        "file": "2015.272582.Shrimad-Bhagwatam_djvu.txt",
        "sha1": "1208800ce2d334605197a6f097fb324315455890",
        "title": "Śrīmad Bhagwatam (prose English translation), Books I–VII",
        "date": "1896",
        "url": "https://archive.org/details/in.ernet.dli.2015.272582",
    },
]

FIELD = "en_dutt"          # verse JSON field that carries the Dutt rendering
EDITION_SLUG = "sb-en-dutt"

ROMAN = {"I": 1, "V": 5, "X": 10, "L": 50}


def roman_to_int(s: str) -> int | None:
    s = s.upper()
    if not s or any(c not in ROMAN for c in s):
        return None
    total = 0
    for i, c in enumerate(s):
        v = ROMAN[c]
        if i + 1 < len(s) and ROMAN[s[i + 1]] > v:
            total -= v
        else:
            total += v
    return total or None


def edit_distance(a: str, b: str) -> int:
    if a == b:
        return 0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def looks_like(word: str, target: str, tol: int = 2) -> bool:
    """OCR-safe 'is this garbled word actually `target`' test."""
    w = re.sub(r"[^A-Za-z]", "", word).upper()
    t = target.upper()
    if not w:
        return False
    if w == t:
        return True
    if abs(len(w) - len(t)) > tol:
        return False
    return edit_distance(w, t) <= tol


# ---------------------------------------------------------------- downloading

def download(src: dict, cache: pathlib.Path) -> str:
    cache.mkdir(parents=True, exist_ok=True)
    local = cache / (src["identifier"] + ".txt")
    if local.exists() and local.stat().st_size > 1000:
        return local.read_text(encoding="utf-8", errors="replace")
    url = f"https://archive.org/download/{src['identifier']}/{src['file']}"
    req = urllib.request.Request(url, headers={"User-Agent": "DharmaLibraryBot/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r:  # noqa: S310 (fixed https host)
        raw = r.read()
    text = raw.decode("utf-8", errors="replace")
    local.write_text(text, encoding="utf-8")
    return text


# ------------------------------------------------------------------- parsing

# A running header in these scans is an all-caps "SRIMADBHAGABATAM" optionally
# followed by a page number, sometimes with the letters spaced out by OCR.
def is_running_header(line: str) -> bool:
    s = line.strip()
    if not s or len(s) > 70:
        return False
    letters = [c for c in s if c.isalpha()]
    if len(letters) < 6:
        return False
    upper = sum(1 for c in letters if c.isupper())
    if upper / len(letters) < 0.6:
        return False
    compact = "".join(letters).upper()
    keys = ("SRIMADBHAGABATAM", "SIMADBHAGABATAM", "SIMADBAGABATAM", "SRIMADBHAGABAT",
            "BHAGABATAM", "BHAGABATA", "BHAGAWATAM", "BHAGBATAM", "BHAGAVATAM")
    for k in keys:
        idx = compact.find(k)
        if 0 <= idx <= 8:
            residual = (compact[:idx] + compact[idx + len(k):]).strip()
            if len(residual) <= 8:
                return True
    return False


def is_page_number(line: str) -> bool:
    s = line.strip()
    return bool(re.fullmatch(r"\d{1,4}", s))


def is_noise(line: str) -> bool:
    """OCR junk lines: stray punctuation, single letters, rules."""
    s = line.strip()
    if not s:
        return False
    alnum = [c for c in s if c.isalnum()]
    if len(alnum) < 3:
        return True
    if re.fullmatch(r"[\W_]+", s):
        return True
    return False


BOOK_RE = re.compile(r"^\s*([A-Za-z][A-Za-z'’]{1,7})\s+([IVXL]{1,6})\b")
CHAPTER_RE = re.compile(r"^\s*([A-Za-z][A-Za-z'’]{3,12})\s+([IVXL]{1,6})\b")
# Table-of-contents entries carry a trailing page reference ("— P. 4."); real
# chapter headings never do.
TOC_RE = re.compile(r"\bP\.\s*[ivxl0-9]|\bPage\s+\d|\bpp?\.\s*\d", re.I)

# Front matter / colophon junk that must never be treated as translation text.
FRONT_MATTER_RE = re.compile(
    r"^(contents|introduction|preface|index|book\s+[ivxl]+\s*$)", re.I)
STOP_RE = re.compile(
    r"(end\s+of\s+book|university\s+of\s+\w+|digitized\s+with\s+financial"
    r"|public\s+library|national\s+library|biblioth[eè]que"
    r"|printed\s+by\s+.{0,30}press)", re.I)

# How much body text must follow a heading for it to count as a real one.
MIN_CHAPTER_SPAN = 250
# How close a BOOK heading must be to a CHAPTER heading for the chapter to be
# considered part of the body (this is what rejects table-of-contents entries).
BOOK_LOOKBACK = 12


def parse_volume(text: str) -> dict[int, dict[int, dict]]:
    """Split a scan's OCR text into {book: {chapter: {'lines': [...]}}}."""
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    n = len(lines)

    # 1. locate candidate BOOK and CHAPTER headings
    def heading_num(line: str, pattern, word: str, tol: int) -> int | None:
        """Return the roman-numeral value if `line` is a bare heading line.

        A real heading line carries nothing but the word and the number.
        Table-of-contents entries carry a long description after it, and are
        rejected here.
        """
        m = pattern.match(line)
        if not m or not looks_like(m.group(1), word, tol):
            return None
        rest = line[m.end():].strip(" .:—-|\t")
        if len(rest) > 12:            # description / page reference follows
            return None
        if TOC_RE.search(line):
            return None
        return roman_to_int(m.group(2)) or 0

    book_at: dict[int, int] = {}
    chapter_at: dict[int, int] = {}
    for i, line in enumerate(lines):
        b = heading_num(line, BOOK_RE, "BOOK", 2)
        if b is not None:
            book_at[i] = b
            continue
        c = heading_num(line, CHAPTER_RE, "CHAPTER", 2)
        if c is not None:
            chapter_at[i] = c

    chapter_idx = sorted(chapter_at)
    book_idx = sorted(book_at)
    if not chapter_idx:
        return {}

    def nearest_book_before(i: int) -> int | None:
        best = None
        for b in book_idx:
            if b < i and i - b <= BOOK_LOOKBACK:
                best = book_at[b]
        return best

    # 2. a heading is "real" only when real body text follows before the next
    #    heading *and* a BOOK heading sits just above it. Both tests together
    #    discard the table of contents, whose entries are one short line each
    #    and only the first of which follows a BOOK line.
    real_chapters: list[tuple[int, int]] = []
    for pos, i in enumerate(chapter_idx):
        nxt = chapter_idx[pos + 1] if pos + 1 < len(chapter_idx) else n
        span = sum(len(x) for x in lines[i + 1:nxt])
        if span >= MIN_CHAPTER_SPAN and nearest_book_before(i) is not None:
            real_chapters.append((i, chapter_at[i]))
    if not real_chapters:
        return {}

    body_start = real_chapters[0][0]
    body_end = real_chapters[-1][0]

    # 3. walk the body, assigning lines to the current (book, chapter)
    out: dict[int, dict[int, dict]] = {}
    cur_book = nearest_book_before(body_start) or 0
    cur_chap = 0
    buf: list[str] = []

    def flush():
        nonlocal buf
        if cur_book and cur_chap:
            out.setdefault(cur_book, {}).setdefault(cur_chap, {"lines": []})["lines"].extend(buf)
        buf = []

    for i in range(body_start, n):
        line = lines[i]
        if i in book_at and i > body_start:
            flush()
            cur_book = book_at[i]
            continue          # the heading itself is not body text
        if i in chapter_at:
            if i > body_start:
                flush()
            cur_chap = chapter_at[i]
            continue          # the heading itself is not body text
        if is_running_header(line) or is_page_number(line):
            # kept in the buffer (so chapter_paragraphs can see the page
            # furniture and not break the paragraph there) but carries no text
            buf.append(line)
            continue
        if i > body_end and STOP_RE.search(line):
            break
        buf.append(line)
    flush()
    return out


def _is_removed(line: str) -> bool:
    """Lines the OCR emits that carry no translation text at all."""
    return is_running_header(line) or is_page_number(line)


def clean_paragraph(p: str) -> str:
    p = re.sub(r"\s+", " ", p).strip()
    # footnote markers Dutt uses inline
    p = re.sub(r"[\*\u2020\u2021\u00a7\u00b6]", "", p)
    p = re.sub(r"\s+([,.;:!?])", r"\1", p)
    return p.strip()


def chapter_paragraphs(chap: dict) -> list[str]:
    """Group a chapter's OCR lines into paragraphs.

    A page break in these scans shows up as ``<blank> <page no> <running
    header> <blank>``. Those lines are dropped, and a blank line that touches a
    dropped line is *not* treated as a paragraph break — otherwise every page
    boundary would cut a rendering in half.
    """
    raw = chap["lines"]
    removed = [_is_removed(l) for l in raw]
    paras: list[str] = []
    cur: list[str] = []

    def next_kept(j: int) -> int | None:
        for k in range(j + 1, len(raw)):
            if raw[k].strip():
                return k
        return None

    for i, line in enumerate(raw):
        if not line.strip():
            prev_removed = i > 0 and removed[i - 1]
            k = next_kept(i)
            next_removed = k is not None and removed[k]
            if prev_removed or next_removed:
                continue        # page furniture, not a paragraph break
            if cur:
                paras.append(clean_paragraph(" ".join(cur)))
                cur = []
            continue
        if removed[i] or is_noise(line):
            continue
        s = line.strip()
        # footnote text: Dutt's notes sit at the foot of the page and start
        # with a marker or a lowercase gloss word.
        if s.startswith(("*", "\u2020", "\u2021")) or re.match(r"^[a-z]\s", s):
            continue
        cur.append(s)
    if cur:
        paras.append(clean_paragraph(" ".join(cur)))
    # A paragraph that does not end in terminal punctuation was cut by the OCR
    # (or by a footnote) rather than by Dutt: stitch it to what follows.
    merged: list[str] = []
    for p in paras:
        if merged and not re.search(r"[.!?\"\u201d\u2019)]$", merged[-1]):
            merged[-1] = clean_paragraph(merged[-1] + " " + p)
        else:
            merged.append(p)
    return [p for p in merged if len(p) > 1]


SENT_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z\u201c\u2018\"'])")

# Abbreviations that must not end a sentence.
ABBR = ("Mr", "Mrs", "Dr", "St", "No", "Vol", "viz", "i.e", "e.g", "etc", "cf",
        "Op", "cit", "pp", "eds", "Skt", "San", "Lit")


def chapter_sentences(paras: list[str]) -> list[str]:
    out: list[str] = []
    for p in paras:
        parts = SENT_SPLIT.split(p)
        for part in parts:
            s = part.strip()
            if not s:
                continue
            # stitch back abbreviations that were split
            while out and re.search(r"\b(" + "|".join(re.escape(a) for a in ABBR) + r")\.$", out[-1]):
                out[-1] = out[-1] + " " + s
                s = ""
                break
            if s:
                out.append(s)
    return out


# ------------------------------------------------------------- corpus access

def load_corpus() -> dict[tuple[int, int], list[dict]]:
    corpus: dict[tuple[int, int], list[dict]] = {}
    for canto in sorted((p for p in CONTENT.iterdir() if p.is_dir() and p.name.isdigit()),
                        key=lambda p: int(p.name)):
        for chap_dir in sorted((p for p in canto.iterdir() if p.is_dir() and p.name.isdigit()),
                               key=lambda p: int(p.name)):
            f = chap_dir / "verses.json"
            if not f.exists():
                continue
            data = json.loads(f.read_text(encoding="utf-8"))
            corpus[(int(canto.name), int(chap_dir.name))] = data["verses"]
    return corpus


# ------------------------------------------------------------------ alignment

def align(sentences: list[str], verses: list[dict]) -> tuple[list[tuple[str, str]], str]:
    """Return ([(ref, sentence)], method).

    Only an unambiguous one-to-one, in-order mapping is accepted. Anything else
    is reported as unaligned rather than guessed.
    """
    if not sentences or not verses:
        return [], "empty"
    if len(sentences) == len(verses):
        return [(v["ref"], s) for v, s in zip(verses, sentences)], "one_to_one"
    # A chapter whose sentence count is short by a small amount usually means
    # Dutt merged a few neighbouring ślokas into one sentence. We do NOT guess:
    # those chapters are reported as unaligned.
    return [], "count_mismatch"


def build(cache: pathlib.Path) -> tuple[dict[str, str], dict]:
    corpus = load_corpus()
    mapping: dict[str, str] = {}
    report = {"volumes": [], "chapters": []}

    for src in DUTT_SOURCES:
        text = download(src, cache)
        parsed = parse_volume(text)
        vol = {"key": src["key"], "identifier": src["identifier"],
               "bytes": len(text), "books": sorted(parsed.keys()), "chapters": 0}
        for book in sorted(parsed):
            for chap_no in sorted(parsed[book]):
                verses = corpus.get((book, chap_no), [])
                paras = chapter_paragraphs(parsed[book][chap_no])
                sents = chapter_sentences(paras)
                pairs, method = align(sents, verses)
                vol["chapters"] += 1
                rec = {
                    "volume": src["key"], "skandha": book, "adhyaya": chap_no,
                    "corpus_verses": len(verses), "paragraphs": len(paras),
                    "sentences": len(sents), "aligned": len(pairs), "method": method,
                }
                report["chapters"].append(rec)
                for ref, sentence in pairs:
                    if ref not in mapping:      # first verified witness wins
                        mapping[ref] = sentence
        report["volumes"].append(vol)
    return mapping, report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--cache", default=str(ROOT / ".dutt-cache"))
    a = ap.parse_args()

    cache = pathlib.Path(a.cache)
    mapping, report = build(cache)

    total = sum(len(v) for v in load_corpus().values())
    covered = len(mapping)
    report["summary"] = {
        "corpus_verses": total,
        "aligned_verses": covered,
        "coverage": round(covered / total, 4) if total else 0.0,
        "field": FIELD,
        "edition": EDITION_SLUG,
    }
    DOCS.mkdir(parents=True, exist_ok=True)
    (DOCS / "dutt-translation-coverage.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    by_method: dict[str, int] = {}
    for rec in report["chapters"]:
        by_method[rec["method"]] = by_method.get(rec["method"], 0) + 1
    print(f"Dutt alignment: {covered}/{total} verses "
          f"({report['summary']['coverage']:.1%}) methods={by_method}")
    for vol in report["volumes"]:
        print(f"  {vol['key']}: books {vol['books']} chapters {vol['chapters']} "
              f"({vol['bytes']} bytes OCR)")

    if a.write:
        changed = 0
        for (canto, chap), verses in load_corpus().items():
            path = CONTENT / str(canto) / str(chap) / "verses.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            dirty = False
            for v in data["verses"]:
                new = mapping.get(v["ref"])
                if new and v.get(FIELD) != new:
                    v[FIELD] = new
                    dirty = True
            if dirty:
                path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                                encoding="utf-8")
                changed += 1
        print(f"wrote {FIELD} into {changed} chapter files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

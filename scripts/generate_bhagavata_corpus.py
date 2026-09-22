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
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(__file__))
from translit import deva_to_iast  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content" / "bhagavata-purana"
API = "https://sa.wikisource.org/w/api.php"
ORIGIN = "https://sa.wikisource.org"
WORK_PREFIX = "श्रीमद्भागवतपुराणम्"
USER_AGENT = "DharmaLibraryBot/1.0 (https://github.com/ramnath086/dharma-library; corpus ingest; CC BY-SA 4.0)"
LICENSE = "CC-BY-SA-4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by-sa/4.0/"
ATTRIBUTION = "Sanskrit Wikisource contributors"

# Adhyāya pages on sa.wikisource (स्कन्धः spelling only). Verified by
# list=allpages on 2026-09-21; see docs/bhagavata-source-research.md.
# Skandha 10 lives under पूर्वार्धः (1–49) / उत्तरार्धः (50–90), not
# स्कन्धः १०/अध्यायः N.
SKANDHA_CHAPTERS: dict[int, int] = {
    1: 19, 2: 10, 3: 33, 4: 31, 5: 26, 6: 19,
    7: 15, 8: 24, 9: 24, 10: 90, 11: 31, 12: 13,
}
EXPECTED_CHAPTERS = sum(SKANDHA_CHAPTERS.values())  # 335
SKANDHA_10_PURVA_LAST = 49

DEVA_DIGIT = str.maketrans("0123456789", "०१२३४५६७८९")
FROM_DEVA_DIGIT = str.maketrans("०१२३४५६७८९", "0123456789")

# Numbering styles on sa.wikisource Bhāgavata pages (detected per chapter):
#   A  ॥ N ॥ / । N ॥ / । ०९ ॥ / compact ॥N॥
#   B  one-or-two spaces + N at EOL (gadya; used when A/C/D are absent, e.g. 5.1–5.2, 12.x)
#   C  N। after a pāda (skandhas 7–8). Style B is never mixed into a chapter
#      that already has A/C/D markers — leftover « १» after 1.1.23 is not a verse.
#   D  ॥ ०५.२४.००१ ॥  (sk.adh.verse with leading zeros; 5.24)
_DEVA_NUM = r"[०१२३४५६७८९0-9]+"
VERSE_END_CLASSIC = re.compile(
    rf"[।॥]\s*({_DEVA_NUM})\s*[।॥]"
)
VERSE_END_BARE = re.compile(
    rf"(?<=[ \t])({_DEVA_NUM})(?=[ \t]*$|[ \t]{{2}})",
    re.M,
)
# Gadya close glued to the last akṣara: «वर्णयिष्यामः१२» (5.4). Only used
# when the chapter has no danda-delimited numbers (same gate as BARE).
VERSE_END_GLUED_EOL = re.compile(
    rf"(?<=[\u0900-\u097F])({_DEVA_NUM})[ \t]*$",
    re.M,
)
VERSE_END_NUM_DANDA = re.compile(
    rf"[ \t]+({_DEVA_NUM})(?:[ \t]+[\u0900-\u097F]+)?[ \t]*[।॥]"
)
# Number glued to the last akṣara then a danda: «माम्२३।» / «दुःखम्५२।».
# Always on (unlike gadya-only GLUED_EOL) because these chapters already
# use danda-delimited numbers.
VERSE_END_GLUED_DANDA = re.compile(
    rf"(?<=[\u0900-\u097F])({_DEVA_NUM})[ \t]*[।॥]"
)
# Compact close after a MediaWiki line-break: « \\१७॥ » (1.15).
VERSE_END_ESCAPED = re.compile(
    rf"\\+({_DEVA_NUM})[।॥]"
)
# Opening danda + number at EOL, no close: «॥ ३९» then newline (5.26).
VERSE_END_OPEN_EOL = re.compile(
    rf"[।॥]\s*({_DEVA_NUM})\s*$",
    re.M,
)
# D  ॥ ०५.२४.००१ ॥  (sk.adh.verse with leading zeros; 5.24+)
VERSE_END_DOTTED = re.compile(
    rf"[।॥]\s*{_DEVA_NUM}\.{_DEVA_NUM}\.({_DEVA_NUM})\s*[।॥]"
)
# Same-line empty close «॥ ॥» (no digits): Wikisource omitted the printed
# number but the mūla is on the page (10.11.11, 9.11.11). Newlines-only
# «॥\n॥» is two numbered verses, not an empty marker.
VERSE_END_EMPTY = re.compile(r"॥[ \t]*॥")
# Split tens/units leftover after a classic split: « ६ ॥» following «॥ २ ॥».
_SPLIT_REST_DIGIT = re.compile(
    rf"^\s*({_DEVA_NUM})\s*[।॥]"
)
UNNUMBERED = -1
SPEAKER_LINE = re.compile(
    r"^[\s\*]*([^\n]{1,80}?)\s+(उवाच|ऊचुः)\s*[।|]?\s*$"
)
COLOPHON = re.compile(r"^इति\s+श्रीम?द्?भागवत")
# Colophon lines like «प्रथमोऽध्यायः ॥ १ ॥» or «द्वितीयोध्याऽयः ॥ २ ॥»
# (avagraha may sit before अध्यायः or inside it).
CHAPTER_END = re.compile(r"ध्या['ऽ]?यः\s*॥")
METER_LABEL = re.compile(r"^\([^)]+\)\s*$")
TEMPLATE = re.compile(r"\{\{[^{}]*\}\}", re.S)
LINK = re.compile(r"\[\[(?:[^|\]]*\|)?([^\]]+)\]\]")
TAG = re.compile(r"<[^>]+>")
BOLD = re.compile(r"'{2,}")
DEVANAGARI_CHAR = re.compile(r"[\u0900-\u097F]")

# Surface उवाच labels → graph slugs already present in graph.json.
# Unmapped speakers are stored as metadata.speaker_surface, never invented people.
SPEAKER_SLUGS = {
    "सूत": "suta",
    "सूतः": "suta",
    "ऋषयः": "sages-of-naimisaranya",
    "ऋषय": "sages-of-naimisaranya",
    "शौनक": "saunaka",
    "शौनकः": "saunaka",
    "शुक": "suka",
    "शुकः": "suka",
    "श्रीशुक": "suka",
    "श्रीशुकः": "suka",
    "व्यास": "vyasa",
    "व्यासः": "vyasa",
    "ब्रह्मा": "brahma",
    "ब्रह्मन्": "brahma",
}


class SourceBlocker(RuntimeError):
    """Rights-compatible source exists but cannot be ingested in this run."""


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def deva_int(n: int) -> str:
    return str(n).translate(DEVA_DIGIT)


def parse_int(token: str) -> int:
    return int(token.translate(FROM_DEVA_DIGIT))


def _iter_markers(body: str, *, allow_bare: bool = False) -> list[tuple[int, int, int]]:
    """Locate verse-number markers; drop overlaps; join adjacent split digits."""
    hits: list[tuple[int, int, int]] = []
    pats = [VERSE_END_CLASSIC, VERSE_END_NUM_DANDA, VERSE_END_GLUED_DANDA, VERSE_END_ESCAPED, VERSE_END_OPEN_EOL, VERSE_END_DOTTED]
    if allow_bare:
        pats.append(VERSE_END_BARE)
        pats.append(VERSE_END_GLUED_EOL)
    for pat in pats:
        for m in pat.finditer(body):
            hits.append((m.start(), m.end(), parse_int(m.group(1))))
    for m in VERSE_END_EMPTY.finditer(body):
        hits.append((m.start(), m.end(), UNNUMBERED))
    hits.sort(key=lambda h: (h[0], -(h[1] - h[0])))
    uniq: list[tuple[int, int, int]] = []
    last_end = -1
    for s, e, n in hits:
        if s < last_end:
            continue
        uniq.append((s, e, n))
        last_end = e
    merged: list[tuple[int, int, int]] = []
    i = 0
    while i < len(uniq):
        s, e, n = uniq[i]
        if i + 1 < len(uniq):
            s2, e2, n2 = uniq[i + 1]
            if body[e:s2].strip() == "" and n > 0 and n2 > 0 and n < 100 and n2 < 10:
                merged.append((s, e2, int(str(n) + str(n2))))
                i += 2
                continue
        merged.append((s, e, n))
        i += 1
    return merged


def _split_verse_markers(body: str, *, allow_bare: bool | None = None) -> list[str]:
    """Like ``re.split`` with one capturing group: [pre, num, rest, num, rest, …].

    Bare line-numbers (style B) are used only when the chapter has no
    danda-delimited numbers. That covers 5.1–5.2 and 12.x gadya without
    letting a leftover « १» rewind a classic chapter such as 1.1.
    """
    if allow_bare is None:
        markers = _iter_markers(body, allow_bare=False)
        if not markers:
            markers = _iter_markers(body, allow_bare=True)
    else:
        markers = _iter_markers(body, allow_bare=allow_bare)
    if not markers:
        return [body]
    parts: list[str] = []
    prev = 0
    for s, e, n in markers:
        parts.append(body[prev:s])
        parts.append(str(n))
        prev = e
    parts.append(body[prev:])
    return parts


def chapter_title(skandha: int, adhyaya: int) -> str:
    """Canonical sa.wikisource title for one adhyāya.

    Skandha 10 is split पूर्वार्धः (1–49) / उत्तरार्धः (50–90) on the
    स्कन्धः tree. Other skandhas are ``स्कन्धः N/अध्यायः M``. The
    duplicate ``स्कन्दः`` tree is never used.
    """
    sk = f"{WORK_PREFIX}/स्कन्धः {deva_int(skandha)}"
    adh = f"अध्यायः {deva_int(adhyaya)}"
    if skandha == 10:
        half = "पूर्वार्धः" if adhyaya <= SKANDHA_10_PURVA_LAST else "उत्तरार्धः"
        return f"{sk}/{half}/{adh}"
    return f"{sk}/{adh}"


def chapter_url(skandha: int, adhyaya: int) -> str:
    return f"{ORIGIN}/wiki/{urllib.parse.quote(chapter_title(skandha, adhyaya))}"


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
    text = text.replace("\u200c", "").replace("\u200d", "")  # ZWNJ/ZWJ in श्रीमद्‌भागवत
    text = text.replace("।।", "॥")
    # Editorial footnotes, not mūla: «१६ [http://… टिप्पणी]।», «२० (…पाठभेदः)।».
    text = re.sub(r"\[https?://[^\]]+\]", "", text)
    text = re.sub(r"\([^)]*पाठभेद[^)]*\)", "", text)
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
        if s.lower().startswith("thumb|") or s.lower().startswith("file:"):
            continue
        if s.startswith("तुलनीय"):
            continue
        if re.fullmatch(r"अथ.{0,24}ध्या['ऽ]?यः", s):
            continue
        if s and not DEVANAGARI_CHAR.search(s):
            continue
        if COLOPHON.match(s):
            # Chapter is over. Trailing duplicate dumps (6.18 repeats 1। after
            # the इति line) must not be parsed as more mūla.
            break
        if CHAPTER_END.search(s):
            continue
        if METER_LABEL.match(s):
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
    last_printed = 0
    printed_count: dict[int, int] = {}

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

    def emit_verse(printed: int, verse_text: str, who: str | None, extra_meta: dict | None = None) -> None:
        """Append one verse. ``ordinal`` is dense reading order; ``ref`` keeps the page number."""
        nonlocal last_printed
        if printed < 1:
            raise SourceBlocker(f"{skandha}.{adhyaya}: non-positive verse number {printed}")
        if last_printed and printed < last_printed:
            raise SourceBlocker(
                f"{skandha}.{adhyaya}: printed number went backwards ({last_printed} → {printed})"
            )
        seq = len(verses) + 1
        printed_count[printed] = printed_count.get(printed, 0) + 1
        occ = printed_count[printed]
        if occ == 1:
            ref = f"{skandha}.{adhyaya}.{printed}"
        elif occ <= 26:
            ref = f"{skandha}.{adhyaya}.{printed}{chr(ord('a') + occ - 1)}"
        else:
            raise SourceBlocker(
                f"{skandha}.{adhyaya}: printed ॥ {printed} ॥ repeated {occ} times"
            )
        meta = dict(extra_meta or {})
        notes: list[str] = []
        if last_printed and printed > last_printed + 1:
            skipped = ", ".join(str(i) for i in range(last_printed + 1, printed))
            notes.append(
                f"Wikisource numbering skipped {skipped}; no mūla invented for the gap."
            )
        if occ > 1:
            notes.append(
                f"Wikisource printed this number {occ} times; occurrence {occ} is a separate verse (ref {ref})."
            )
        if seq != printed or occ > 1:
            meta["wikisource_number"] = printed
        if notes:
            prev_note = meta.get("numbering_note")
            meta["numbering_note"] = " ".join([prev_note, *notes] if prev_note else notes)
        kind = "invocation" if (skandha, adhyaya, printed) in {(1, 1, 1), (1, 1, 2), (1, 1, 3)} else "verse"
        numbered = f"{verse_text} ॥ {deva_int(printed)} ॥"
        payload = {
            "ref": ref,
            "ordinal": seq,
            "kind": kind,
            "speaker": who,
            "deva": numbered,
            "iast": _iast_lines(numbered),
        }
        if meta:
            payload["metadata"] = meta
        verses.append(payload)
        last_printed = printed

    parts = _split_verse_markers(body)  # auto: bare only if no danda markers
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
        dropped_digit_note = None
        if num == UNNUMBERED:
            # «॥ ॥» with no digits: mūla is on the page, number omitted.
            nxt = None
            if i + 2 < len(parts):
                try:
                    nxt = parse_int(parts[i + 2])
                except ValueError:
                    nxt = None
            expected_n = (last_printed + 1) if last_printed else 1
            if nxt == expected_n + 1:
                dropped_digit_note = (
                    "Wikisource closed this śloka with ॥ ॥ (no printed number); "
                    f"kept as {expected_n} because the previous marker is "
                    f"{last_printed or 0} and the next is {nxt} "
                    "(text from the page, numbering supplied)."
                )
                num = expected_n
            elif nxt == expected_n:
                # «॥ ॥ ६ ॥» after 5: empty overlaps the real close of 6.
                # Do not emit a second verse; keep the mūla for printed 6.
                parts[i + 1] = parts[i - 1] + parts[i + 1]
                i += 2
                continue
            else:
                raise SourceBlocker(
                    f"{skandha}.{adhyaya}: unnumbered ॥ ॥ after {last_printed} "
                    f"before {nxt}; not inventing a verse number"
                )

        def peek_next() -> int | None:
            if i + 2 >= len(parts):
                return None
            try:
                nxt = parse_int(parts[i + 2])
            except ValueError:
                return None
            if i + 3 < len(parts):
                m_n = _SPLIT_REST_DIGIT.match(parts[i + 3])
                if m_n:
                    nxt = int(str(nxt) + m_n.group(1).translate(FROM_DEVA_DIGIT))
            return nxt

        if last_printed and num < last_printed:
            # «॥ २ ॥ ६ ॥» after verse 25 is 26, not a jump back to 2.
            m_rest = _SPLIT_REST_DIGIT.match(following)
            if m_rest:
                joined = int(str(num) + m_rest.group(1).translate(FROM_DEVA_DIGIT))
                if joined > last_printed:
                    num = joined
                    following = following[m_rest.end():]
        if last_printed and num < last_printed:
            # «॥ २ ॥» then «॥ २७ ॥» after 25 is 26 with a dropped units digit (4.6).
            nxt = peek_next()
            expected_n = last_printed + 1
            if nxt == last_printed + 2 and str(expected_n).startswith(str(num)):
                dropped_digit_note = (
                    f"Wikisource printed ॥ {deva_int(num)} ॥ here; "
                    f"kept as {expected_n} because the next marker is {nxt} "
                    f"(dropped digit; no Sanskrit invented)."
                )
                num = expected_n
        if last_printed and num > last_printed + 1:
            # «॥ ८३ ।» then «॥ ९ ॥» after 7 is 8 with a stray trailing digit (7.4).
            nxt = peek_next()
            expected_n = last_printed + 1
            if nxt == expected_n + 1 and str(num).startswith(str(expected_n)):
                dropped_digit_note = (
                    f"Wikisource printed ॥ {deva_int(num)} ॥ here; "
                    f"kept as {expected_n} because the next marker is {nxt} "
                    f"(extra digit; no Sanskrit invented)."
                )
                num = expected_n
            elif nxt == last_printed + 1 and str(num).startswith(str(last_printed)):
                # «॥ ३२३ ।» after 32 before 33 is a garbled reprint of 32 (7.4).
                dropped_digit_note = (
                    f"Wikisource printed ॥ {deva_int(num)} ॥ here; "
                    f"kept as {last_printed} (garbled extra digit; no Sanskrit invented)."
                )
                num = last_printed
        raw_body = parts[i - 1]
        if not verses and num == 2:
            # Wikisource sometimes leaves the opening śloka unnumbered
            # (e.g. 1.7: Shaunaka's question has no ॥ १ ॥, then ॥। २ ॥).
            # Split on the last उवाच so verse 2 is not duplicated. Text is from
            # the page; only the missing *number* is supplied.
            before, v2_speaker, after = _split_at_last_speaker(raw_body)
            open_text, _open_lead = _verse_body(before)
            open_text = open_text.rstrip().rstrip("।॥").strip()
            if open_text:
                emit_verse(1, open_text, _last_speaker_in(before), extra_meta={
                    "numbering_note": (
                        "Opening mūla had no ॥ १ ॥ on Wikisource; "
                        "kept as verse 1 of this chapter (text from the page, numbering supplied)."
                    )
                })
                if v2_speaker:
                    speaker = v2_speaker
                raw_body = after
            else:
                raise SourceBlocker(
                    f"{skandha}.{adhyaya}: first numbered verse is 2, expected 1"
                )
        verse_text, leading = _verse_body(raw_body)
        if leading:
            flush_nonverse(leading)
            verse_text, _ = _verse_body(raw_body)
        if not verse_text:
            raise SourceBlocker(f"{skandha}.{adhyaya}.{num}: empty mūla")
        extra = {"numbering_note": dropped_digit_note} if dropped_digit_note else None
        emit_verse(num, verse_text, speaker, extra_meta=extra)
        speaker_after, _rest = _split_trailing_speaker(following)
        if speaker_after:
            speaker = speaker_after
        i += 2

    if not verses:
        raise SourceBlocker(f"{skandha}.{adhyaya}: parser produced 0 verses")
    return verses


def _speaker_from_match(m: re.Match) -> str:
    return re.sub(r"\s+", " ", m.group(1)).strip(" ।|*")


def _last_speaker_in(raw: str) -> str | None:
    speaker = None
    for ln in raw.splitlines():
        m = SPEAKER_LINE.match(ln.strip())
        if m:
            speaker = _speaker_from_match(m)
    return speaker


def _split_at_last_speaker(raw: str) -> tuple[str, str | None, str]:
    """Split ``raw`` on the last उवाच line: (before, speaker, after)."""
    lines = raw.splitlines()
    last_i = None
    last_speaker = None
    for i, ln in enumerate(lines):
        m = SPEAKER_LINE.match(ln.strip())
        if m:
            last_i = i
            last_speaker = _speaker_from_match(m)
    if last_i is None:
        return raw, None, ""
    before = "\n".join(lines[:last_i])
    after = "\n".join(lines[last_i + 1:])
    return before, last_speaker, after


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
        if s.startswith("==") or COLOPHON.match(s) or CHAPTER_END.search(s) or s.startswith("{{"):
            leading.append(ln)
            body_idx = i + 1
            continue
        if METER_LABEL.match(s):
            leading.append(ln)
            body_idx = i + 1
            continue
        if SPEAKER_LINE.match(s):
            leading.append(ln)
            body_idx = i + 1
            continue
        body_idx = i
        break
    body_lines = [ln.strip() for ln in lines[body_idx:] if ln.strip() and not COLOPHON.match(ln.strip())]
    while body_lines and SPEAKER_LINE.match(body_lines[-1]):
        body_lines.pop()
    deva = "\n".join(body_lines).strip()
    deva = re.sub(r"[ \t]+", " ", deva)
    deva = re.sub(r"\n{3,}", "\n\n", deva).strip()
    return deva, "\n".join(leading)


def _iast_lines(deva: str) -> str:
    return "\n".join(deva_to_iast(line) for line in deva.split("\n"))


def apply_speaker_slugs(verses: list[dict]) -> None:
    """Map known उवाच labels onto graph slugs; never invent people."""
    for v in verses:
        raw = v.get("speaker")
        if not raw:
            continue
        key = re.sub(r"\s+", " ", str(raw)).strip(" ।|*")
        slug = SPEAKER_SLUGS.get(key)
        if slug:
            v["speaker"] = slug
            continue
        meta = dict(v.get("metadata") or {})
        meta["speaker_surface"] = raw
        v["metadata"] = meta
        v["speaker"] = None


def _parse_api_json(raw: str) -> dict:
    data = json.loads(raw)
    if isinstance(data, dict) and data.get("error"):
        raise SourceBlocker(f"MediaWiki API error: {data['error']}")
    return data


def _curl_api(encoded: str) -> dict:
    curl = shutil.which("curl")
    if not curl:
        raise FileNotFoundError("curl not on PATH")
    proc = subprocess.run(
        [
            curl, "-sS", "-G",
            "-A", USER_AGENT,
            "--max-time", "60",
            "-H", "Accept: application/json",
            "--data", encoded,
            API,
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise OSError(f"curl exit {proc.returncode}: {(proc.stderr or proc.stdout)[:400]}")
    if not proc.stdout.strip():
        raise OSError("curl returned empty body")
    return _parse_api_json(proc.stdout)


def _urllib_api(encoded: str) -> dict:
    req = urllib.request.Request(
        API,
        data=encoded.encode("utf-8"),
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read().decode("utf-8")
    return _parse_api_json(raw)


def api_request(params: dict, retries: int = 5) -> dict:
    payload = {**params, "format": "json", "formatversion": "2", "maxlag": "5"}
    encoded = urllib.parse.urlencode(payload)
    last: Exception | None = None
    for attempt in range(retries):
        for transport, fn in (("curl", _curl_api), ("urllib", _urllib_api)):
            try:
                return fn(encoded)
            except SourceBlocker as e:
                err = str(e)
                if "maxlag" in err or "ratelimited" in err:
                    last = e
                    print(f"   ! {transport} {err}", flush=True)
                    break
                raise
            except Exception as e:  # noqa: BLE001 — every transport failure is the blocker
                last = e
                print(f"   ! {transport} {type(e).__name__}: {e}", flush=True)
                continue
        if attempt + 1 < retries:
            time.sleep(2 ** attempt)
    raise SourceBlocker(
        "SOURCE BLOCKER: cannot reach sa.wikisource.org "
        f"({type(last).__name__}: {last}). Rights-compatible CC BY-SA 4.0 text "
        "exists but this environment cannot download it. Not fabricating "
        "verses. See docs/bhagavata-source-research.md."
    ) from last


def probe_api() -> None:
    print(f"   probing {API} …", flush=True)
    data = api_request({"action": "query", "meta": "siteinfo", "siprop": "general"})
    general = (data.get("query") or {}).get("general") or {}
    print(f"   siteinfo wikiid={general.get('wikiid')} generator={general.get('generator')}", flush=True)


def fetch_pages(titles: list[str]) -> dict[str, dict]:
    """Return title → {content, pageid, revid, timestamp, sha1, resolved_title}."""
    data = api_request({
        "action": "query",
        "prop": "revisions",
        "rvprop": "content|ids|timestamp|sha1",
        "rvslots": "main",
        "titles": "|".join(titles),
        "redirects": "1",
    })
    redirects = {r["from"]: r["to"] for r in data.get("query", {}).get("redirects", [])}
    normalized = {n["from"]: n["to"] for n in data.get("query", {}).get("normalized", [])}
    pages = data.get("query", {}).get("pages", [])
    by_title = {p.get("title"): p for p in pages}

    def resolve(title: str) -> str:
        t = normalized.get(title, title)
        t = redirects.get(t, t)
        return t

    out: dict[str, dict] = {}
    for title in titles:
        resolved = resolve(title)
        page = by_title.get(resolved)
        if not page or page.get("missing"):
            raise SourceBlocker(f"missing Wikisource page: {title}")
        revs = page.get("revisions") or []
        if not revs:
            raise SourceBlocker(f"no revision for {title}")
        slot = revs[0].get("slots", {}).get("main", {})
        text = slot.get("content") or revs[0].get("content")
        if not text:
            raise SourceBlocker(f"empty wikitext for {title}")
        out[title] = {
            "content": text,
            "pageid": page.get("pageid"),
            "revid": revs[0].get("revid"),
            "timestamp": revs[0].get("timestamp"),
            "sha1": revs[0].get("sha1"),
            "resolved_title": resolved,
        }
    return out


def fetch_chapter(skandha: int, adhyaya: int) -> dict:
    title = chapter_title(skandha, adhyaya)
    return fetch_pages([title])[title]


def merge_pilot_translations(new_verses: list[dict], existing_path: pathlib.Path) -> list[dict]:
    """Keep Dharma Library translations on 1.1.1–1.1.10; do not invent others.

    Overlapping verses also keep the already-shipped editorial Devanagari / IAST
    (word-breaks, notes, audio cues). New verses stay Wikisource-only.
    """
    if not existing_path.exists():
        return new_verses
    old = {v["ref"]: v for v in json.loads(existing_path.read_text(encoding="utf-8")).get("verses", [])}
    out = []
    keep_keys = (
        "en", "ml", "word_meanings", "notes_en", "mentions", "xrefs",
        "meter", "metadata", "deva", "iast", "kind",
    )
    for v in new_verses:
        prev = old.get(v["ref"])
        if prev:
            merged = dict(v)
            for k in keep_keys:
                if prev.get(k) is not None:
                    merged[k] = prev[k]
            if "speaker" in prev:
                merged["speaker"] = prev["speaker"]
            out.append(merged)
        else:
            out.append(v)
    return out


def write_chapter(
    skandha: int,
    adhyaya: int,
    verses: list[dict],
    source: dict | None = None,
    retrieved: str | None = None,
) -> pathlib.Path:
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
    title = chapter_title(skandha, adhyaya)
    url = chapter_url(skandha, adhyaya)
    src = {
        "url": url,
        "title": title,
        "retrieved": retrieved or utc_now(),
        "license": LICENSE,
        "license_url": LICENSE_URL,
        "attribution": ATTRIBUTION,
        "transformation": (
            "MediaWiki wikitext stripped of templates/links; verses split on "
            "॥ N ॥; IAST via scripts/translit.py. No translations invented. "
            "GRETIL was not used as the shipped file."
        ),
    }
    if source:
        for k in ("pageid", "revid", "timestamp", "sha1", "resolved_title"):
            if source.get(k) is not None:
                src[k] = source[k]
    payload = {
        "_note": (
            f"Śrīmad Bhāgavata Purāṇa {skandha}.{adhyaya} — Sanskrit mūla from "
            f"sa.wikisource.org ({url}), {LICENSE.replace('-', ' ')}. "
            "IAST via scripts/translit.py. Translations, where present, "
            "are original Dharma Library work (CC BY-SA 4.0) or omitted. "
            "GRETIL was not used as the shipped file."
        ),
        "_source": src,
        "section": section,
        "verses": verses,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def planned_chapters(only_skandha: int | None = None) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for sk, nchap in SKANDHA_CHAPTERS.items():
        if only_skandha is not None and sk != only_skandha:
            continue
        for adh in range(1, nchap + 1):
            out.append((sk, adh))
    return out


def ingest_all(dry_run: bool, delay: float, batch_size: int, only_skandha: int | None = None) -> dict:
    retrieved = utc_now()
    planned = planned_chapters(only_skandha)
    summary: dict = {
        "retrieved": retrieved,
        "source": ORIGIN,
        "index": f"{ORIGIN}/wiki/{WORK_PREFIX}",
        "license": LICENSE,
        "license_url": LICENSE_URL,
        "attribution": ATTRIBUTION,
        "skandhas": {},
        "chapters": 0,
        "verses": 0,
        "pages": [],
    }
    by_sk: dict[int, list[int]] = {}

    for i in range(0, len(planned), batch_size):
        batch = planned[i:i + batch_size]
        titles = [chapter_title(sk, adh) for sk, adh in batch]
        pages = fetch_pages(titles)
        for (sk, adh), title in zip(batch, titles):
            page = pages[title]
            verses = parse_wikitext(page["content"], sk, adh)
            if verses[0]["ordinal"] != 1:
                raise SourceBlocker(
                    f"{sk}.{adh}: first numbered verse is {verses[0]['ordinal']}, expected 1"
                )
            apply_speaker_slugs(verses)
            existing = CONTENT / str(sk) / str(adh) / "verses.json"
            verses = merge_pilot_translations(verses, existing)
            if not dry_run:
                write_chapter(sk, adh, verses, source=page, retrieved=retrieved)
            by_sk.setdefault(sk, []).append(len(verses))
            summary["chapters"] += 1
            summary["verses"] += len(verses)
            summary["pages"].append({
                "skandha": sk,
                "adhyaya": adh,
                "title": title,
                "url": chapter_url(sk, adh),
                "pageid": page.get("pageid"),
                "revid": page.get("revid"),
                "timestamp": page.get("timestamp"),
                "sha1": page.get("sha1"),
                "verses": len(verses),
            })
            print(f"  {sk}.{adh}: {len(verses)} verses (revid {page.get('revid')})")
        if delay:
            time.sleep(delay)

    for sk, nchap in SKANDHA_CHAPTERS.items():
        if only_skandha is not None and sk != only_skandha:
            continue
        counts = by_sk.get(sk, [])
        if len(counts) != nchap:
            raise SourceBlocker(f"skandha {sk}: expected {nchap} chapters, got {len(counts)}")
        summary["skandhas"][str(sk)] = {"chapters": nchap, "verses": sum(counts)}

    if only_skandha is None and summary["chapters"] != EXPECTED_CHAPTERS:
        raise SourceBlocker(
            f"incomplete: parsed {summary['chapters']} chapters, expected {EXPECTED_CHAPTERS}"
        )
    return summary


def write_manifest(summary: dict) -> pathlib.Path:
    path = CONTENT / "WIKISOURCE_MANIFEST.json"
    payload = {
        "retrieved": summary["retrieved"],
        "license": LICENSE,
        "license_url": LICENSE_URL,
        "attribution": ATTRIBUTION,
        "index": summary.get("index"),
        "api": API,
        "transformation": (
            "MediaWiki wikitext → strip templates/links → split on ॥ N ॥ → "
            "IAST via scripts/translit.py. No translations invented. "
            "GRETIL not used as source."
        ),
        "expected_chapters": EXPECTED_CHAPTERS,
        "chapters": summary["chapters"],
        "verses": summary["verses"],
        "skandhas": summary["skandhas"],
        "pages": summary["pages"],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def update_work_json(summary: dict) -> None:
    path = CONTENT / "work.json"
    work = json.loads(path.read_text(encoding="utf-8"))
    meta = dict(work.get("metadata") or {})
    complete = summary["chapters"] == EXPECTED_CHAPTERS
    meta["total_cantos"] = 12
    meta["traditional_chapter_inventory"] = EXPECTED_CHAPTERS
    meta["imported_chapter_count"] = summary["chapters"]
    meta["imported_verse_count"] = summary["verses"]
    meta["complete"] = complete
    meta["retrieved"] = summary["retrieved"]
    meta["source_license"] = LICENSE
    if complete:
        meta.pop("pilot_scope", None)
        meta.pop("source_blocker", None)
        meta["translation_scope"] = "1.1.1–1.1.10"
        work["description"] = (
            "The Bhāgavata Purāṇa (Śrīmad Bhāgavatam) is one of the eighteen "
            "Mahāpurāṇas, traditionally attributed to Vyāsa and narrated by Śuka "
            "to King Parīkṣit, as retold by Sūta to the sages at Naimiṣāraṇya. "
            f"This build ships the complete sa.wikisource.org mūla: 12 skandhas, "
            f"{summary['chapters']} adhyāyas, {summary['verses']} numbered verses "
            f"parsed from that edition on {summary['retrieved'][:10]} (CC BY-SA 4.0). "
            "Traditional ~18,000 is an approximation, not an import target. "
            "English and Malayalam translations remain original Dharma Library "
            "drafts on 1.1.1–1.1.10 only; other verses have no invented translation. "
            "GRETIL was collated as a scholarly witness and is not shipped."
        )
        for e in work.get("editions", []):
            if e.get("slug") == "sb-mula-deva":
                e["description"] = (
                    "The Sanskrit text in Devanagari. Electronic witness: "
                    f"sa.wikisource.org (CC BY-SA 4.0), {summary['verses']} verses "
                    f"in {summary['chapters']} chapters."
                )
        for s in work.get("sources", []):
            if s.get("slug") == "sa-wikisource-bhagavata":
                s["notes"] = (
                    "Electronic Sanskrit mūla of the vulgate Bhāgavata Purāṇa. "
                    f"Licence: CC BY-SA 4.0 (Wikimedia). Retrieved {summary['retrieved']}. "
                    f"Imported {summary['chapters']} chapters / {summary['verses']} verses. "
                    "Attribution required."
                )
    work["metadata"] = meta
    path.write_text(json.dumps(work, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_source_md(summary: dict) -> None:
    complete = summary["chapters"] == EXPECTED_CHAPTERS
    sk_rows = "\n".join(
        f"| {sk} | {info['chapters']} | {info['verses']} |"
        for sk, info in sorted(summary["skandhas"].items(), key=lambda kv: int(kv[0]))
    )
    if complete:
        body = f"""# Bhāgavata Purāṇa — what is in this folder

**Shipped scope:** complete Śrīmad Bhāgavata Purāṇa mūla from
[sa.wikisource.org](https://sa.wikisource.org/wiki/श्रीमद्भागवतपुराणम्)
({LICENSE.replace("-", " ")}).

| Axis | This ingest |
|---|---|
| Retrieved | {summary["retrieved"]} |
| Licence | [{LICENSE}]({LICENSE_URL}) |
| Attribution | {ATTRIBUTION} |
| Skandhas | 12 |
| Adhyāyas parsed | {summary["chapters"]} (expected {EXPECTED_CHAPTERS}) |
| Numbered verses parsed | **{summary["verses"]}** (this edition; not a traditional 18,000 target) |
| Translations | original Dharma Library drafts on **1.1.1–1.1.10** only; nothing invented for the rest |
| GRETIL | collation/validation only; **not shipped** |

| Skandha | Chapters | Verses |
|---|---|---|
{sk_rows}

Transformation: MediaWiki wikitext → strip templates/links → split on `॥ N ॥` →
IAST via `scripts/translit.py`. Per-page `pageid` / `revid` / `sha1` are in
`WIKISOURCE_MANIFEST.json` and each chapter's `verses.json` `_source` block.

Gita Press numbering was used only as a collation witness. Do not drop the
BY-SA attribution when redistributing this e-text.
"""
    else:
        body = f"""# Bhāgavata Purāṇa — what is in this folder

**Shipped scope:** incomplete ingest ({summary["chapters"]} chapters /
{summary["verses"]} verses). This is **not** a complete Śrīmad Bhāgavata.

See `docs/bhagavata-source-research.md`.
"""
    (CONTENT / "SOURCE.md").write_text(body, encoding="utf-8")


def main() -> int:
    try:
        sys.stdout.reconfigure(line_buffering=True)
        sys.stderr.reconfigure(line_buffering=True)
    except Exception:
        pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--delay", type=float, default=0.4, help="seconds between API batches (be polite)")
    ap.add_argument("--batch-size", type=int, default=10, help="titles per MediaWiki query")
    ap.add_argument("--only-skandha", type=int, default=None)
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
        print(f"== Bhāgavata ingest from {ORIGIN} ({EXPECTED_CHAPTERS} chapters expected)", flush=True)
        print("   GRETIL will not be written. Translations will not be invented.", flush=True)
        probe_api()
        summary = ingest_all(
            dry_run=a.dry_run,
            delay=a.delay,
            batch_size=max(1, a.batch_size),
            only_skandha=a.only_skandha,
        )
        print("== done", json.dumps({k: summary[k] for k in ("chapters", "verses", "skandhas", "retrieved", "license")}, ensure_ascii=False))
        print(f"   actual verse count from this edition: {summary['verses']}")
        if not a.dry_run and a.only_skandha is None:
            write_manifest(summary)
            update_work_json(summary)
            write_source_md(summary)
        return 0
    except SourceBlocker as e:
        print(str(e), file=sys.stderr, flush=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

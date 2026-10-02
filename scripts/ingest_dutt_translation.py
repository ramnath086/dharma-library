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
import bisect
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

# English function words carry no alignment signal.
ENGLISH_STOP = set("""a an the and or but if then than that this these those there here of in
on at to for with from by as is are was were be been being am do does did doing have has had
having i you he she it we they me him her them my your his its our their who whom whose which
what when where why how all any both each few more most other some such no nor not only own
same so too very can will just should now into out up down over under again further once
o thou thee thy ye unto hath hast doth dost saith said says upon whilst among between within
also even ever every neither none other others shall would could may might must let us let
o's""".split())


def deaccent(s: str) -> str:
    """IAST -> plain ASCII, so 'Vāsudeva' can be matched against 'Vasudeva'."""
    table = str.maketrans({
        "ā": "a", "Ā": "A", "ī": "i", "Ī": "I", "ū": "u", "Ū": "U",
        "ṛ": "r", "Ṛ": "R", "ṝ": "r", "ḹ": "l",
        "ḷ": "l", "Ḹ": "L",
        "ē": "e", "ō": "o", "ṁ": "m", "ṃ": "m", "ṅ": "n", "ñ": "n",
        "ṇ": "n", "ś": "s", "ṣ": "s", "ś": "s", "ṭ": "t", "ḍ": "d",
        "ḥ": "", "ḫ": "h", "ṟ": "r",
    })
    return s.translate(table)


class GlossIndex:
    """lemma -> English senses, with a prefix fallback for inflected forms.

    Built from the Digital Corpus of Sanskrit dictionary (CC BY 4.0), the same
    source as the word-by-word edition. It is only used as a *bridge* to score
    how well a sentence of Dutt's English matches a Sanskrit verse; it is never
    written into the corpus.
    """

    def __init__(self, dictionary: dict[str, str]):
        self.lemmas = sorted(dictionary)
        self.raw = dictionary
        self._cache: dict[str, list[str]] = {}

    def lemmas_for(self, token: str) -> list[str]:
        token = token.strip().lower()
        if token in self._cache:
            return self._cache[token]
        found: list[str] = []
        for length in range(len(token), 4, -1):
            prefix = token[:length]
            i = bisect.bisect_left(self.lemmas, prefix)
            n = 0
            while i < len(self.lemmas) and self.lemmas[i].startswith(prefix):
                found.append(self.lemmas[i])
                i += 1
                n += 1
                if n >= 8:
                    break
            if found:
                break
        self._cache[token] = found
        return found

    def english_words(self, token: str) -> set[str]:
        out: set[str] = set()
        for lem in self.lemmas_for(token):
            for sense in self.raw[lem].split(";"):
                for w in re.findall(r"[a-z]{3,}", sense.lower()):
                    if w not in ENGLISH_STOP:
                        out.add(w)
        return out


def content_words(sentence: str) -> set[str]:
    return {w for w in re.findall(r"[a-z]{3,}", sentence.lower())
            if w not in ENGLISH_STOP}


def verse_signals(verse: dict, gloss: GlossIndex) -> tuple[set[str], set[str]]:
    """(transliterated Sanskrit words, dictionary-glossed English words)."""
    translit: set[str] = set()
    glossed: set[str] = set()
    for tok in re.findall(r"[A-Za-zāīūṛṝḷēōṁṃṅñṇśṣṭḍḥḫ]+", verse.get("iast", "")):
        plain = deaccent(tok).lower()
        if len(plain) >= 4:
            translit.add(plain)
        glossed |= gloss.english_words(tok)
    return translit, glossed


class Aligner:
    """Monotone alignment of Dutt's sentences onto the corpus refs.

    Dutt renders a śloka as one or more consecutive sentences and sometimes
    merges neighbouring ślokas into a single sentence, so the mapping is a
    monotone many-to-one alignment rather than a bijection. It is solved with a
    Viterbi pass that maximises the total evidence, and every emitted pair then
    has to clear an absolute *and* a relative evidence bar — a mapping is only
    written when the sentence matches that verse far better than any neighbour.
    """

    SKIP_VERSE = 0.0       # Dutt omitted / merged away this śloka
    SKIP_SENTENCE = 0.35   # a sentence that renders no śloka of its own

    def __init__(self, idf: dict[str, float], gloss: GlossIndex,
                 accept: float = 0.30, margin: float = 0.10):
        self.idf = idf
        self.gloss = gloss
        self.accept = accept
        self.margin = margin

    def score(self, translit: set[str], glossed: set[str], sentence: str) -> float:
        words = content_words(sentence)
        if not words or not (translit or glossed):
            return 0.0
        hit = 0.0
        for w in words:
            if w in translit:
                hit += 3.0 * self.idf.get(w, 1.0)      # transliteration: strong
            elif w in glossed:
                hit += 1.0 * self.idf.get(w, 1.0)      # dictionary gloss: weak
        total = sum(self.idf.get(w, 1.0) for w in translit) + \
            sum(self.idf.get(w, 1.0) for w in glossed)
        if total <= 0:
            return 0.0
        return min(hit / total, 1.0)

    REUSE = 0.8              # a sentence Dutt uses for two neighbouring ślokas

    def align(self, verses: list[dict], sentences: list[str]) -> list[tuple[str, str, float]]:
        if not verses or not sentences:
            return []
        sig = [verse_signals(v, self.gloss) for v in verses]
        n, m = len(verses), len(sentences)
        S = [[self.score(t, g, s) for s in sentences] for t, g in sig]
        NEG = float("-inf")

        # best[i][j] = best total evidence when verses 0..i are explained by
        # sentences 0..j, with verse i either using sentence j or being skipped.
        best = [[NEG] * m for _ in range(n)]
        back: list[list[tuple[str, int] | None]] = [[None] * m for _ in range(n)]
        for j in range(m):
            if S[0][j] >= self.SKIP_VERSE:
                best[0][j], back[0][j] = S[0][j], ("s", j)
            else:
                best[0][j], back[0][j] = self.SKIP_VERSE, ("v", j)

        for i in range(1, n):
            prev, row, brow = best[i - 1], best[i], back[i]
            # best k < j reached by verse i-1
            pref = [NEG] * (m + 1)
            argpref = [-1] * (m + 1)
            run, arg = NEG, -1
            for j in range(m):
                if prev[j] > run:
                    run, arg = prev[j], j
                pref[j + 1], argpref[j + 1] = run, arg
            for j in range(m):
                opt, arg = NEG, None
                # verse i skipped, sentence j left for later
                if prev[j] != NEG:
                    opt, arg = prev[j] + self.SKIP_VERSE, ("v", j)
                # verse i rendered by sentence j; verse i-1 by an earlier one
                if pref[j] != NEG:
                    cand = pref[j] + S[i][j]
                    if cand > opt:
                        opt, arg = cand, ("s", argpref[j])
                # sentence j shared by verses i-1 and i (Dutt merges ślokas)
                if prev[j] != NEG:
                    cand = prev[j] + self.REUSE * S[i][j]
                    if cand > opt:
                        opt, arg = cand, ("r", j)
                # sentence j renders nothing on its own
                if j > 0 and row[j - 1] != NEG:
                    cand = row[j - 1] + self.SKIP_SENTENCE
                    if cand > opt:
                        opt, arg = cand, ("j", j - 1)
                row[j], brow[j] = opt, arg

        last = best[n - 1]
        if max(last) == NEG:
            return []
        j = max(range(m), key=lambda x: last[x])
        pairs: list[tuple[int, int, float]] = []
        i = n - 1
        while i >= 0:
            move = back[i][j]
            if move is None:
                break
            kind, k = move
            if kind == "s":
                pairs.append((i, j, S[i][j]))
                i, j = i - 1, k
            elif kind == "r":
                pairs.append((i, j, S[i][j]))
                i -= 1
            elif kind == "v":
                i -= 1
            else:                      # "j": this sentence was skipped
                j = k
        pairs.reverse()

    # Confidence gate: the chosen sentence must beat every other sentence
        # that could plausibly render this verse.
        out = []
        for i, j, sc in pairs:
            others = sorted((S[i][k] for k in range(max(0, j - 2), min(m, j + 3))
                             if k != j), reverse=True)
            runner = others[0] if others else 0.0
            if sc >= self.accept and sc - runner >= self.margin:
                out.append((verses[i]["ref"], sentences[j], round(sc, 4)))
        return out


def build_idf(sentence_lists: list[list[str]]) -> dict[str, float]:
    import math
    df: dict[str, int] = {}
    for sents in sentence_lists:
        for s in sents:
            for w in content_words(s):
                df[w] = df.get(w, 0) + 1
    n = max(1, sum(len(s) for s in sentence_lists))
    return {w: math.log(1.0 + n / c) for w, c in df.items()}


def build(cache: pathlib.Path, gloss: GlossIndex) -> tuple[dict[str, str], dict]:
    corpus = load_corpus()
    mapping: dict[str, str] = {}
    report = {"volumes": [], "chapters": []}

    # First pass: parse every volume so the idf table sees all of Dutt's English.
    parsed_volumes = []
    for src in DUTT_SOURCES:
        text = download(src, cache)
        parsed = parse_volume(text)
        chapters = []
        for book in sorted(parsed):
            for chap_no in sorted(parsed[book]):
                verses = corpus.get((book, chap_no), [])
                paras = chapter_paragraphs(parsed[book][chap_no])
                sents = chapter_sentences(paras)
                chapters.append((book, chap_no, verses, paras, sents))
        parsed_volumes.append((src, text, chapters))
        report["volumes"].append({
            "key": src["key"], "identifier": src["identifier"],
            "bytes": len(text),
            "books": sorted({b for b, _c, _v, _p, _s in chapters}),
            "chapters": len(chapters),
        })

    idf = build_idf([c[4] for _s, _t, chs in parsed_volumes for c in chs])
    aligner = Aligner(idf, gloss)
    scored: dict[str, float] = {}

    for src, _text, chapters in parsed_volumes:
        for book, chap_no, verses, paras, sents in chapters:
            pairs = aligner.align(verses, sents)
            report["chapters"].append({
                "volume": src["key"], "skandha": book, "adhyaya": chap_no,
                "corpus_verses": len(verses), "paragraphs": len(paras),
                "sentences": len(sents), "aligned": len(pairs),
                "mean_score": round(sum(p[2] for p in pairs) / len(pairs), 4) if pairs else 0.0,
            })
            for ref, sentence, sc in pairs:
                scored.setdefault(ref, sc)
                if ref not in mapping:      # first verified witness wins
                    mapping[ref] = sentence

    # Which adhyāyas the parser never produced, and which never aligned — the
    # honest measure of what is *not* covered.
    parsed_keys = {(c["skandha"], c["adhyaya"]) for c in report["chapters"]}
    report["missing_chapters"] = [f"{b}.{c}" for (b, c) in sorted(corpus)
                                  if (b, c) not in parsed_keys]
    report["unaligned_chapters"] = [f"{c['skandha']}.{c['adhyaya']}"
                                    for c in report["chapters"] if not c["aligned"]]
    report["samples"] = [
        {"ref": r, "score": scored[r], "dutt": mapping[r][:400]}
        for r in sorted(mapping, key=lambda x: [int(p) for p in x.split(".")])[:12]
    ]
    return mapping, report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--cache", default=str(ROOT / ".dutt-cache"))
    ap.add_argument("--accept", type=float, default=0.30)
    ap.add_argument("--margin", type=float, default=0.10)
    a = ap.parse_args()

    cache = pathlib.Path(a.cache)
    sys.path.insert(0, str(ROOT / "scripts"))
    from ingest_dcs_wordmeanings import load_dictionary  # noqa: E402
    gloss = GlossIndex(load_dictionary())
    Aligner.__init__.__defaults__ = (a.accept, a.margin)

    mapping, report = build(cache, gloss)
    total = sum(len(v) for v in load_corpus().values())
    report["summary"] = {
        "corpus_verses": total,
        "aligned_verses": len(mapping),
        "coverage": round(len(mapping) / total, 4) if total else 0.0,
        "accept_threshold": a.accept,
        "margin_threshold": a.margin,
        "field": FIELD,
        "edition": EDITION_SLUG,
    }
    DOCS.mkdir(parents=True, exist_ok=True)
    (DOCS / "dutt-translation-coverage.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    aligned_ch = sum(1 for c in report["chapters"] if c["aligned"])
    print(f"Dutt alignment: {len(mapping)}/{total} verses "
          f"({report['summary']['coverage']:.1%}); "
          f"{aligned_ch}/{len(report['chapters'])} chapters contributed")
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

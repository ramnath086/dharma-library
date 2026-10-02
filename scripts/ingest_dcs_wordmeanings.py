#!/usr/bin/env python3
"""Ingest word-by-word meanings for the Bhāgavata corpus from the Digital
Corpus of Sanskrit (DCS).

Source
------
Oliver Hellwig, *Digital Corpus of Sanskrit* (DCS), 2010–2026,
https://www.sanskrit-linguistics.org/dcs/ — data dump
https://github.com/OliverHellwig/sanskrit, directory
``dcs/data/conllu/``.

* Licence: **CC BY 4.0** (see ``dcs/data/readme.md``). That is an open licence
  with commercial use and derivatives allowed, so it clears the project's
  rights policy once attribution is carried (see ``work.json``).
* The CoNLL-U dump contains the Bhāgavatapurāṇa sandhi-split, lemmatised and
  POS-tagged, one file per adhyāya, one block per *pāda*. ``# sent_counter`` is
  the verse number inside the adhyāya and ``# sent_subcounter`` the pāda, so
  the dump is **verse-aligned** to the numbering used by this corpus.
* ``lookup/dictionary.csv`` gives, per lemma id, the lemma and its English
  dictionary senses. Those senses are the word-by-word meanings shipped here.

What is *not* done
------------------
DCS does not cover every adhyāya of the Bhāgavata (as of this pass: 119 of
335). Chapters it does not cover keep whatever they already have; nothing is
invented or inferred for them. The senses are dictionary senses, not
contextual translations — the edition title and description say so.

    python3 scripts/ingest_dcs_wordmeanings.py --report
    python3 scripts/ingest_dcs_wordmeanings.py --write
"""
from __future__ import annotations

import argparse
import base64
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content" / "bhagavata-purana"
DOCS = ROOT / "docs"

FIELD = "wm_dcs"               # verse JSON field that carries the DCS glosses
EDITION_SLUG = "sb-wm-dcs-en"

REPO = "OliverHellwig/sanskrit"
API = "https://api.github.com"
TEXT_DIR = "dcs/data/conllu/files/Bh\u0101gavatapur\u0101\u1e47a"
DICTIONARY = "dcs/data/conllu/lookup/dictionary.csv"

MAX_SENSES = 3                 # dictionary senses kept per word
MAX_GLOSS_CHARS = 140          # hard cap so a Monier-Williams essay stays short

# DCS merges Monier-Williams (English) with a German dictionary, so a small
# number of senses come back in German ("gleicher", "Erde", ...). They are
# dropped: this is an English word-by-word edition. Only unambiguous German
# words are listed — English look-alikes such as "die" (a die), "in", "an",
# "am", "was", "see", "heart" and "name" are deliberately absent.
GERMAN_MARKERS = {
    "gleicher", "gleiche", "gleichen", "Erde", "etwas", "jemand", "niemand",
    "und", "oder", "aber", "auch", "noch", "schon", "sehr", "mehr", "groß",
    "gross", "klein", "gut", "böse", "boese", "Wasser", "Feuer", "Luft",
    "Himmel", "Welt", "Zeit", "Wort", "Sprache", "Körper", "Koerper", "Geist",
    "Seele", "Blut", "Leben", "Tod", "Liebe", "Hass", "Angst", "Freude",
    "Schmerz", "Wahrheit", "Lüge", "Luege", "Unrecht", "Tugend", "Laster",
    "König", "Koenig", "Königin", "Koenigin", "Fürst", "Fuerst", "Weib",
    "Sohn", "Tochter", "Mutter", "Bruder", "Schwester", "Feind", "Gast",
    "Opfer", "Gebet", "Lied", "Tanz", "Spiel", "Arbeit", "Ruhe", "Schlaf",
    "Traum", "Essen", "Trinken", "Tier", "Pflanze", "Baum", "Blume", "Frucht",
    "Stein", "Berg", "Tal", "Fluss", "Meer", "Ufer", "Stadt", "Dorf", "Haus",
    "Hof", "Feld", "Wald", "Garten", "Hain", "Herr", "Frau", "Kind", "Haar",
    "Hand", "Fuss", "Auge", "Ohr", "Mund", "Nase", "Herz", "wo", "wann",
    "warum", "weil", "damit", "ohne", "durch", "für", "fuer", "über",
    "ueber", "unter", "zwischen", "neben", "aus", "von", "nach", "bei",
    "mit", "auf", "im", "ins",
}

CONTROL_RE = re.compile(r"[\x00-\x1f\x7f-\x9f]")

CHAPTER_RE = re.compile(r"^##\s*chapter:\s*(.+?)\s*$")
COUNTER_RE = re.compile(r"^#\s*sent_counter\s*=\s*(\d+)\s*$")
WORDLINE_RE = re.compile(r"^(\d+)\t")


def gh(path: str) -> bytes:
    req = urllib.request.Request(
        API + path,
        headers={"Accept": "application/vnd.github.raw+json",
                 "User-Agent": "DharmaLibraryBot/1.0",
                 "X-GitHub-Api-Version": "2022-11-28"},
    )
    with urllib.request.urlopen(req, timeout=300) as r:  # noqa: S310 (fixed https host)
        return r.read()


def gh_json(path: str):
    return json.loads(gh(path).decode("utf-8"))


# ------------------------------------------------------------------- corpus

def load_corpus() -> dict[tuple[int, int], list[dict]]:
    corpus: dict[tuple[int, int], list[dict]] = {}
    for canto in sorted((p for p in CONTENT.iterdir() if p.is_dir() and p.name.isdigit()),
                        key=lambda p: int(p.name)):
        for chap in sorted((p for p in canto.iterdir() if p.is_dir() and p.name.isdigit()),
                           key=lambda p: int(p.name)):
            f = chap / "verses.json"
            if f.exists():
                corpus[(int(canto.name), int(chap.name))] = json.loads(
                    f.read_text(encoding="utf-8"))["verses"]
    return corpus


def refs_by_number(verses: list[dict]) -> dict[int, str]:
    out: dict[int, str] = {}
    for v in verses:
        tail = v["ref"].rsplit(".", 1)[-1]
        m = re.match(r"^(\d+)", tail)
        if m:
            out.setdefault(int(m.group(1)), v["ref"])
    return out


# ------------------------------------------------------------------ parsing

def load_dictionary() -> dict[str, tuple[str, str]]:
    """lemma id -> (lemma, meanings)"""
    raw = gh(f"/repos/{REPO}/git/blobs/" + dictionary_sha()).decode("utf-8")
    out: dict[str, tuple[str, str]] = {}
    for line in raw.split("\n")[1:]:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        out[parts[0]] = (parts[1], parts[4])
    return out


_DICT_SHA: str | None = None


def dictionary_sha() -> str:
    global _DICT_SHA
    if _DICT_SHA is None:
        tree = gh_json(f"/repos/{REPO}/git/trees/master?recursive=1")
        for t in tree.get("tree", []):
            if t.get("path") == DICTIONARY:
                _DICT_SHA = t["sha"]
                break
        if _DICT_SHA is None:
            raise SystemExit(f"{DICTIONARY} not found in {REPO}")
    return _DICT_SHA


def bhagavata_files() -> list[tuple[str, str]]:
    """[(path, blob sha)] for every Bhāgavatapurāṇa CoNLL-U file."""
    tree = gh_json(f"/repos/{REPO}/git/trees/master?recursive=1")
    out = []
    for t in tree.get("tree", []):
        p = t.get("path", "")
        if t.get("type") == "blob" and p.startswith(TEXT_DIR) and p.endswith(".conllu"):
            out.append((p, t["sha"]))
    if not out:
        raise SystemExit(f"no CoNLL-U files under {TEXT_DIR}")
    return out


def parse_conllu(raw: str) -> dict[tuple[int, int, int], list[tuple[str, str | None]]]:
    """Return {(canto, chapter, verse): [(form, lemma_id), ...]}.

    ``# sent_counter`` is the verse number inside the adhyāya and
    ``# sent_subcounter`` the pāda, so all blocks sharing a sent_counter belong
    to one verse and their words are concatenated in reading order.
    """
    verses: dict[tuple[int, int, int], list[tuple[str, str | None]]] = {}
    cur: list[tuple[str, str | None]] | None = None
    canto = chapter = verse = None
    for line in raw.split("\n"):
        if line.startswith("##"):
            m = CHAPTER_RE.match(line)
            if m:
                parts = [p.strip() for p in m.group(1).split(",")]
                if len(parts) >= 3:
                    canto, chapter = int(parts[1]), int(parts[2])
                    cur = None
            continue
        if line.startswith("#"):
            m = COUNTER_RE.match(line)
            if m and canto and chapter:
                verse = int(m.group(1))
                cur = verses.setdefault((canto, chapter, verse), [])
            continue
        if not line.strip() or cur is None:
            continue
        m = WORDLINE_RE.match(line)
        if not m:
            continue                     # multiword-token header line
        fields = line.split("\t")
        if len(fields) < 10:
            continue
        misc = fields[9]
        lemma_id = None
        unsandhied = None
        for kv in misc.split("|"):
            if kv.startswith("LemmaId="):
                lemma_id = kv.split("=", 1)[1]
            elif kv.startswith("Unsandhied="):
                unsandhied = kv.split("=", 1)[1]
        form = (unsandhied or "").strip()
        if form in ("", "_"):
            form = fields[1]
        cur.append((form, lemma_id))
    return verses


def _sense_is_german(sense: str) -> bool:
    toks = re.findall(r"[A-Za-zÄÖÜäöüß]+", sense)
    if not toks:
        return False
    return any(t in GERMAN_MARKERS for t in toks)


def gloss(lemma_id: str | None, dictionary: dict[str, tuple[str, str]]) -> str:
    if not lemma_id or lemma_id not in dictionary:
        return ""
    _lemma, meanings = dictionary[lemma_id]
    senses = [s.strip() for s in meanings.split(";") if s.strip()]
    senses = [s for s in senses if not _sense_is_german(s)]
    out = "; ".join(senses[:MAX_SENSES])
    out = CONTROL_RE.sub(" ", out)
    out = re.sub(r"\s+", " ", out).strip(" ;,")
    if len(out) > MAX_GLOSS_CHARS:
        out = out[:MAX_GLOSS_CHARS].rstrip(" ;,") + "\u2026"
    return out


# --------------------------------------------------------------------- main

def build() -> tuple[dict[str, list[dict]], dict]:
    dictionary = load_dictionary()
    corpus = load_corpus()
    refmap = {k: refs_by_number(v) for k, v in corpus.items()}

    mapping: dict[str, list[dict]] = {}
    report = {"chapters": [], "lemmas": len(dictionary)}
    seen_chapters: set[tuple[int, int]] = set()

    for path, sha in bhagavata_files():
        raw = gh(f"/repos/{REPO}/git/blobs/{sha}").decode("utf-8")
        for (canto, chapter, verse), words_raw in parse_conllu(raw).items():
            key = (canto, chapter)
            ref = refmap.get(key, {}).get(verse)
            if not ref:
                continue
            seen_chapters.add(key)
            words = []
            for form, lemma_id in words_raw:
                g = gloss(lemma_id, dictionary)
                if not g:
                    continue
                words.append({"word": form, "meaning": g})
            if words:
                mapping[ref] = words
            report["chapters"].append({
                "ref": ref, "canto": canto, "chapter": chapter,
                "verse": verse, "words": len(words), "file": path.rsplit("/", 1)[-1],
            })

    total = sum(len(v) for v in corpus.values())
    report["summary"] = {
        "corpus_verses": total,
        "verses_with_glosses": len(mapping),
        "coverage": round(len(mapping) / total, 4) if total else 0.0,
        "words": sum(len(w) for w in mapping.values()),
        "chapters_covered": len(seen_chapters),
        "field": FIELD,
        "edition": EDITION_SLUG,
        "source": "Digital Corpus of Sanskrit (CC BY 4.0), github.com/OliverHellwig/sanskrit",
    }
    return mapping, report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    mapping, report = build()
    DOCS.mkdir(parents=True, exist_ok=True)
    (DOCS / "dcs-word-meanings-coverage.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    s = report["summary"]
    print(f"DCS word-by-word: {s['verses_with_glosses']}/{s['corpus_verses']} verses "
          f"({s['coverage']:.1%}), {s['words']} glossed words, "
          f"{report['lemmas']} dictionary lemmas")

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

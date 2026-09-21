"""Guards on shipped scripture JSON: counts, rights honesty, no silent expansion.

The Bhāgavata folder is a *pilot* until generate_bhagavata_corpus.py has been
run successfully. These tests lock that fact so a partial dump cannot be
mistaken for a complete Purāṇa. The Gītā must stay 18×700.
"""
from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
BHAGAVATA = ROOT / "content" / "bhagavata-purana"
GITA = ROOT / "content" / "bhagavad-gita"


def _load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _verse_files(work_dir: pathlib.Path) -> list[pathlib.Path]:
    return sorted(work_dir.glob("**/verses.json"))


class GitaUnchanged(unittest.TestCase):
    def test_eighteen_chapters_seven_hundred_verses(self):
        files = _verse_files(GITA)
        self.assertEqual(len(files), 18)
        total = 0
        for vf in files:
            data = _load(vf)
            verses = data["verses"]
            total += len(verses)
            refs = [v["ref"] for v in verses]
            self.assertEqual(len(refs), len(set(refs)), f"duplicate ref in {vf}")
            for i, v in enumerate(verses, 1):
                self.assertEqual(v["ordinal"], i, f"non-dense ordinal in {vf} at {v.get('ref')}")
                self.assertTrue(v["deva"].strip(), v["ref"])
                self.assertTrue(v["iast"].strip(), v["ref"])
        self.assertEqual(total, 700)

    def test_gita_work_json_still_declares_700(self):
        w = _load(GITA / "work.json")
        self.assertEqual(w["slug"], "bhagavad-gita")
        self.assertEqual(w["metadata"]["total_verses"], 700)
        self.assertEqual(w["metadata"]["total_chapters"], 18)


class BhagavataPilot(unittest.TestCase):
    def test_only_the_ten_verse_pilot_is_shipped(self):
        files = _verse_files(BHAGAVATA)
        self.assertEqual(files, [BHAGAVATA / "1" / "1" / "verses.json"])
        data = _load(files[0])
        refs = [v["ref"] for v in data["verses"]]
        self.assertEqual(refs, [f"1.1.{i}" for i in range(1, 11)])
        for v in data["verses"]:
            self.assertTrue(v["deva"].strip())
            self.assertTrue(v["iast"].strip())
            self.assertTrue(v["en"].strip())
            self.assertTrue(v["ml"].strip())

    def test_work_json_declares_pilot_scope_not_a_complete_corpus(self):
        w = _load(BHAGAVATA / "work.json")
        self.assertEqual(w["slug"], "bhagavata-purana")
        self.assertEqual(w["metadata"].get("pilot_scope"), "1.1.1–1.1.10")
        self.assertEqual(w["metadata"].get("imported_verse_count"), 10)
        self.assertEqual(w["metadata"].get("imported_chapter_count"), 1)
        self.assertFalse(w["metadata"].get("complete"), "must not claim a complete Bhāgavata")

    def test_gretil_is_collation_only_not_a_commercial_pd_grant(self):
        w = _load(BHAGAVATA / "work.json")
        gretil = [s for s in w["sources"] if "gretil" in s["slug"].lower()]
        self.assertTrue(gretil, "keep GRETIL listed as a scholarly witness")
        notes = " ".join(s.get("notes", "") for s in gretil).lower()
        self.assertRegex(notes, r"collation|scholarly")
        self.assertRegex(notes, r"not redistribut|non-commercial|not shipped|not used as")
        for e in w["editions"]:
            if e.get("is_machine"):
                continue
            self.assertNotIn(
                "gretil",
                (e.get("source") or "").lower(),
                f"edition {e['slug']} must not ship GRETIL as its source",
            )
        for r in w["rights"]:
            src = (r.get("source") or "").lower()
            if "gretil" in src:
                self.fail("rights row must not key commercial clearance off GRETIL")

    def test_wikisource_is_the_named_electronic_witness(self):
        w = _load(BHAGAVATA / "work.json")
        wiki = [s for s in w["sources"] if "wikisource" in s["slug"].lower() or "wikisource" in (s.get("url") or "")]
        self.assertTrue(wiki)
        self.assertTrue(any("CC BY-SA" in (s.get("notes") or "") or "CC-BY-SA" in (s.get("notes") or "") for s in wiki))
        mula = [e for e in w["editions"] if e["kind"] == "base_text"]
        self.assertTrue(mula)
        self.assertTrue(any("wikisource" in (e.get("source") or "") for e in mula))

    def test_editorial_audio_cues_are_the_three_invocations_only(self):
        data = _load(BHAGAVATA / "1" / "1" / "verses.json")
        cued = [v["ref"] for v in data["verses"] if (v.get("metadata") or {}).get("audio", {}).get("important")]
        self.assertEqual(cued, ["1.1.1", "1.1.2", "1.1.3"])
        for v in data["verses"]:
            if v["ref"] in cued:
                self.assertEqual(v["kind"], "invocation")
                asset = v["metadata"]["audio"]["cue_asset"]
                self.assertTrue((ROOT / "app" / asset.replace("assets/", "assets/")).exists() or (ROOT / "app" / asset).exists() or (ROOT / "app" / "assets" / "audio" / "sloka_chime.wav").exists())


class RightsShape(unittest.TestCase):
    def test_every_edition_has_rights_and_source(self):
        for work in (BHAGAVATA, GITA):
            w = _load(work / "work.json")
            keys = {r["key"] for r in w["rights"]}
            for e in w["editions"]:
                self.assertIn(e["rights"], keys, e["slug"])
                self.assertTrue(e.get("source"), e["slug"])


if __name__ == "__main__":
    unittest.main()

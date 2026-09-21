"""Parser + rights-guard tests for the Bhāgavata importer.

These tests never hit the network. Fetching the complete Wikisource tree is
opt-in (`scripts/generate_bhagavata_corpus.py`) and must fail closed with
SOURCE BLOCKER when Wikimedia is unreachable — we do not invent verses.
"""
from __future__ import annotations

import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import generate_bhagavata_corpus as G  # noqa: E402


class InventoryTests(unittest.TestCase):
    def test_twelve_skandhas_sum_to_335(self):
        self.assertEqual(len(G.SKANDHA_CHAPTERS), 12)
        self.assertEqual(sum(G.SKANDHA_CHAPTERS.values()), 335)
        self.assertEqual(G.SKANDHA_CHAPTERS[10], 90)
        self.assertEqual(G.SKANDHA_CHAPTERS[12], 13)

    def test_canonical_title_uses_skandha_spelling_and_deva_digits(self):
        t = G.chapter_title(1, 4)
        self.assertIn("स्कन्धः", t)
        self.assertNotIn("स्कन्दः", t)
        self.assertIn("अध्यायः ४", t)

    def test_skandha_10_uses_purva_and_uttara_halves(self):
        purva = G.chapter_title(10, 1)
        mid = G.chapter_title(10, 49)
        uttara = G.chapter_title(10, 50)
        last = G.chapter_title(10, 90)
        self.assertEqual(purva, "श्रीमद्भागवतपुराणम्/स्कन्धः १०/पूर्वार्धः/अध्यायः १")
        self.assertEqual(mid, "श्रीमद्भागवतपुराणम्/स्कन्धः १०/पूर्वार्धः/अध्यायः ४९")
        self.assertEqual(uttara, "श्रीमद्भागवतपुराणम्/स्कन्धः १०/उत्तरार्धः/अध्यायः ५०")
        self.assertEqual(last, "श्रीमद्भागवतपुराणम्/स्कन्धः १०/उत्तरार्धः/अध्यायः ९०")
        self.assertNotIn("स्कन्दः", purva)


class ParserTests(unittest.TestCase):
    def setUp(self):
        self.wiki = (pathlib.Path(__file__).parent / "fixtures" / "bhagavata_1_1_sample.wiki").read_text(encoding="utf-8")

    def test_sample_extracts_dense_verses_with_speakers(self):
        verses = G.parse_wikitext(self.wiki, 1, 1)
        self.assertEqual([v["ref"] for v in verses], ["1.1.4", "1.1.5", "1.1.6"])
        self.assertEqual([v["ordinal"] for v in verses], [4, 5, 6])
        self.assertIn("ऋषयः", verses[0]["deva"])
        self.assertNotIn("īśayaḥ", verses[0]["iast"])
        self.assertIn("ṛṣayaḥ", verses[0]["iast"])
        self.assertIn("सूत", verses[0]["speaker"] or "")
        self.assertIn("ऋषय", verses[2]["speaker"] or "")
        # never invent a translation
        self.assertNotIn("en", verses[0])
        self.assertNotIn("ml", verses[0])

    def test_missing_verse_markers_are_a_blocker_not_silence(self):
        with self.assertRaises(G.SourceBlocker):
            G.parse_wikitext("no verses here at all", 1, 2)

    def test_non_dense_numbering_is_a_blocker(self):
        wiki = "foo ॥ १ ॥\nbar ॥ ३ ॥\n"
        with self.assertRaises(G.SourceBlocker):
            G.parse_wikitext(wiki, 2, 1)

    def test_single_danda_after_number_still_splits(self):
        wiki = "aaa ॥ १ ॥\nbbb ॥ २ ।\n"
        verses = G.parse_wikitext(wiki, 2, 8)
        self.assertEqual([v["ordinal"] for v in verses], [1, 2])
        self.assertIn("॥ १ ॥", verses[0]["deva"])
        self.assertIn("॥ २ ॥", verses[1]["deva"])

    def test_wikisource_1_1_mixed_danda_and_two_line_colophon(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_1_1_wikisource_head.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 1, 1)
        self.assertEqual([v["ordinal"] for v in verses], [1, 2, 3, 4])
        self.assertIn("जन्माद्यस्य", verses[0]["deva"])
        self.assertIn("ऋषयः", verses[3]["deva"])
        self.assertNotIn("प्रथमोऽध्यायः", " ".join(v["deva"] for v in verses))

    def test_leading_zero_deva_number(self):
        wiki = "aaa ॥ ८ ॥\nbbb । ०९ ॥\n"
        verses = G.parse_wikitext(wiki, 1, 1)
        self.assertEqual([v["ordinal"] for v in verses], [8, 9])


class MergePilotTests(unittest.TestCase):
    def test_keeps_existing_translations_on_overlap_only(self):
        existing = ROOT / "content" / "bhagavata-purana" / "1" / "1" / "verses.json"
        incoming = [
            {"ref": "1.1.4", "ordinal": 4, "kind": "verse", "speaker": "ignored", "deva": "X", "iast": "x"},
            {"ref": "1.1.11", "ordinal": 11, "kind": "verse", "speaker": None, "deva": "Y", "iast": "y"},
        ]
        merged = G.merge_pilot_translations(incoming, existing)
        self.assertTrue(merged[0].get("en"))
        self.assertTrue(merged[0].get("ml"))
        self.assertEqual(merged[0]["speaker"], None)  # original 1.1.4 has no speaker slug
        self.assertNotIn("en", merged[1])


if __name__ == "__main__":
    unittest.main()

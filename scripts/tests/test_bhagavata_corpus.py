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
        self.assertEqual([v["ordinal"] for v in verses], [1, 2, 3])
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

    def test_gap_in_printed_numbers_is_kept_without_inventing(self):
        wiki = "foo ॥ १ ॥\nbar ॥ ३ ॥\n"
        verses = G.parse_wikitext(wiki, 2, 1)
        self.assertEqual([v["ref"] for v in verses], ["2.1.1", "2.1.3"])
        self.assertEqual([v["ordinal"] for v in verses], [1, 2])
        self.assertIn("foo", verses[0]["deva"])
        self.assertIn("bar", verses[1]["deva"])
        self.assertIn("skipped", verses[1]["metadata"]["numbering_note"])

    def test_printed_number_going_backwards_is_a_blocker(self):
        wiki = "foo ॥ ५ ॥\nbar ॥ २ ॥\n"
        with self.assertRaises(G.SourceBlocker):
            G.parse_wikitext(wiki, 1, 2)

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
        self.assertEqual([v["ref"] for v in verses], ["1.1.8", "1.1.9"])
        self.assertEqual([v["ordinal"] for v in verses], [1, 2])

    def test_unnumbered_opener_before_verse_2_is_kept_as_verse_1(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_1_7_unnumbered_opener.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 1, 7)
        self.assertEqual([v["ordinal"] for v in verses], [1, 2, 3])
        self.assertIn("निर्गते नारदे", verses[0]["deva"])
        self.assertIn("शम्याप्रास", verses[1]["deva"])
        self.assertNotIn("निर्गते", verses[1]["deva"])
        self.assertNotIn("शम्याप्रास", verses[0]["deva"])
        self.assertEqual(verses[0]["speaker"], "शौनक")
        self.assertEqual(verses[1]["speaker"], "सूत")
        self.assertIn("numbering_note", verses[0]["metadata"])

    def test_wikisource_1_13_gap_and_duplicate_printed_numbers(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_1_13_gap_and_dup.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 1, 13)
        self.assertEqual(
            [v["ref"] for v in verses],
            ["1.13.35", "1.13.37", "1.13.40", "1.13.40b", "1.13.41"],
        )
        self.assertEqual([v["ordinal"] for v in verses], [1, 2, 3, 4, 5])
        self.assertIn("नाहं वेद", verses[1]["deva"])
        self.assertIn("नारदो मुनिसत्तमः", verses[2]["deva"])
        self.assertIn("मा कञ्चन", verses[3]["deva"])
        self.assertNotIn("मा कञ्चन", verses[2]["deva"])
        self.assertIn("skipped", verses[1]["metadata"]["numbering_note"])
        self.assertIn("40b", verses[3]["metadata"]["numbering_note"])

    def test_split_tens_and_units_are_one_verse_number(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_4_2_split_digits.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 4, 2)
        self.assertEqual([v["ref"] for v in verses], ["4.2.25", "4.2.26", "4.2.27"])
        self.assertEqual([v["ordinal"] for v in verses], [1, 2, 3])
        self.assertIn("याचका", verses[1]["deva"])
        self.assertIn("॥ २६ ॥", verses[1]["deva"])
        self.assertNotIn("याचका", verses[2]["deva"])

    def test_dropped_units_digit_before_next_plus_two(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_4_6_dropped_digit.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 4, 6)
        self.assertEqual([v["ref"] for v in verses], ["4.6.25", "4.6.26", "4.6.27"])
        self.assertIn("गजा गजीः", verses[1]["deva"])
        self.assertIn("तारहेम", verses[2]["deva"])
        self.assertIn("dropped digit", verses[1]["metadata"]["numbering_note"])

    def test_skandha_5_bare_line_numbers(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_5_1_bare_numbers.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 5, 1)
        self.assertEqual([v["ref"] for v in verses], ["5.1.1", "5.1.2", "5.1.3"])
        self.assertIn("प्रियव्रतो", verses[0]["deva"])
        self.assertIn("भवितुमर्हति", verses[1]["deva"])
        self.assertNotIn("प्रियव्रतो", verses[1]["deva"])

    def test_skandha_5_single_space_line_numbers(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_5_2_single_space_numbers.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 5, 2)
        self.assertEqual([v["ref"] for v in verses], ["5.2.1", "5.2.2", "5.2.3"])
        self.assertIn("पर्यगोपायत्", verses[0]["deva"])
        self.assertIn("तपस्व्याराधयां", verses[1]["deva"])

    def test_avagraha_colophon_is_not_a_verse(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_6_2_avagraha_colophon.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 6, 2)
        self.assertEqual([v["ref"] for v in verses], ["6.2.49"])
        self.assertIn("अजामिलो", verses[0]["deva"])
        self.assertNotIn("द्वितीयोध्या", " ".join(v["deva"] for v in verses))

    def test_dotted_sk_adh_verse_markers(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_5_24_dotted.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 5, 24)
        self.assertEqual([v["ref"] for v in verses], ["5.24.1", "5.24.2", "5.24.3"])
        self.assertIn("स्वर्भानु", verses[0]["deva"])
        self.assertIn("सुदर्शनं", verses[2]["deva"])
        self.assertNotIn("स्वर्भानु", verses[1]["deva"])

    def test_skandha_12_bare_line_numbers(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_12_1_bare_numbers.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 12, 1)
        self.assertEqual([v["ref"] for v in verses], ["12.1.1", "12.1.2", "12.1.3"])
        self.assertIn("शुनको", verses[0]["deva"])
        self.assertIn("प्रद्योतसंज्ञं", verses[1]["deva"])

    def test_trailing_bare_digit_does_not_rewind_classic_chapter(self):
        wiki = "जन्माद्यस्य यतः ॥ २३ ॥\nइति श्रीमद्भागवते leftover १\n"
        verses = G.parse_wikitext(wiki, 1, 1)
        self.assertEqual([v["ref"] for v in verses], ["1.1.23"])

    def test_classic_markers_win_over_bare_on_later_skandha_5(self):
        # 5.26 numbers with ॥ N ॥; leftover « ३» must not become a verse.
        wiki = "foo ॥ १ ॥\nbar ॥ २ ॥\nbaz ३\n"
        verses = G.parse_wikitext(wiki, 5, 26)
        self.assertEqual([v["ref"] for v in verses], ["5.26.1", "5.26.2"])

    def test_compact_danda_numbers(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_11_1_compact.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 11, 1)
        self.assertEqual([v["ref"] for v in verses], ["11.1.1", "11.1.2", "11.1.3"])
        self.assertIn("दैत्यवधं", verses[0]["deva"])
        self.assertIn("कोपिताः", verses[1]["deva"])

    def test_skandha_11_dropped_digit_after_ten(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_11_1_dropped_eleven.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 11, 1)
        self.assertEqual([v["ref"] for v in verses], ["11.1.10", "11.1.11", "11.1.12"])
        self.assertIn("निसृष्टाः", verses[1]["deva"])
        self.assertIn("विश्वामित्रो", verses[2]["deva"])
        self.assertIn("dropped digit", verses[1]["metadata"]["numbering_note"])

    def test_skandha_7_number_then_danda(self):
        wiki = (
            pathlib.Path(__file__).parent / "fixtures" / "bhagavata_7_1_number_then_danda.wiki"
        ).read_text(encoding="utf-8")
        verses = G.parse_wikitext(wiki, 7, 1)
        self.assertEqual([v["ref"] for v in verses], ["7.1.1", "7.1.2", "7.1.3"])
        self.assertIn("दैत्यानवधीद्", verses[0]["deva"])
        self.assertIn("विद्वेषो", verses[1]["deva"])


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

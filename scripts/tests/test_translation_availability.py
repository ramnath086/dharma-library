"""Where Bhāgavata translation / word-meaning data exists, it must reach the bundle.

The Bhāgavata English/Malayalam renderings and word meanings are a deliberate
**pilot** covering 1.1.1–1.1.10 only (guarded by
`test_pilot_translations_are_not_invented_beyond_1_1_10`); every other verse is
Sanskrit-only by design. This module locks the other half of that contract:
for the pilot verses the data must survive content → ingest → canonical bundle,
so a reader sees the translation and word meanings for 1.1.2 exactly as for
1.1.1, and a non-pilot verse stays honestly Sanskrit-only instead of silently
losing fields.
"""
from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SB = ROOT / "content" / "bhagavata-purana"
BUNDLE = ROOT / "app" / "assets" / "bundles" / "bhagavata-purana.json"

PILOT = ("1.1.1", "1.1.2", "1.1.10")
SANSKRIT_ONLY = ("1.1.11", "2.1.1")


def _corpus(ref: str) -> dict:
    canto, chapter, _verse = ref.split(".")
    data = json.loads((SB / canto / chapter / "verses.json").read_text(encoding="utf-8"))
    return next(v for v in data["verses"] if v["ref"] == ref)


class TranslationAvailability(unittest.TestCase):
    """Content is the source of truth; the bundle is what the app ships."""

    bundle_renderings: dict[str, set[str]] = {}
    bundle_words: dict[str, list[dict]] = {}

    @classmethod
    def setUpClass(cls):
        bundle = json.loads(BUNDLE.read_text(encoding="utf-8"))
        renderings: dict[str, set[str]] = {}
        words: dict[str, list[dict]] = {}
        for section in bundle["sections"]:
            for verse in section["verses"]:
                renderings[verse["ref"]] = {r["kind"] for r in verse["renderings"]}
                for r in verse["renderings"]:
                    if r["kind"] == "word_meanings" and r.get("word_meanings"):
                        words.setdefault(verse["ref"], []).extend(r["word_meanings"])
        cls.bundle_renderings = renderings
        cls.bundle_words = words

    def test_pilot_verses_carry_translation_and_word_meanings_in_the_corpus(self):
        for ref in PILOT:
            with self.subTest(ref=ref):
                verse = _corpus(ref)
                self.assertTrue(verse.get("en", "").strip(), f"missing English: {ref}")
                self.assertTrue(verse.get("ml", "").strip(), f"missing Malayalam: {ref}")
                self.assertTrue(verse.get("word_meanings"), f"missing word meanings: {ref}")

    def test_bundle_exposes_translation_and_word_meanings_for_every_pilot_verse(self):
        """1.1.2 and 1.1.10 must ship exactly like 1.1.1 — not only the first verse."""
        for ref in PILOT:
            with self.subTest(ref=ref):
                kinds = self.bundle_renderings[ref]
                self.assertIn("translation", kinds, f"translation lost in bundle: {ref}")
                self.assertIn("word_meanings", kinds, f"word meanings lost in bundle: {ref}")
                self.assertTrue(self.bundle_words.get(ref), f"word meanings empty in bundle: {ref}")

    def test_translation_and_word_meanings_are_not_dropped_part_way_through_a_chapter(self):
        """Regression guard: the pilot must not stop after the first verse."""
        carried = [ref for ref in PILOT if "translation" in self.bundle_renderings[ref]]
        self.assertEqual(carried, list(PILOT), "pilot renderings stopped before 1.1.10")

    def test_non_pilot_verses_ship_sanskrit_only_and_say_so(self):
        for ref in SANSKRIT_ONLY:
            with self.subTest(ref=ref):
                self.assertFalse(_corpus(ref).get("en"), f"invented English at {ref}")
                self.assertNotIn("translation", self.bundle_renderings[ref], f"invented translation at {ref}")
                self.assertNotIn("word_meanings", self.bundle_renderings[ref], f"invented word meanings at {ref}")


if __name__ == "__main__":
    unittest.main()

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
    def test_shipped_scope_matches_work_json(self):
        w = _load(BHAGAVATA / "work.json")
        meta = w["metadata"]
        files = _verse_files(BHAGAVATA)
        total = 0
        for vf in files:
            data = _load(vf)
            verses = data["verses"]
            total += len(verses)
            self.assertTrue(verses, vf)
            for i, v in enumerate(verses, 1):
                self.assertEqual(v["ordinal"], i, v.get("ref"))
                self.assertTrue(v["deva"].strip(), v["ref"])
                self.assertTrue(v["iast"].strip(), v["ref"])
        self.assertEqual(total, meta["imported_verse_count"])
        self.assertEqual(len(files), meta["imported_chapter_count"])
        if meta.get("complete"):
            self.assertEqual(len(files), 335)
            self.assertEqual(len({vf.parts[-3] for vf in files}), 12)
            self.assertIsNone(meta.get("pilot_scope"))
            self.assertNotIn("source_blocker", meta)
        else:
            self.assertEqual(files, [BHAGAVATA / "1" / "1" / "verses.json"])
            self.assertEqual(meta.get("pilot_scope"), "1.1.1–1.1.10")
            self.assertEqual(meta.get("imported_verse_count"), 10)
            self.assertFalse(meta.get("complete"))

    def test_pilot_translations_are_not_invented_beyond_1_1_10(self):
        data = _load(BHAGAVATA / "1" / "1" / "verses.json")
        verses = data["verses"]
        self.assertGreaterEqual(len(verses), 10)
        self.assertEqual([v["ref"] for v in verses[:10]], [f"1.1.{i}" for i in range(1, 11)])
        for v in verses[:10]:
            self.assertTrue(v["en"].strip())
            self.assertTrue(v["ml"].strip())
        for v in verses[10:]:
            self.assertFalse(v.get("en"), f"invented English at {v['ref']}")
            self.assertFalse(v.get("ml"), f"invented Malayalam at {v['ref']}")

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

    def test_bbt_printed_number_fills_are_present_and_unique(self):
        w = _load(BHAGAVATA / "work.json")
        fills = w["metadata"].get("bbt_vedabase_fill_refs") or []
        self.assertEqual(
            fills,
            ["1.13.36", "4.1.52", "4.21.45", "8.7.5", "8.16.23", "11.11.13", "11.27.40"],
        )
        seen = set()
        by_ref = {}
        for vf in _verse_files(BHAGAVATA):
            for v in _load(vf)["verses"]:
                self.assertNotIn(v["ref"], seen, v["ref"])
                seen.add(v["ref"])
                by_ref[v["ref"]] = v
        for ref in fills:
            v = by_ref[ref]
            meta = v.get("metadata") or {}
            self.assertEqual(meta.get("source_witness"), "bbt-vedabase", ref)
            self.assertTrue(meta.get("source_url", "").startswith("https://vedabase.io/"), ref)
            self.assertTrue(v["deva"].strip(), ref)
            self.assertNotIn("invent", (meta.get("numbering_note") or "").lower(), ref)
        self.assertEqual(len(seen), w["metadata"]["imported_verse_count"])
        self.assertEqual(len(fills), w["metadata"].get("bbt_vedabase_fill_count"))
        manifest = _load(BHAGAVATA / "WIKISOURCE_MANIFEST.json")
        imported = w["metadata"]["imported_verse_count"]
        # Manifest is WS-only (imported - fills) or merged (imported). Never double-count.
        self.assertIn(
            manifest["verses"],
            {imported, imported - len(fills)},
            "WIKISOURCE_MANIFEST verses must equal shipped count or WS-only count",
        )
        expected_deva = {
            "1.13.36": "विमृज्याश्रूणि पाणिभ्यां\nविष्टभ्यात्मानमात्मना ।\nअजातशत्रुं प्रत्यूचे प्रभोः पादावनुस्मरन् ॥ ३६ ॥",
            "4.1.52": "मेधा स्मृतिं तितिक्षा तु क्षेमं ह्रीः प्रश्रयं सुतम् ।\nमूर्तिः सर्वगुणोत्पत्तिर्नरनारायणावृषी ॥ ५२ ॥",
            "4.21.45": "मैत्रेय उवाच\nइति ब्रुवाणं नृपतिं पितृदेवद्विजातयः ।\nतुष्टुवुर्हृष्टमनसः साधुवादेन साधवः ॥ ४५ ॥",
            "8.7.5": "कृतस्थानविभागास्त एवं कश्यपनन्दनाः ।\nममन्थुः परमं यत्ता अमृतार्थं पयोनिधिम् ॥ ५ ॥",
            "8.16.23": "आदिश त्वं द्विजश्रेष्ठ विधिं तदुपधावनम् ।\nआशु तुष्यति मे देवः सीदन्त्याः सह पुत्रकैः ॥ २३ ॥",
            "11.11.13": "प्रतिबुद्ध इव स्वप्नान्नानात्वाद् विनिवर्तते ॥ १३ ॥",
            "11.27.40": "ध्यायन्नभ्यर्च्य दारूणि हविषाभिघृतानि च ।\nप्रास्याज्यभागावाघारौ दत्त्वा चाज्यप्लुतं हविः ॥ ४० ॥",
        }
        for ref, de in expected_deva.items():
            self.assertEqual(by_ref[ref]["deva"], de, ref)

    def test_audit_invariants_and_bundle_match_work_json(self):
        import sys
        sys.path.insert(0, str(ROOT / "scripts"))
        from audit_bhagavata_corpus import audit  # noqa: E402

        w = _load(BHAGAVATA / "work.json")
        meta = w["metadata"]
        report = audit()
        self.assertEqual(report["chapters_on_disk"], 335)
        self.assertEqual(report["imported_verses"], meta["imported_verse_count"])
        self.assertEqual(report["unique_refs"], report["imported_verses"])
        self.assertEqual(report["duplicate_refs"], [])
        self.assertEqual(report["empty_mula"], [])
        self.assertEqual(report["malformed_ids"], [])
        self.assertEqual(report["printed_gaps"], [])
        self.assertEqual(report["bbt_fills_missing"], [])
        self.assertEqual(report["unexplained"], [])
        self.assertEqual(
            set(report["latin_in_deva"]),
            {"1.13.1", "2.2.25", "3.12.47", "4.26.2", "4.26.16", "5.1.31", "5.1.32", "8.8.1", "8.8.3", "8.11.17"},
        )

        gita_bundle = _load(ROOT / "app" / "assets" / "bundles" / "bhagavad-gita.json")
        self.assertEqual(len(gita_bundle["sections"]), 18)
        self.assertEqual(sum(len(s["verses"]) for s in gita_bundle["sections"]), 700)

        bh_bundle = _load(ROOT / "app" / "assets" / "bundles" / "bhagavata-purana.json")
        n_verses = sum(len(s["verses"]) for s in bh_bundle["sections"])
        self.assertEqual(len(bh_bundle["sections"]), meta["imported_chapter_count"])
        self.assertEqual(n_verses, meta["imported_verse_count"])
        self.assertEqual(len(bh_bundle["sections"]), 335)

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

    def test_every_word_meanings_edition_has_its_own_verse_field(self):
        """Two word-by-word sources must not fight over one verse field."""
        w = _load(BHAGAVATA / "work.json")
        wm = [e for e in w["editions"] if e["kind"] == "word_meanings"]
        self.assertGreaterEqual(len(wm), 2, "expected the DCS word-by-word edition too")
        fields = [e.get("content_field") for e in wm]
        self.assertEqual(len(fields), len(set(fields)), fields)
        for e in wm:
            self.assertTrue(e.get("content_field"), e["slug"])
            status = {r["key"]: r["status"] for r in w["rights"]}[e["rights"]]
            self.assertIn(status, ("public_domain", "open_license",
                                   "permission_granted", "original"), e["slug"])

    def test_dcs_word_meanings_are_present_where_the_report_says_they_are(self):
        """The DCS edition may only cover the chapters it actually parsed."""
        w = _load(BHAGAVATA / "work.json")
        ed = next(e for e in w["editions"] if e["slug"] == "sb-wm-dcs-en")
        field = ed["content_field"]
        report = _load(ROOT / "docs" / "dcs-word-meanings-coverage.json")
        expected = report["summary"]["verses_with_glosses"]
        found = 0
        for vf in _verse_files(BHAGAVATA):
            for v in _load(vf)["verses"]:
                rows = v.get(field)
                if rows:
                    found += 1
                    self.assertTrue(all(r.get("word") and r.get("meaning") for r in rows),
                                    f"empty gloss at {v['ref']}")
                    for r in rows:
                        self.assertLessEqual(len(r["meaning"]), 145, v["ref"])
        self.assertEqual(found, expected, "content no longer matches the coverage report")

    def test_no_dutt_translation_is_ingested(self):
        """Dutt is public domain but unnumbered: nothing may be misattributed."""
        for vf in _verse_files(BHAGAVATA):
            for v in _load(vf)["verses"]:
                self.assertNotIn("en_dutt", v, f"unverified Dutt mapping at {v['ref']}")
        w = _load(BHAGAVATA / "work.json")
        slugs = {e["slug"] for e in w["editions"]}
        self.assertNotIn("sb-en-dutt", slugs)


if __name__ == "__main__":
    unittest.main()

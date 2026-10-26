"""Tests for the review-gated Bhāgavata AI translation workflow."""
from __future__ import annotations

import copy
import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from translate_bhagavata import (  # noqa: E402
    DEFAULT_WORK_DIR,
    PipelineError,
    TranslationPipeline,
    content_sha256,
    format_translation_scope,
    is_complete,
    ref_sort_key,
)


def read_json(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class RefAndScopeTests(unittest.TestCase):
    def test_suffixed_refs_sort_in_printed_reading_order(self):
        refs = ["1.13.41", "1.13.40b", "1.13.40"]
        self.assertEqual(sorted(refs, key=ref_sort_key), ["1.13.40", "1.13.40b", "1.13.41"])

    def test_suffixed_refs_never_disappear_inside_numeric_ranges(self):
        self.assertEqual(
            format_translation_scope(["1.13.41", "1.13.40b", "1.13.42", "1.13.40"]),
            "1.13.40, 1.13.40b, 1.13.41–1.13.42",
        )

    def test_ordinary_ranges_remain_compact(self):
        self.assertEqual(
            format_translation_scope([f"1.1.{number}" for number in range(1, 14)]),
            "1.1.1–1.1.13",
        )


class CheckedInSampleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pipeline = TranslationPipeline(DEFAULT_WORK_DIR)

    def test_status_checkpoint_is_derived_from_current_content(self):
        status = self.pipeline.status()
        drafts = self.pipeline.all_drafts()
        published = {ref for ref in self.pipeline.order if is_complete(self.pipeline.verses[ref])}
        expected_unpublished = next((ref for ref in self.pipeline.order if ref not in published), None)
        expected_ungenerated = next(
            (ref for ref in self.pipeline.order if ref not in published and ref not in drafts), None
        )
        expected_ready = [
            ref
            for ref in self.pipeline.order
            if ref not in published
            and ref in drafts
            and drafts[ref]["review"]["status"] == "approved"
        ]
        work = read_json(DEFAULT_WORK_DIR / "work.json")
        self.assertEqual(status["corpus_verses"], 14105)
        self.assertEqual(status["published_complete"], len(published))
        self.assertEqual(status["published_scope"], work["metadata"]["translation_scope"])
        self.assertEqual(status["next_unpublished"], expected_unpublished)
        self.assertEqual(status["next_ungenerated"], expected_ungenerated)
        self.assertEqual(status["approved_ready_to_promote"], expected_ready)
        self.assertEqual(status["published_partial"], [])

    def test_drafts_and_app_source_remain_review_consistent(self):
        drafts = self.pipeline.all_drafts()
        sample_refs = {"1.1.11", "1.1.12", "1.1.13"}
        self.assertTrue(sample_refs.issubset(drafts), "keep the original workflow sample records")
        self.assertEqual(self.pipeline.validate_all(), [])
        for ref, draft in drafts.items():
            self.assertEqual(draft["generation"]["method"], "ai_assisted", ref)
            source = self.pipeline.verses[ref]
            if draft["review"]["status"] != "approved":
                self.assertFalse(is_complete(source), f"unapproved draft leaked into app source at {ref}")
                continue
            if is_complete(source):
                for key in ("en", "ml", "word_meanings"):
                    self.assertEqual(source[key], draft[key], f"published/draft mismatch at {ref}")
                provenance = (source.get("metadata") or {}).get("translation_provenance")
                self.assertIsNotNone(provenance, f"missing promoted review provenance at {ref}")


class PipelineFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.work_dir = pathlib.Path(self.temporary.name) / "bhagavata-purana"
        source = read_json(DEFAULT_WORK_DIR / "1" / "1" / "verses.json")
        source["verses"] = copy.deepcopy(source["verses"][:13])
        # Fixtures always begin with only the original ten published verses,
        # even after the real 1.1.11–1.1.13 samples are reviewed and promoted.
        for verse in source["verses"][10:]:
            for key in ("en", "ml", "word_meanings"):
                verse.pop(key, None)
            metadata = dict(verse.get("metadata") or {})
            metadata.pop("translation_provenance", None)
            if metadata:
                verse["metadata"] = metadata
            else:
                verse.pop("metadata", None)
        (self.work_dir / "1" / "1").mkdir(parents=True)
        (self.work_dir / "1" / "1" / "verses.json").write_text(
            json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        work = read_json(DEFAULT_WORK_DIR / "work.json")
        work["metadata"]["translation_scope"] = "1.1.1–1.1.10"
        work["metadata"]["translated_verse_count"] = 10
        work["metadata"]["translation_counts"] = {"en": 10, "ml": 10, "word_meanings_en": 10}
        (self.work_dir / "work.json").write_text(
            json.dumps(work, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        self.pipeline = TranslationPipeline(self.work_dir)
        real_pipeline = TranslationPipeline(DEFAULT_WORK_DIR)
        real_samples = real_pipeline.read_chapter_drafts("1.1.11")
        self.samples = {}
        for ref in ("1.1.11", "1.1.12", "1.1.13"):
            self.samples[ref] = copy.deepcopy(real_samples[ref])
            self.samples[ref]["review"] = {
                "status": "pending",
                "reviewer": None,
                "reviewed_at": None,
                "notes": "Reset to pending for this isolated test fixture.",
            }

    def tearDown(self):
        self.temporary.cleanup()

    def stage(self, *refs: str):
        for ref in refs:
            self.pipeline.write_draft(copy.deepcopy(self.samples[ref]))

    def approve(self, start="1.1.11", end=None):
        return self.pipeline.review(
            start=start,
            end=end,
            approve=True,
            reviewer="Test Human Editor",
            attest_human_review=True,
            notes="Checked against the supplied Sanskrit in this fixture.",
        )

    def source(self):
        return read_json(self.work_dir / "1" / "1" / "verses.json")

    def test_pending_draft_cannot_be_promoted(self):
        self.stage("1.1.11")
        before = (self.work_dir / "1" / "1" / "verses.json").read_bytes()
        with self.assertRaisesRegex(PipelineError, "not approved"):
            self.pipeline.promote(start="1.1.11", apply=True)
        self.assertEqual((self.work_dir / "1" / "1" / "verses.json").read_bytes(), before)

    def test_approval_requires_explicit_human_attestation(self):
        self.stage("1.1.11")
        with self.assertRaisesRegex(PipelineError, "attest-human-review"):
            self.pipeline.review(
                start="1.1.11",
                end=None,
                approve=True,
                reviewer="Test Human Editor",
                attest_human_review=False,
            )
        self.assertEqual(self.pipeline.all_drafts()["1.1.11"]["review"]["status"], "pending")

    def test_approved_draft_promotes_with_provenance_and_scope(self):
        self.stage("1.1.11")
        self.approve()
        source_before = self.source()["verses"][10]
        deva_before = source_before["deva"]
        iast_before = source_before["iast"]

        # Promotion defaults to a dry run.
        self.assertEqual(self.pipeline.promote(start="1.1.11"), ["1.1.11"])
        self.assertFalse(self.source()["verses"][10].get("en"))
        self.assertEqual(self.pipeline.promote(start="1.1.11", apply=True), ["1.1.11"])

        promoted = self.source()["verses"][10]
        sample = self.samples["1.1.11"]
        self.assertEqual(promoted["deva"], deva_before)
        self.assertEqual(promoted["iast"], iast_before)
        self.assertEqual(promoted["en"], sample["en"])
        self.assertEqual(promoted["ml"], sample["ml"])
        self.assertEqual(promoted["word_meanings"], sample["word_meanings"])
        provenance = promoted["metadata"]["translation_provenance"]
        self.assertEqual(provenance["reviewer"], "Test Human Editor")
        self.assertEqual(provenance["content_sha256"], content_sha256(sample))

        work = read_json(self.work_dir / "work.json")
        self.assertEqual(work["metadata"]["translation_scope"], "1.1.1–1.1.11")
        self.assertEqual(work["metadata"]["translated_verse_count"], 11)
        self.assertEqual(work["metadata"]["translation_counts"]["word_meanings_en"], 11)
        self.assertIn("recorded human editorial review", work["description"])

    def test_editing_after_approval_invalidates_review_integrity(self):
        self.stage("1.1.11")
        self.approve()
        draft = self.pipeline.all_drafts()["1.1.11"]
        draft["en"] += " An unreviewed addition."
        self.pipeline.write_draft(draft)
        errors = self.pipeline.validate_all()
        self.assertTrue(any("changed after approval" in error for error in errors), errors)
        with self.assertRaisesRegex(PipelineError, "promotion blocked"):
            self.pipeline.promote(start="1.1.11", apply=True)

    def test_bad_source_hash_language_and_gloss_are_rejected(self):
        self.stage("1.1.11")
        draft = self.pipeline.all_drafts()["1.1.11"]
        draft["source_sha256"] = "0" * 64
        draft["ml"] = "This is not Malayalam."
        draft["word_meanings"][0]["word"] = "भूरिणि"
        self.pipeline.write_draft(draft)
        errors = self.pipeline.validate_all()
        self.assertTrue(any("source hash" in error for error in errors), errors)
        self.assertTrue(any("no Malayalam letters" in error for error in errors), errors)
        self.assertTrue(any("IAST word" in error for error in errors), errors)

    def test_openai_contract_and_adjacent_context_are_offline_testable(self):
        sample = self.samples["1.1.11"]
        response_body = {
            "id": "chatcmpl-test",
            "model": "fixture-model",
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "verses": [
                                    {key: sample[key] for key in ("ref", "en", "ml", "word_meanings")}
                                ]
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ],
        }

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return json.dumps(response_body, ensure_ascii=False).encode("utf-8")

        environment = {
            "OPENAI_API_KEY": "offline-test-secret",
            "OPENAI_BASE_URL": "https://api.example.test/v1",
            "OPENAI_TRANSLATION_MODEL": "requested-fixture-model",
        }
        with mock.patch.dict(os.environ, environment, clear=False):
            pipeline = TranslationPipeline(self.work_dir)
            with mock.patch("urllib.request.urlopen", return_value=FakeResponse()) as urlopen:
                parsed, generation = pipeline.request_batch(["1.1.11"])

        self.assertEqual(parsed["verses"][0]["ref"], "1.1.11")
        self.assertEqual(generation["provider"], "openai")
        self.assertEqual(generation["model"], "fixture-model")
        self.assertEqual(generation["response_id"], "chatcmpl-test")
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.example.test/v1/chat/completions")
        payload = json.loads(request.data.decode("utf-8"))
        self.assertEqual(payload["model"], "requested-fixture-model")
        self.assertEqual(payload["response_format"], {"type": "json_object"})
        user_payload = json.loads(payload["messages"][1]["content"].split("\n", 1)[1])
        self.assertEqual([v["ref"] for v in user_payload["verses"]], ["1.1.11"])
        self.assertEqual(user_payload["context_before"]["ref"], "1.1.10")
        self.assertEqual(user_payload["context_after"]["ref"], "1.1.12")
        self.assertNotIn("en", user_payload["context_before"], "only Sanskrit context may be sent")

    def test_generation_is_resumable_without_calling_a_network(self):
        real_samples = self.samples

        class FakePipeline(TranslationPipeline):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.calls = []

            def request_batch(self, refs):
                self.calls.append(list(refs))
                candidates = [
                    {
                        key: copy.deepcopy(real_samples[ref][key])
                        for key in ("ref", "en", "ml", "word_meanings")
                    }
                    for ref in refs
                ]
                generation = {
                    "provider": "test-double",
                    "model": "deterministic-fixture",
                    "prompt_version": "test-prompt",
                    "generated_at": "2026-10-26T00:00:00Z",
                }
                return {"verses": candidates}, generation

        fake = FakePipeline(self.work_dir)
        first = fake.generate(limit=2, batch_size=5)
        second = fake.generate(limit=2, batch_size=5)
        third = fake.generate(limit=2, batch_size=5)
        self.assertEqual(first["staged"], ["1.1.11", "1.1.12"])
        self.assertEqual(second["staged"], ["1.1.13"])
        self.assertEqual(third["staged"], [])
        self.assertEqual(fake.calls, [["1.1.11", "1.1.12"], ["1.1.13"]])
        self.assertEqual(fake.validate_all(), [])
        self.assertFalse(self.source()["verses"][10].get("en"), "generation must not publish directly")


if __name__ == "__main__":
    unittest.main()

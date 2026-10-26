#!/usr/bin/env python3
"""Resumable, review-gated AI assistance for Bhāgavata translations.

The source of truth remains content/bhagavata-purana/<canto>/<chapter>/verses.json.
AI responses are staged under translation-drafts/ and are never ingested merely
because they exist. A recorded human editorial review is required before a
draft can be promoted into the app content.

Typical first run (three verses is the deliberate default safety limit):

    export OPENAI_API_KEY=...                 # never commit this value
    python3 scripts/translate_bhagavata.py generate --limit 3
    python3 scripts/translate_bhagavata.py validate
    python3 scripts/translate_bhagavata.py status

See docs/translation-pipeline.md for review, promotion and app-export steps.
Only Python's standard library is required.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.request
from collections import Counter
from typing import Any, Iterable, Sequence

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_WORK_DIR = ROOT / "content" / "bhagavata-purana"
PROMPT_VERSION = "sb-translation-v1"
SCHEMA_VERSION = 1
DEFAULT_MODEL = "gpt-4o-mini"
REVIEW_STATUSES = {"pending", "approved", "rejected"}
REF_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)([a-z]?)$")
PLACEHOLDER_RE = re.compile(
    r"\b(?:TODO|TBD|lorem ipsum|translation here|meaning here|as an ai)\b",
    re.IGNORECASE,
)


class PipelineError(RuntimeError):
    """An actionable generation, validation, review or promotion failure."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None


def ref_parts(ref: str) -> tuple[int, int, int]:
    match = REF_RE.fullmatch(ref)
    if not match:
        raise PipelineError(f"invalid verse ref {ref!r}; expected CANTO.CHAPTER.VERSE with optional suffix")
    return tuple(int(part) for part in match.groups()[:3])  # type: ignore[return-value]


def ref_sort_key(ref: str) -> tuple[int, int, int, str]:
    match = REF_RE.fullmatch(ref)
    if not match:
        raise PipelineError(f"invalid verse ref {ref!r}; expected CANTO.CHAPTER.VERSE with optional suffix")
    canto, chapter, verse, suffix = match.groups()
    return int(canto), int(chapter), int(verse), suffix


def chapter_of(ref: str) -> str:
    canto, chapter, _ = ref_parts(ref)
    return f"{canto}.{chapter}"


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def source_sha256(verse: dict[str, Any]) -> str:
    return hashlib.sha256(
        canonical_json({"deva": verse["deva"], "iast": verse["iast"]}).encode("utf-8")
    ).hexdigest()


def content_sha256(draft: dict[str, Any]) -> str:
    payload = {
        "en": draft.get("en"),
        "ml": draft.get("ml"),
        "word_meanings": draft.get("word_meanings"),
    }
    return hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


def atomic_write_json(path: pathlib.Path, value: Any) -> None:
    """Write a complete JSON document, then atomically replace the old file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=path.parent, prefix=path.name + ".", suffix=".tmp", delete=False
        ) as handle:
            temporary = handle.name
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        mode = (path.stat().st_mode & 0o777) if path.exists() else 0o644
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PipelineError(f"cannot read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PipelineError(f"{path} must contain a JSON object")
    return value


def is_complete(verse: dict[str, Any]) -> bool:
    return all(
        isinstance(verse.get(key), str) and verse[key].strip()
        for key in ("en", "ml")
    ) and isinstance(verse.get("word_meanings"), list) and bool(verse["word_meanings"])


def format_translation_scope(refs: Iterable[str]) -> str:
    """Format translated refs as compact per-chapter ranges.

    Suffixed printed refs (for example 1.13.40b) remain explicit and break a
    numeric range; 40, 40b, 41 must never collapse into a misleading 40–41.
    """
    grouped: dict[tuple[int, int], list[tuple[int, str]]] = {}
    for ref in sorted(set(refs), key=ref_sort_key):
        canto, chapter, verse, suffix = ref_sort_key(ref)
        grouped.setdefault((canto, chapter), []).append((verse, suffix))
    ranges: list[str] = []
    for (canto, chapter), numbers in grouped.items():
        index = 0
        while index < len(numbers):
            start_number, start_suffix = numbers[index]
            end_number, end_suffix = start_number, start_suffix
            next_index = index + 1
            if not start_suffix:
                while next_index < len(numbers):
                    candidate_number, candidate_suffix = numbers[next_index]
                    if candidate_suffix or candidate_number != end_number + 1:
                        break
                    end_number = candidate_number
                    next_index += 1
            start_ref = f"{canto}.{chapter}.{start_number}{start_suffix}"
            if start_number == end_number and start_suffix == end_suffix:
                ranges.append(start_ref)
            else:
                ranges.append(f"{start_ref}–{canto}.{chapter}.{end_number}{end_suffix}")
            index = next_index
    return ", ".join(ranges)


def _has_devanagari(value: str) -> bool:
    return any("\u0900" <= char <= "\u097f" for char in value)


def _has_malayalam(value: str) -> bool:
    return any("\u0d00" <= char <= "\u0d7f" for char in value)


def _has_latin(value: str) -> bool:
    # Includes standalone IAST letters such as ā, not only ASCII a–z.
    return any(char.isalpha() and unicodedata.name(char, "").startswith("LATIN") for char in value)


SYSTEM_PROMPT = """You are assisting a careful Sanskrit editorial team working on the Śrīmad Bhāgavata Purāṇa.
Produce an independent, literal-but-readable English prose translation, a natural and accurate Malayalam prose translation, and English word-by-word glosses keyed to the supplied IAST.

Rules:
- Translate only the supplied Sanskrit. Do not copy or imitate a published translation, commentary, synonyms list, or purport.
- Do not add theology, sectarian interpretation, narrative details, notes, cross-references, or explanations that are not needed for a clear literal rendering.
- Resolve compounds and sandhi in the glosses when helpful, but keep every gloss tied to the actual IAST wording. Use IAST, not Devanagari, in the `word` field. Group a compound or sandhi join when that is clearer.
- Cover every meaning-bearing word in order, including repeated particles. Meanings must be concise English glosses, not commentary.
- Preserve speaker, addressee, number, negation, mood and relational pronouns. `ātmā` may mean self, heart or inner being according to context; do not impose a doctrine.
- Malayalam must be a direct rendering of the Sanskrit, not a translation of your English sentence. Use customary Sanskrit names in Malayalam script and fluent Malayalam grammar.
- Return strict JSON only, with no Markdown. Shape: {"verses":[{"ref":"C.C.V","en":"...","ml":"...","word_meanings":[{"word":"IAST","meaning":"English"}]}]}.
- `context_before` and `context_after`, when present, are Sanskrit context only. Use them to resolve pronouns and narrative continuity, but never translate or return those context refs.
- Return exactly one object for every requested ref and no other refs. If uncertain, make the most conservative literal choice; a human editor will review the draft.
- Automated output is an unreviewed draft. Never claim scholarly approval.
"""


class TranslationPipeline:
    def __init__(self, work_dir: pathlib.Path = DEFAULT_WORK_DIR, model: str | None = None):
        self.work_dir = work_dir.resolve()
        self.draft_dir = self.work_dir / "translation-drafts"
        self.model = model or os.environ.get("OPENAI_TRANSLATION_MODEL") or DEFAULT_MODEL
        self._verses: dict[str, dict[str, Any]] | None = None
        self._order: list[str] | None = None
        self._verse_files: dict[str, pathlib.Path] | None = None

    @property
    def verses(self) -> dict[str, dict[str, Any]]:
        self._load_corpus()
        return self._verses or {}

    @property
    def order(self) -> list[str]:
        self._load_corpus()
        return self._order or []

    def _load_corpus(self) -> None:
        if self._verses is not None:
            return
        verses: dict[str, dict[str, Any]] = {}
        files: dict[str, pathlib.Path] = {}
        paths = sorted(self.work_dir.glob("**/verses.json"))
        if not paths:
            raise PipelineError(f"no verses.json files found under {self.work_dir}")
        for path in paths:
            data = read_json(path)
            chapter_verses = data.get("verses")
            if not isinstance(chapter_verses, list):
                raise PipelineError(f"{path} has no verses list")
            for verse in chapter_verses:
                ref = verse.get("ref", "")
                ref_parts(ref)
                if ref in verses:
                    raise PipelineError(f"duplicate source ref {ref}")
                if not isinstance(verse.get("deva"), str) or not isinstance(verse.get("iast"), str):
                    raise PipelineError(f"{ref} lacks Devanagari or IAST source text")
                verses[ref] = verse
                files[ref] = path
        self._verses = verses
        self._order = sorted(verses, key=ref_sort_key)
        self._verse_files = files

    def invalidate_corpus_cache(self) -> None:
        self._verses = None
        self._order = None
        self._verse_files = None

    def draft_path(self, ref: str) -> pathlib.Path:
        canto, chapter, _ = ref_parts(ref)
        return self.draft_dir / str(canto) / f"{chapter}.json"

    def read_chapter_drafts(self, ref: str) -> dict[str, dict[str, Any]]:
        path = self.draft_path(ref)
        if not path.exists():
            return {}
        data = read_json(path)
        if data.get("schema_version") != SCHEMA_VERSION:
            raise PipelineError(f"unsupported draft schema in {path}")
        records = data.get("drafts")
        if not isinstance(records, list):
            raise PipelineError(f"{path} has no drafts list")
        result: dict[str, dict[str, Any]] = {}
        for record in records:
            if not isinstance(record, dict) or not isinstance(record.get("ref"), str):
                raise PipelineError(f"invalid draft record in {path}")
            record_ref = record["ref"]
            ref_parts(record_ref)
            if self.draft_path(record_ref) != path:
                raise PipelineError(f"{record_ref} is stored in the wrong chapter file: {path}")
            if record_ref in result:
                raise PipelineError(f"duplicate draft {record_ref} in {path}")
            result[record_ref] = record
        return result

    def write_draft(self, draft: dict[str, Any]) -> None:
        ref = draft["ref"]
        path = self.draft_path(ref)
        records = self.read_chapter_drafts(ref)
        records[ref] = draft
        payload = {
            "schema_version": SCHEMA_VERSION,
            "work": "bhagavata-purana",
            "chapter": chapter_of(ref),
            "drafts": [records[key] for key in sorted(records, key=ref_sort_key)],
        }
        atomic_write_json(path, payload)

    def all_drafts(self) -> dict[str, dict[str, Any]]:
        result: dict[str, dict[str, Any]] = {}
        if not self.draft_dir.exists():
            return result
        paths = sorted(self.draft_dir.glob("*/*.json"))
        for path in paths:
            relative = path.relative_to(self.draft_dir)
            probe = f"{relative.parts[0]}.{path.stem}.1"
            for ref, draft in self.read_chapter_drafts(probe).items():
                if ref in result:
                    raise PipelineError(f"draft {ref} occurs in more than one file")
                result[ref] = draft
        return result

    def status(self) -> dict[str, Any]:
        drafts = self.all_drafts()
        published = {ref for ref in self.order if is_complete(self.verses[ref])}
        partial = [
            ref
            for ref in self.order
            if not is_complete(self.verses[ref])
            and any(self.verses[ref].get(key) for key in ("en", "ml", "word_meanings"))
        ]
        review_counts = Counter(
            (draft.get("review") or {}).get("status", "missing") for draft in drafts.values()
        )
        next_unpublished = next((ref for ref in self.order if ref not in published), None)
        next_ungenerated = next(
            (
                ref
                for ref in self.order
                if ref not in published and ref not in drafts
            ),
            None,
        )
        approved_ready = [
            ref
            for ref, draft in drafts.items()
            if ref not in published and (draft.get("review") or {}).get("status") == "approved"
        ]
        return {
            "corpus_verses": len(self.order),
            "published_complete": len(published),
            "published_partial": partial,
            "published_scope": format_translation_scope(published),
            "next_unpublished": next_unpublished,
            "next_ungenerated": next_ungenerated,
            "draft_records": len(drafts),
            "draft_review_counts": dict(sorted(review_counts.items())),
            "approved_ready_to_promote": sorted(approved_ready, key=ref_sort_key),
        }

    def select(self, start: str | None, end: str | None, limit: int | None, *, generating: bool) -> list[str]:
        if start is None:
            if not generating:
                raise PipelineError("--start is required for this command")
            start = self.status()["next_ungenerated"]
            if start is None:
                return []
        ref_parts(start)
        if start not in self.verses:
            raise PipelineError(f"unknown start ref {start}")
        start_index = self.order.index(start)
        if end is not None:
            ref_parts(end)
            if end not in self.verses:
                raise PipelineError(f"unknown end ref {end}")
            end_index = self.order.index(end)
            if end_index < start_index:
                raise PipelineError("--end must not precede --start")
            return self.order[start_index : end_index + 1]
        count = 3 if limit is None else limit
        if count < 1:
            raise PipelineError("--limit must be at least 1")
        return self.order[start_index : start_index + count]

    def validate_draft(self, draft: dict[str, Any], *, check_review_integrity: bool = True) -> list[str]:
        errors: list[str] = []
        ref = draft.get("ref")
        if not isinstance(ref, str) or not REF_RE.fullmatch(ref):
            return ["missing or malformed ref"]
        prefix = f"{ref}: "
        if ref not in self.verses:
            return [prefix + "ref is not present in the source corpus"]

        if draft.get("source_sha256") != source_sha256(self.verses[ref]):
            errors.append(prefix + "source hash does not match the current Devanagari and IAST")

        for language in ("en", "ml"):
            value = draft.get(language)
            if not isinstance(value, str) or not value.strip():
                errors.append(prefix + f"{language} must be a non-empty string")
            elif PLACEHOLDER_RE.search(value):
                errors.append(prefix + f"{language} contains a placeholder or AI disclaimer")

        en = draft.get("en")
        if isinstance(en, str) and en.strip():
            if not _has_latin(en):
                errors.append(prefix + "English translation has no Latin letters")
            if _has_devanagari(en) or _has_malayalam(en):
                errors.append(prefix + "English translation contains Devanagari or Malayalam script")
        ml = draft.get("ml")
        if isinstance(ml, str) and ml.strip():
            if not _has_malayalam(ml):
                errors.append(prefix + "Malayalam translation has no Malayalam letters")
            if _has_devanagari(ml):
                errors.append(prefix + "Malayalam translation contains Devanagari source text")

        glosses = draft.get("word_meanings")
        if not isinstance(glosses, list) or not glosses:
            errors.append(prefix + "word_meanings must be a non-empty list")
        else:
            for index, gloss in enumerate(glosses, 1):
                location = f"{prefix}gloss {index}"
                if not isinstance(gloss, dict) or set(gloss) != {"word", "meaning"}:
                    errors.append(location + " must contain exactly word and meaning")
                    continue
                word, meaning = gloss["word"], gloss["meaning"]
                if not isinstance(word, str) or not word.strip() or not _has_latin(word):
                    errors.append(location + " needs an IAST word in Latin script")
                elif _has_devanagari(word) or _has_malayalam(word):
                    errors.append(location + " word must use IAST, not an Indic script")
                if not isinstance(meaning, str) or not meaning.strip() or not _has_latin(meaning):
                    errors.append(location + " needs a non-empty English meaning")
                elif PLACEHOLDER_RE.search(meaning):
                    errors.append(location + " contains a placeholder")

        generation = draft.get("generation")
        if not isinstance(generation, dict):
            errors.append(prefix + "generation provenance is missing")
            generation = {}
        if generation.get("method") != "ai_assisted":
            errors.append(prefix + "generation.method must be ai_assisted")
        for key in ("provider", "model", "prompt_version", "generated_at"):
            if not isinstance(generation.get(key), str) or not generation[key].strip():
                errors.append(prefix + f"generation.{key} is required")
        if generation.get("generated_at") and not parse_timestamp(generation["generated_at"]):
            errors.append(prefix + "generation.generated_at must be an ISO-8601 timestamp with timezone")
        if generation.get("output_sha256") != content_sha256(draft):
            # Human correction while pending is legitimate; this is informational
            # until review, at which point review.content_sha256 locks the text.
            if not generation.get("output_sha256"):
                errors.append(prefix + "generation.output_sha256 is required")

        review = draft.get("review")
        if not isinstance(review, dict):
            errors.append(prefix + "review state is missing")
            review = {}
        status = review.get("status")
        if status not in REVIEW_STATUSES:
            errors.append(prefix + "review.status must be pending, approved or rejected")
        if status == "approved":
            if not isinstance(review.get("reviewer"), str) or not review["reviewer"].strip():
                errors.append(prefix + "approved draft needs a named reviewer")
            if review.get("attestation") != "human_editorial_review":
                errors.append(prefix + "approved draft lacks human editorial-review attestation")
            if not parse_timestamp(review.get("reviewed_at")):
                errors.append(prefix + "approved draft needs a valid reviewed_at timestamp")
            if check_review_integrity and review.get("content_sha256") != content_sha256(draft):
                errors.append(prefix + "content changed after approval; it must be reviewed again")
        if status == "rejected" and not (isinstance(review.get("notes"), str) and review["notes"].strip()):
            errors.append(prefix + "rejected draft needs review notes")

        return errors

    def validate_all(self) -> list[str]:
        errors: list[str] = []
        for ref, draft in sorted(self.all_drafts().items(), key=lambda item: ref_sort_key(item[0])):
            errors.extend(self.validate_draft(draft))
        return errors

    def make_draft(self, candidate: dict[str, Any], generation: dict[str, Any]) -> dict[str, Any]:
        expected = {"ref", "en", "ml", "word_meanings"}
        if set(candidate) != expected:
            raise PipelineError(
                f"{candidate.get('ref', '<unknown>')}: AI object must contain exactly {sorted(expected)}"
            )
        ref = candidate["ref"]
        if not isinstance(ref, str) or ref not in self.verses:
            raise PipelineError(f"AI returned unknown ref {ref!r}")
        draft: dict[str, Any] = {
            "ref": ref,
            "source_sha256": source_sha256(self.verses[ref]),
            "en": candidate["en"],
            "ml": candidate["ml"],
            "word_meanings": candidate["word_meanings"],
            "generation": {
                "method": "ai_assisted",
                "provider": generation["provider"],
                "model": generation["model"],
                "prompt_version": generation.get("prompt_version", PROMPT_VERSION),
                "generated_at": generation.get("generated_at", utc_now()),
            },
            "review": {
                "status": "pending",
                "reviewer": None,
                "reviewed_at": None,
                "notes": None,
            },
        }
        if generation.get("response_id"):
            draft["generation"]["response_id"] = generation["response_id"]
        draft["generation"]["output_sha256"] = content_sha256(draft)
        errors = self.validate_draft(draft)
        if errors:
            raise PipelineError("invalid AI draft:\n  " + "\n  ".join(errors))
        return draft

    def request_batch(self, refs: Sequence[str]) -> tuple[dict[str, Any], dict[str, Any]]:
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            raise PipelineError(
                "OPENAI_API_KEY is not set. Export it only in your shell; never place it in JSON or Git."
            )
        base_url = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
        def source_record(ref: str) -> dict[str, Any]:
            return {
                "ref": ref,
                "speaker": self.verses[ref].get("speaker"),
                "devanagari": self.verses[ref]["deva"],
                "iast": self.verses[ref]["iast"],
            }

        source = [source_record(ref) for ref in refs]
        first_index = self.order.index(refs[0])
        last_index = self.order.index(refs[-1])
        before = self.order[first_index - 1] if first_index > 0 else None
        after = self.order[last_index + 1] if last_index + 1 < len(self.order) else None
        if before and chapter_of(before) != chapter_of(refs[0]):
            before = None
        if after and chapter_of(after) != chapter_of(refs[-1]):
            after = None
        assert self._verse_files is not None
        chapter_data = read_json(self._verse_files[refs[0]])
        chapter_info = (chapter_data.get("section") or {}).get("chapter") or {}
        user_payload = {
            "chapter": {
                "ref": chapter_of(refs[0]),
                "title_iast": chapter_info.get("title_iast"),
                "title_en": chapter_info.get("title_en"),
            },
            "context_before": source_record(before) if before else None,
            "verses": source,
            "context_after": source_record(after) if after else None,
        }
        payload = {
            "model": self.model,
            "temperature": 0.2,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": "Translate only the refs in `verses`; use but do not translate the adjacent context. Return exactly the requested refs.\n"
                    + json.dumps(user_payload, ensure_ascii=False),
                },
            ],
        }
        request = urllib.request.Request(
            base_url + "/chat/completions",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "User-Agent": "DharmaLibrary-TranslationPipeline/1",
            },
            method="POST",
        )
        last_error: Exception | None = None
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=180) as response:
                    body = json.loads(response.read().decode("utf-8"))
                content = body["choices"][0]["message"]["content"]
                parsed = json.loads(content)
                if not isinstance(parsed, dict) or not isinstance(parsed.get("verses"), list):
                    raise PipelineError("AI response does not contain a verses list")
                generation = {
                    "provider": "openai",
                    "model": body.get("model") or self.model,
                    "response_id": body.get("id"),
                    "prompt_version": PROMPT_VERSION,
                    "generated_at": utc_now(),
                }
                return parsed, generation
            except urllib.error.HTTPError as exc:
                last_error = exc
                if exc.code not in {408, 409, 429, 500, 502, 503, 504}:
                    detail = exc.read().decode("utf-8", errors="replace")[:1000]
                    raise PipelineError(f"translation API returned HTTP {exc.code}: {detail}") from exc
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, KeyError, IndexError) as exc:
                last_error = exc
            if attempt < 3:
                time.sleep(2**attempt)
        raise PipelineError(f"translation API failed after 4 attempts: {last_error}") from last_error

    def generate(
        self,
        *,
        start: str | None = None,
        end: str | None = None,
        limit: int | None = None,
        batch_size: int = 3,
        force: bool = False,
    ) -> dict[str, list[str]]:
        if not 1 <= batch_size <= 5:
            raise PipelineError("--batch-size must be between 1 and 5")
        selected = self.select(start, end, limit, generating=True)
        drafts = self.all_drafts()
        todo: list[str] = []
        result = {"staged": [], "skipped": []}
        for ref in selected:
            source = self.verses[ref]
            if is_complete(source):
                result["skipped"].append(f"{ref} (already published)")
                continue
            if any(source.get(key) for key in ("en", "ml", "word_meanings")):
                raise PipelineError(f"{ref} has partial published content; inspect it before generating")
            existing = drafts.get(ref)
            if existing and not force:
                result["skipped"].append(f"{ref} (draft already exists)")
                continue
            if existing and (existing.get("review") or {}).get("status") == "approved":
                raise PipelineError(f"{ref} is approved; refusing to overwrite an approved draft")
            todo.append(ref)

        # Keep each API request within one chapter. This simplifies review and
        # ensures a response can never silently cross a chapter boundary.
        batches: list[list[str]] = []
        for ref in todo:
            if (
                not batches
                or len(batches[-1]) >= batch_size
                or chapter_of(batches[-1][0]) != chapter_of(ref)
            ):
                batches.append([])
            batches[-1].append(ref)

        for batch in batches:
            response, generation = self.request_batch(batch)
            candidates = response.get("verses", [])
            by_ref: dict[str, dict[str, Any]] = {}
            for candidate in candidates:
                if not isinstance(candidate, dict) or not isinstance(candidate.get("ref"), str):
                    raise PipelineError("AI returned a malformed verse object")
                ref = candidate["ref"]
                if ref in by_ref:
                    raise PipelineError(f"AI returned duplicate ref {ref}")
                by_ref[ref] = candidate
            if set(by_ref) != set(batch):
                raise PipelineError(
                    f"AI ref mismatch: requested {batch}, received {sorted(by_ref)}; nothing from this batch was staged"
                )
            # Validate the complete batch before writing any member of it.
            new_drafts = [self.make_draft(by_ref[ref], generation) for ref in batch]
            for draft in new_drafts:
                self.write_draft(draft)
                result["staged"].append(draft["ref"])
        return result

    def review(
        self,
        *,
        start: str,
        end: str | None,
        approve: bool,
        reviewer: str,
        attest_human_review: bool,
        notes: str | None = None,
    ) -> list[str]:
        if not reviewer.strip():
            raise PipelineError("--reviewer must name the editor who examined the draft")
        if approve and not attest_human_review:
            raise PipelineError("approval requires --attest-human-review after actual human editorial review")
        if not approve and not (notes and notes.strip()):
            raise PipelineError("rejection requires --notes explaining what must be corrected")
        refs = self.select(start, end or start, None, generating=False)
        drafts = self.all_drafts()
        missing = [ref for ref in refs if ref not in drafts]
        if missing:
            raise PipelineError("no staged draft for: " + ", ".join(missing))
        errors: list[str] = []
        for ref in refs:
            errors.extend(self.validate_draft(drafts[ref], check_review_integrity=False))
        if errors:
            raise PipelineError("cannot review invalid drafts:\n  " + "\n  ".join(errors))
        now = utc_now()
        for ref in refs:
            draft = drafts[ref]
            draft["review"] = {
                "status": "approved" if approve else "rejected",
                "reviewer": reviewer.strip(),
                "reviewed_at": now,
                "notes": notes.strip() if notes else None,
                "content_sha256": content_sha256(draft),
                "changed_in_review": content_sha256(draft)
                != (draft.get("generation") or {}).get("output_sha256"),
            }
            if approve:
                draft["review"]["attestation"] = "human_editorial_review"
            self.write_draft(draft)
        return refs

    def promote(
        self,
        *,
        start: str | None = None,
        end: str | None = None,
        all_approved: bool = False,
        apply: bool = False,
    ) -> list[str]:
        drafts = self.all_drafts()
        if all_approved:
            if start or end:
                raise PipelineError("--all-approved cannot be combined with --start or --end")
            refs = [
                ref
                for ref in self.order
                if ref in drafts
                and not is_complete(self.verses[ref])
                and (drafts[ref].get("review") or {}).get("status") == "approved"
            ]
        else:
            if not start:
                raise PipelineError("promotion requires --start or --all-approved")
            refs = self.select(start, end or start, None, generating=False)
        if not refs:
            return []
        errors: list[str] = []
        for ref in refs:
            draft = drafts.get(ref)
            if not draft:
                errors.append(f"{ref}: no staged draft")
                continue
            if (draft.get("review") or {}).get("status") != "approved":
                errors.append(f"{ref}: draft is not approved")
            source = self.verses[ref]
            if is_complete(source) and any(source.get(key) != draft.get(key) for key in ("en", "ml", "word_meanings")):
                errors.append(f"{ref}: published translation differs from the draft; refusing to overwrite it")
            errors.extend(self.validate_draft(draft))
        if errors:
            raise PipelineError("promotion blocked:\n  " + "\n  ".join(errors))
        if not apply:
            return refs

        assert self._verse_files is not None
        by_file: dict[pathlib.Path, list[str]] = {}
        for ref in refs:
            by_file.setdefault(self._verse_files[ref], []).append(ref)
        for path, file_refs in by_file.items():
            data = read_json(path)
            for verse in data["verses"]:
                ref = verse["ref"]
                if ref not in file_refs:
                    continue
                draft = drafts[ref]
                verse["en"] = draft["en"]
                verse["ml"] = draft["ml"]
                verse["word_meanings"] = draft["word_meanings"]
                metadata = dict(verse.get("metadata") or {})
                generation = draft["generation"]
                review = draft["review"]
                metadata["translation_provenance"] = {
                    "method": "ai_assisted",
                    "provider": generation["provider"],
                    "model": generation["model"],
                    "prompt_version": generation["prompt_version"],
                    "generated_at": generation["generated_at"],
                    "source_sha256": draft["source_sha256"],
                    "reviewer": review["reviewer"],
                    "reviewed_at": review["reviewed_at"],
                    "changed_in_review": review.get("changed_in_review", False),
                    "content_sha256": review["content_sha256"],
                }
                verse["metadata"] = metadata
            atomic_write_json(path, data)

        self.invalidate_corpus_cache()
        self._load_corpus()
        work_path = self.work_dir / "work.json"
        work = read_json(work_path)
        metadata = dict(work.get("metadata") or {})
        complete_refs = [ref for ref in self.order if is_complete(self.verses[ref])]
        metadata["translation_scope"] = format_translation_scope(complete_refs)
        metadata["translated_verse_count"] = len(complete_refs)
        metadata["translation_counts"] = {
            "en": sum(bool(self.verses[ref].get("en")) for ref in self.order),
            "ml": sum(bool(self.verses[ref].get("ml")) for ref in self.order),
            "word_meanings_en": sum(bool(self.verses[ref].get("word_meanings")) for ref in self.order),
        }
        metadata["translation_review"] = (
            "AI-assisted drafts are promoted only after recorded human editorial review; "
            "all translations remain drafts pending scholarly review."
        )
        work["metadata"] = metadata
        description = work.get("description")
        if isinstance(description, str):
            work["description"] = re.sub(
                r"English and Malayalam translations remain original Dharma Library drafts on .*?; "
                r"other verses have no invented translation\.",
                "English and Malayalam translations and English word-by-word glosses are original "
                "Dharma Library drafts; see metadata.translation_scope for current coverage. "
                "AI-assisted drafts are promoted only after recorded human editorial review.",
                description,
            )
        atomic_write_json(work_path, work)
        return refs


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=pathlib.Path, default=DEFAULT_WORK_DIR, help=argparse.SUPPRESS)
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser("generate", help="stage AI drafts; never modifies published verses")
    generate.add_argument("--start", help="first ref (default: first verse needing a draft)")
    destination = generate.add_mutually_exclusive_group()
    destination.add_argument("--end", help="last ref, inclusive")
    destination.add_argument("--limit", type=int, help="maximum refs to select (default: 3)")
    generate.add_argument("--batch-size", type=int, default=3, help="verses per API request, 1–5")
    generate.add_argument("--force", action="store_true", help="replace unapproved staged drafts")

    subparsers.add_parser("validate", help="validate every staged draft without network access")
    subparsers.add_parser("status", help="show published, staged and next-required coverage")

    review = subparsers.add_parser("review", help="record an editorial decision on staged drafts")
    review.add_argument("--start", required=True)
    review.add_argument("--end", help="last ref, inclusive (default: --start)")
    decision = review.add_mutually_exclusive_group(required=True)
    decision.add_argument("--approve", action="store_true")
    decision.add_argument("--reject", action="store_true")
    review.add_argument("--reviewer", required=True, help="name of the editor (recorded in provenance)")
    review.add_argument("--attest-human-review", action="store_true")
    review.add_argument("--notes")

    promote = subparsers.add_parser("promote", help="copy approved drafts into app source JSON")
    promote.add_argument("--start")
    promote.add_argument("--end", help="last ref, inclusive (default: --start)")
    promote.add_argument("--all-approved", action="store_true")
    promote.add_argument("--apply", action="store_true", help="write changes; without this, perform a dry run")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    pipeline = TranslationPipeline(args.work_dir)
    try:
        if args.command == "status":
            print(json.dumps(pipeline.status(), ensure_ascii=False, indent=2))
        elif args.command == "validate":
            errors = pipeline.validate_all()
            if errors:
                print("Draft validation failed:", file=sys.stderr)
                for error in errors:
                    print("  " + error, file=sys.stderr)
                return 1
            count = len(pipeline.all_drafts())
            print(f"Validated {count} staged draft(s): no structural, provenance or review-integrity errors.")
        elif args.command == "generate":
            result = pipeline.generate(
                start=args.start,
                end=args.end,
                limit=args.limit,
                batch_size=args.batch_size,
                force=args.force,
            )
            for item in result["skipped"]:
                print("skipped", item)
            for ref in result["staged"]:
                print("staged", ref)
            print(f"Staged {len(result['staged'])} new draft(s); no published verse was changed.")
        elif args.command == "review":
            refs = pipeline.review(
                start=args.start,
                end=args.end,
                approve=args.approve,
                reviewer=args.reviewer,
                attest_human_review=args.attest_human_review,
                notes=args.notes,
            )
            print(f"{'Approved' if args.approve else 'Rejected'} {len(refs)} draft(s): {', '.join(refs)}")
        elif args.command == "promote":
            refs = pipeline.promote(
                start=args.start,
                end=args.end,
                all_approved=args.all_approved,
                apply=args.apply,
            )
            if not refs:
                print("No approved unpublished drafts selected.")
            elif args.apply:
                print(f"Promoted {len(refs)} verse(s): {', '.join(refs)}")
                print("Next: regenerate SQL, ingest it, and export the offline app bundle.")
            else:
                print(f"Dry run: {len(refs)} approved verse(s) can be promoted: {', '.join(refs)}")
                print("Re-run with --apply only after checking the diff.")
        return 0
    except PipelineError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

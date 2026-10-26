# AI-assisted Bhāgavata translation pipeline

This workflow expands the existing **English translation, Malayalam translation,
and English word-by-word glosses** without allowing unreviewed AI output to enter
the reader app. It uses only the Python standard library.

## Current checkpoint

The checked-in corpus has **14,105 source verses in 335 chapters**.

| State | Coverage / next action |
|---|---|
| Published in app source | `1.1.1–1.1.10` (10 verses) |
| Next unpublished verse | `1.1.11` |
| Staged AI-assisted drafts | `1.1.11–1.1.23` (rest of Chapter 1), **pending human review** |
| Next verse with no staged draft | `1.2.1` |
| Remaining unpublished after the original pilot | 14,095 verses |

The drafts live in `content/bhagavata-purana/translation-drafts/1/1.json`.
They are deliberately **not** present in `1/1/verses.json`, generated SQL, or the
offline app bundle. `scripts/translate_bhagavata.py status` recalculates this
checkpoint from the actual files rather than relying on this table.

## Safety and editorial rules

1. **Generation and publication are separate.** `generate` writes only staged
   drafts. It cannot add a translation to the app.
2. **Human approval is mandatory.** `promote` rejects pending or rejected
   drafts. Approval requires the reviewer to pass `--attest-human-review`.
3. **The source is locked.** Every draft stores a SHA-256 hash of its source
   Devanagari and IAST. A source change blocks review/promotion until the draft
   is regenerated.
4. **Approval is locked to the reviewed text.** Any edit after approval makes
   validation fail and requires another review.
5. **Translations remain drafts.** Publication here means inclusion in app
   content, not scholarly certification. The existing UI continues to label
   translations *draft — pending scholarly review*.
6. **No copied modern translations.** Do not paste or ask the model to reproduce
   BBT/Vedabase, Gita Press, Motilal Banarsidass, or another copyrighted
   translation, synonyms list, or purport. The prompt requests an independent
   literal rendering from the repository's Sanskrit mūla.
7. **Both languages and glosses are one unit.** Partial `en`/`ml`/
   `word_meanings` output is not considered complete.

Automated validation checks structure, language script, provenance, hashes, and
review state. It **cannot establish Sanskrit semantic accuracy**; that remains
the editor's responsibility.

## Files

```text
scripts/translate_bhagavata.py                  generation/review/promotion CLI
content/bhagavata-purana/translation-drafts/
  <canto>/<chapter>.json                        staged records and audit state
content/bhagavata-purana/<canto>/<chapter>/
  verses.json                                   app source; changed only by promote
scripts/tests/test_translation_pipeline.py      offline tests; no API required
```

Each staged record contains:

- `ref` and `source_sha256`;
- `en`, `ml`, and ordered `word_meanings` (`word` in IAST, `meaning` in English);
- generation provider/model/prompt/timestamp and original-output hash;
- pending/approved/rejected review state, reviewer, timestamp, notes, and the
  hash of the exact content reviewed.

Draft files use atomic replacement. A stopped run can be resumed without
parsing or rewriting the whole corpus. The corpus's suffixed printed refs (for
example `1.13.40b`) are supported and remain in reading order.

## 1. Inspect status

No credentials or network access are needed:

```bash
python3 scripts/translate_bhagavata.py status
python3 scripts/translate_bhagavata.py validate
```

## 2. Generate a small batch

Set the API key only in the shell or your secret manager. Never put it in
`env.json`, content JSON, a Git commit, or the mobile app.

```bash
export OPENAI_API_KEY='…'
# Optional; defaults to gpt-4o-mini:
export OPENAI_TRANSLATION_MODEL='gpt-4o-mini'

python3 scripts/translate_bhagavata.py generate --limit 3
```

The default selection is deliberately **three verses**, starting at the first
verse that has neither a complete published translation nor a staged draft.
With the current checked-in drafts, the command above selects `1.2.1–1.2.3`.

Explicit ranges are also supported:

```bash
# Begin Chapter 2 with an explicit range after reviewing Chapter 1:
python3 scripts/translate_bhagavata.py generate \
  --start 1.2.1 --end 1.2.10 --batch-size 3
```

`--batch-size` is 1–5 and requests never cross a chapter boundary. Every batch
must return exactly the requested refs and pass validation before any member of
that batch is written. Existing drafts and published translations are skipped.
Use `--force` only to replace an unapproved draft; approved drafts cannot be
overwritten by generation.

The OpenAI-compatible endpoint can be changed with `OPENAI_BASE_URL` when your
deployment requires it. API retries are limited, and no key or response is
printed by the CLI. Generation records the returned model and response ID when
available.

## 3. Edit and validate the draft

Open the chapter draft JSON and compare every candidate against the source in
the corresponding `verses.json`. Editors may correct pending drafts directly.
The review record will indicate whether the approved text differs from the
original model output.

Minimum editorial checklist:

- every pāda, negation, pronoun, speaker/addressee, and grammatical mood is
  represented;
- English is literal but readable, without imported commentary;
- Malayalam is checked directly against Sanskrit, not merely against English;
- names and technical terms are consistent with the existing pilot;
- glosses follow the IAST wording and cover all meaning-bearing words in order;
- no wording was copied from a modern publication;
- unresolved ambiguity is rejected for further work rather than hidden by an
  invented explanation.

Then run:

```bash
python3 scripts/translate_bhagavata.py validate
```

## 4. Record a human editorial decision

Approve only after actually performing the review above:

```bash
python3 scripts/translate_bhagavata.py review \
  --start 1.1.11 --end 1.1.13 \
  --approve --reviewer 'Editor name' --attest-human-review \
  --notes 'Checked Sanskrit, English, Malayalam, and all glosses.'
```

Or reject with an actionable reason:

```bash
python3 scripts/translate_bhagavata.py review \
  --start 1.1.11 --reject --reviewer 'Editor name' \
  --notes 'Recheck bhūri-karmāṇi and revise the Malayalam rendering.'
```

A rejected draft is not selected as a new untouched verse. After correcting it,
re-review it; or explicitly regenerate it with `generate --start 1.1.11
--force`.

## 5. Promote approved content

Promotion is a dry run unless `--apply` is present:

```bash
python3 scripts/translate_bhagavata.py promote --start 1.1.11 --end 1.1.13
python3 scripts/translate_bhagavata.py promote --start 1.1.11 --end 1.1.13 --apply
```

Alternatively, select every approved but unpublished draft:

```bash
python3 scripts/translate_bhagavata.py promote --all-approved
python3 scripts/translate_bhagavata.py promote --all-approved --apply
```

Promotion updates only the approved `en`, `ml`, `word_meanings`, and translation
provenance metadata. It preserves Sanskrit and other verse metadata, updates
`work.json` coverage counts/scope, and refuses to overwrite a different
published translation. Re-running the same promotion is safe.

## 6. Refresh the final app assets

After checking the content diff, regenerate and test the SQL/database/bundle:

```bash
python3 scripts/localdb.py reset
python3 scripts/ingest.py --apply
python3 scripts/localdb.py test
python3 scripts/export_bundle.py
python3 -m unittest discover -s scripts/tests -v
```

For a normal Flutter environment, also run:

```bash
cd app
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

Commit the reviewed `verses.json`, `work.json`, `content/generated/*.sql`, and
`app/assets/bundles/*.json` changes together. Do not commit API secrets.
Generated SQL and app bundles should be refreshed **only after promotion**;
staged draft JSON is intentionally ignored by ingestion.

## Scaling beyond the sample

Work in chapter-sized, reviewable batches rather than generating all 14,095
remaining verses unattended. A practical cadence is: generate a chapter (or a
short range for long chapters), validate, edit, approve, inspect the diff,
promote, and export. This keeps API cost, review effort, scholarly risk, and Git
diffs bounded while retaining a clear resumable checkpoint.

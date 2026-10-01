# Bhāgavatam translation sourcing assessment

Purpose: record what was verified before any attempt to widen translation
coverage beyond the 1.1.1–1.1.10 pilot. **No content was ingested as a result of
this assessment.** Nothing here authorises generating, paraphrasing or
reconstructing renderings — only importing text that exists in a source whose
licence permits redistribution.

## Current state (measured, not assumed)

`content/bhagavata-purana` holds 14,105 verses across 335 chapters. Non-empty
field counts:

| Field | Verses |
| --- | --- |
| `ref`, `ordinal`, `kind`, `deva`, `iast` | 14,105 |
| `speaker` | 4,592 |
| `metadata` | 3,413 |
| `en`, `ml`, `word_meanings`, `mentions`, `meter` | **10** (1.1.1–1.1.10) |
| `notes_en`, `xrefs` | 4 |

`work.json` already declares this: `metadata.translation_scope = "1.1.1–1.1.10"`,
source licence `CC-BY-SA-4.0` (the Sanskrit base comes from Sanskrit Wikisource),
and the shipped translation/word-meaning editions are `sb-en-dl`, `sb-ml-dl`,
`sb-wm-en`, all cleared under the `dl-cc-by-sa` rights row.

The pipeline was audited end-to-end and is **not** the bottleneck: generated SQL
carries translation rows for 1.1.1–1.1.10 (11 rows incl. the section row), the
canonical bundle carries 10 renderings for each of those verses, the SQLite
importer stores every rendering without filtering by kind, and the reader UI
selects renderings by kind. Verses show no translation because **the source has
none to import.**

## Candidate sources and verdicts

### English — usable candidate, not yet acquired

**Manmatha Nath Dutt (1855–1912), *A prose English translation of Śrīmad
Bhāgavatam*, Calcutta, 1895/1896 (Elysium Press / H. C. Dass), 2 vols.**

- Public-domain status: published 1895–96; translator died 1912 → public domain
  in the United States, and in India under life+60. Wikipedia gives 1855–1912 for
  the translator [1](https://en.wikipedia.org/wiki/Manmatha_Nath_Dutt).
- Full-view scans exist: HathiTrust records full view (University of California)
  for both volumes [2](https://catalog.hathitrust.org/Record/012507010);
  Internet Archive copies `proseenglishtran12dutt` (U. Toronto, 1895, full text
  download) [3](https://archive.org/details/proseenglishtran12dutt) and
  `in.ernet.dli.2015.272582` (Digital Library of India, 1896)
  [4](https://archive.org/details/in.ernet.dli.2015.272582).
- Coverage: covers all twelve cantos, so in principle every remaining verse.
- **Risks that block blind ingestion:** 19th-century OCR is noisy; Dutt's chapter
  and verse numbering may not match this repository's Wikisource vulgate (14,105
  verses); a chapter-level bulk copy would silently mis-attribute renderings. Any
  import must be verse-aligned and spot-verified against the Sanskrit before it
  is written.

Another pre-1929 English option worth the same treatment: Swami Vijnanananda's
version in the *Sacred Books of the Hindus* series (1921–22). Same PD reasoning,
same alignment obligations.

### English — rejected

- **Bhaktivedanta Book Trust (Prabhupāda) Śrīmad Bhāgavatam.** In copyright
  (BBT, 2012 digital edition)
  [1](https://archive.org/details/SrimadBhagavatamEnglish-Sanskrit). BBT is
  already listed as a source in `work.json` but may not be redistributed.
- **Gītā Press (C. L. Goswami) translation.** An Internet Archive upload marks
  the item CC0
  [5](https://archive.org/details/bQvZ_srimad-bhagavata-mahapurana-with-sanskrit-text-and-english-trans.-book-9-to-12-e),
  but the licence is asserted by the *uploader*, not the rights holder; Gītā Press
  holds copyright on a mid-20th-century work. Uploader CC0 is not a provenance
  chain. Rejected until Gītā Press grants a written licence.

### Malayalam — no usable verse-aligned source found

- **S. G. Narayanan Embranthiri / S. V. Parameśvaran,
  *Anvayakrama-Paribhāṣā-sahitam*, 12 vols.** Licensed
  **CC BY-NC-ND 3.0** on the archive item
  [6](https://archive.org/details/Srimad_Bhagavatam_Malayalam_Anvayakrama_Paribhasha_sahitam):
  non-commercial and no-derivatives. Both terms forbid shipping it in this app.
  Rejected.
- **1915 *Sree Mahabhagavatham* (Ezhuthachan)** is marked Public Domain Mark 1.0
  [7](https://archive.org/details/1915_Sree_Mahabhagavatham), but it is an
  abridged Malayalam retelling, not a verse-by-verse rendering of the Sanskrit
  Bhāgavata, so it cannot be aligned to 14,105 verses. Not usable for `ml`.

### Word meanings — no usable source

Verse-by-verse word meanings (`word_meanings`) for the Bhāgavatam exist
essentially only in the BBT edition (in copyright). No public-domain or openly
licensed word-meaning source was found. `word_meanings` therefore stays absent
for every verse outside the existing pilot rather than being reconstructed.

## Why nothing was imported in this pass

Two hard blockers, in addition to licensing:

1. **No outbound network from the working environment.** Direct HTTPS to
   archive.org fails at the TLS handshake, so bulk text acquisition is not
   possible from here; only interactive page fetches are available, which cannot
   move hundreds of megabytes of OCR safely.
2. **Alignment is a correctness gate, not a convenience.** 14,105 verses must be
   matched one-by-one against the repository's vulgate. Importing unaligned text
   would attach renderings to the wrong verses — indistinguishable in effect from
   inventing them, and therefore forbidden.

## Required procedure before any coverage is widened

1. Acquire the Dutt (or equivalent PD) text with its scan identifiers recorded.
2. Parse to per-verse units and align against `content/bhagavata-purana` refs;
   drop any verse that cannot be aligned with certainty (leave the field absent).
3. Add a `sources` row and a `rights` row for the new provenance, and point the
   `sb-en-dl` (or a new) edition at it — mirroring how Gītā records
   `pd-en-swarupananda-1909` with an explicit `PD-US-pre-1923 + PD-India-life+60 +
   PD-EU-life+70` string.
4. Regenerate `content/generated/*.sql` through the existing `scripts/ingest.py`;
   do not hand-edit generated SQL or canonical bundles.
5. Update `translation_scope` in `work.json` and the pilot guard
   `test_pilot_translations_are_not_invented_beyond_1_1_10` **only after** the new
   coverage is verified in the source data.
6. Re-run source → SQL → bundle → SQLite → UI tests
   (`scripts/tests/test_translation_availability.py`,
   `app/test/offline_translation_import_test.dart`, `app/test/verse_card_test.dart`)
   and full CI before any deployment.

## Status

- New content imported: **none**.
- Schema, migrations, bundles, corpus, and the pilot tests: **unchanged**.
- Deployment: **none** (nothing to deploy; licensing and provenance gates are not
  satisfied for any additional source).

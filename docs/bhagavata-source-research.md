# Śrīmad Bhāgavata Purāṇa — source research (this pass)

This note records what was verified, what is **not** cleared to ship, and
whether the app contains a complete 12-skandha corpus or still the **pilot**
(Canto 1, Chapter 1, verses 1.1.1–1.1.10).

**Do not treat this document as a public-domain certificate.** Rights status is
per edition, with named witnesses. Check `content/bhagavata-purana/work.json`
`metadata.complete` and `imported_verse_count` for what is actually shipped.

## What “complete” would mean here

| Axis | Requirement |
|---|---|
| Structure | 12 skandhas (cantos) |
| Chapters | Every adhyāya of the chosen edition, not a round number from a website |
| Text | Devanagari mūla **and** IAST for each verse |
| Provenance | Named, rights-compatible electronic source (or a documented derivation from a verified PD historical edition) |
| Honesty | Actual imported counts from **that** edition; no invented verses; no silent substitution of another recension |

A commonly cited figure is “about 18,000 verses”. That is a traditional
approximation, **not** an import target. Verse totals differ by recension
(vulgate vs. critical). The importer must report the count it actually parsed.

## Chapter inventory (Wikisource, सा.विकिस्रोतः)

Index: [श्रीमद्भागवतपुराणम्](https://sa.wikisource.org/wiki/श्रीमद्भागवतपुराणम्)

Canonical page titles use **`स्कन्धः`** (not the duplicate `स्कन्दः` tree, which
must be ignored) and Devanagari digits.

Reconfirmed **2026-09-21** via `list=allpages&apprefix=श्रीमद्भागवतपुराणम्/`
(`batchcomplete`, 500 titles): 335 canonical adhyāya pages.

| Skandha | Title pattern | Adhyāya pages |
|---|---|---|
| 1–9, 11–12 | `श्रीमद्भागवतपुराणम्/स्कन्धः N/अध्यायः M` | 19, 10, 33, 31, 26, 19, 15, 24, 24, —, 31, 13 |
| 10 | `…/स्कन्धः १०/पूर्वार्धः/अध्यायः` 1–49 **and** `…/उत्तरार्धः/अध्यायः` 50–90 | 90 |
| **Total** | | **335** |

Junk titles excluded: `स्कन्धः १२/अध्यायः/अध्यायः २`, `स्कन्धः १२अध्यायः २`,
`स्कंध १२/अध्यायः ३`. The entire `स्कन्दः` (short-vowel) tree is ignored.

Work page: id **7950**, Wikidata Q682958, last edit 26 Jun 2023 (Puranastudy);
423 subpages (33 redirect / 390 non-redirect), of which 335 are the canonical
adhyāyas above.

Sample check (Canto 1, Chapter 1): Wikisource has **23** numbered verses in that
adhyāya. Expanding that single chapter without the other 334 is not a complete
Bhāgavata.

Parser notes for this edition (fail closed; no invented Sanskrit):

* Verse ends mix `॥ N ॥`, `। N ॥`, `। ०९ ॥` (leading zero), and `॥। N ॥`
  (triple danda, e.g. 1.7).
* Two-line colophons (`इति …` then `प्रथमोऽध्यायः ॥ १ ॥` with avagraha) are
  dropped, not counted as verses. Meter labels like `(अनुष्टुप्)` are stripped.
* **Unnumbered opening śloka:** some chapters omit `॥ १ ॥` on the first mūla
  and start numbering at 2 (confirmed **1.7**, pageid 7996). The unnumbered
  Devanagari immediately before that marker, split on the last `उवाच`, is kept
  as verse 1 of that chapter. Text is from the page; only the missing *number*
  is supplied (`metadata.numbering_note`). If there is no recoverable mūla
  before verse 2, ingest fails closed.
* **Printed-number gaps and duplicates:** Wikisource numbering is not always
  dense (confirmed **1.13**: 35 then 37, no mūla for 36; `॥ ४० ॥` printed
  twice on two different ślokas). `ref` keeps the page number (duplicates get
  a suffix, e.g. `1.13.40b`). `ordinal` is dense reading order for the app /
  SQL pipeline. Gaps are **not** filled with invented Sanskrit. A printed
  number that goes backwards is still a blocker (usually a leaked colophon),
  except split tens/units (`॥ २ ॥ ६ ॥` = 26, confirmed **4.2**).

Text-critical note already in the pilot: 1.1.4 reads `ऋषयः` (Wikisource /
printed vulgate), not GRETIL’s `īśayaḥ`.

## Sources examined

### 1. GRETIL Bhāgavatapurāṇa (`bhp_01u` et al.)

* What it is: a scholarly machine-readable transcription of the vulgate.
* Licence posture: GRETIL terms are **scholarly / non-commercial**. They are
  not a clearance to redistribute the e-text in a commercial app.
* Decision: **collation and validation only. Do not ship.** Do not label the
  GRETIL file itself `public_domain` with `allows_commercial: true`.

### 2. SanskritDocuments / other modern sites

Publicly accessible ≠ rights-cleared. Not used as a redistribution source.

### 3. Motilal / Tagare / BBT / Gita Press translations

Modern translations and Hindi renderings are **not** cleared. Not used.

### 4. sa.wikisource.org `श्रीमद्भागवतपुराणम्`

* Wikimedia terms: **CC BY-SA 4.0** (compatible with this project’s rights
  model as `open_license`, provided attribution is kept). Footer / Terms of Use:
  [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/),
  [Wikimedia Terms of Use](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use).
* This is the only complete electronic candidate identified in this pass that
  is compatible with redistribution **in principle**.
* MediaWiki API (siteinfo 2026-09-21T13:57:04Z): wikiid `sawikisource`,
  MW 1.47.0-wmf.20.
* Fetch: `action=query&prop=revisions&rvprop=content|ids|timestamp|sha1&rvslots=main`
  with `titles=` batches (skandha 10 uses the पूर्वार्धः/उत्तरार्धः paths above).
* Importer: `scripts/generate_bhagavata_corpus.py`.

### 5. Official Sanskrit Wikisource dump

[dumps.wikimedia.org/sawikisource/20260901/](https://dumps.wikimedia.org/sawikisource/20260901/)
is complete (dump date 2026-09-01).
`sawikisource-20260901-pages-articles.xml.bz2` is **221.6 MB** compressed.
That file is binary and too large to ingest through the Arena page-fetch
helper. It remains a valid offline route on a machine that can `wget` it.

### 6. 19th-century printed editions (e.g. Burnouf 1840s)

Public-domain **prints** exist (Internet Archive scans). Turning those into a
verified e-text requires OCR + human collation far beyond this pass. Not used
as a silent substitute.

### 7. Legal backdrop (mūla vs. translation)

Indian courts have treated **Purāṇa mūla** as not subject to copyright in the
way a modern translation is (Delhi High Court, 2023, in the Gita Press / Bhagavad
Gītā context — mūla PD; translations remain protected). That supports treating
the **ancient work** as public domain. It does **not**:

* turn a modern e-text (GRETIL) into a commercial redistribution grant;
* clear any translation, commentary, or recording;
* tell us which recension to publish.

## Retrieval routes tried (2026-09-21)

A rights-compatible complete e-text **exists** (Wikisource, CC BY-SA 4.0).
Whether it is **in this repository** is a separate question (`work.json`
`metadata.complete`).

| Route | Result |
|---|---|
| Local `urllib` / OpenSSL to `sa.wikisource.org`, `dumps.wikimedia.org`, `wikipedia.org`, `archive.org` | TLS handshake EOF / `SSLZeroReturnError` / 0-byte ClientHello. **Do not retry.** |
| Local `curl` | `SSL_ERROR_SYSCALL` at ClientHello to Wikimedia / Cloudflare. GitHub.com `curl` works. |
| Local Node `fetch` | Wikimedia `ECONNRESET`; GitHub `UNABLE_TO_VERIFY_LEAF_SIGNATURE`. |
| Arena `fetch_page` helper | **Works.** Confirmed siteinfo JSON, `list=allpages` (335 canonical titles), `prop=revisions` wikitext (e.g. skandha 2 adhyāya 7), dump **index** HTML. Responses are chunked; reconstructing ~335 chapter bodies through the helper is not a reliable ingest. `action=raw` is rewritten as HTML by the helper — use the API. |
| Official `pages-articles.xml.bz2` (221.6 MB) | Listed via `fetch_page`; **not** ingestible as binary through that helper. |
| `scripts/generate_bhagavata_corpus.py` in this sandbox | SOURCE BLOCKER (same local TLS failure). Does **not** invent verses. |
| GitHub-hosted Actions (`.github/workflows/ingest-bhagavata.yml`) | Remaining bulk path: ubuntu-latest can POST the MediaWiki API, parse 335 chapters, emit SQL + the offline bundle, and upload `bhagavata-wikisource-ingest`. |

Do **not** claim a complete Bhāgavata until that ingest artifact has been
committed and `metadata.complete` is true with 335 chapters. A failed or
absent ingest leaves the 10-verse pilot in place.

When the importer succeeds it must:

1. Parse every canonical अध्याय page (335) and refuse to mark the work complete
   if any skandha is short.
2. Write Devanagari + IAST only from the fetched mūla (IAST via
   `scripts/translit.py`). **Do not invent translations.**
3. Report the **actual** verse count parsed from that edition.
4. Keep Gita Press / GRETIL as numbering/collation witnesses, not as the
   shipped file.
5. Attribute Wikimedia / CC BY-SA 4.0 on the electronic Sanskrit edition.
6. Record source URL, `pageid`, `revid`, timestamp, sha1, retrieval date,
   licence, attribution, and transformation (`WIKISOURCE_MANIFEST.json` plus
   each chapter `_source`).

## What remains in the app until ingest lands

* Pilot: `content/bhagavata-purana/1/1/verses.json` — **10 verses** (1.1.1–1.1.10),
  unless `work.json` says otherwise.
* Bhagavad Gītā: **18 chapters / 700 verses** — unchanged.
* Original English & Malayalam translations on the pilot verses: Dharma Library,
  CC BY-SA 4.0, labelled draft.

Anyone quoting “the complete Bhāgavata is in this build” is wrong until the
importer has been run successfully and the reported counts replace
`metadata.pilot_scope`.

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
  (triple danda, e.g. 1.7). Skandha 5 often numbers with two spaces and **no**
  danda (`पराभवः  १` or a single space, e.g. 5.2 `पर्यगोपायत् १`). The same
  gadya numbering appears in **skandha 12**. **5.24** numbers with dotted
  `॥ ०५.२४.००१ ॥` (sk.adh.verse, leading zeros). **5.25–5.26** switch back to
  classic `॥ N ॥`; bare digits are used only when a chapter has no
  danda-delimited numbers, so leftover `१` cannot rewind 1.1 after verse 23.
  Skandha 7–8 often use `N।` after the pādas
  (`यथा १।`).
* Two-line colophons (`इति …` then `प्रथमोऽध्यायः ॥ १ ॥` or
  `द्वितीयोध्याऽयः ॥ २ ॥` with avagraha; ZWNJ in `श्रीमद्‌भागवत`) are
  dropped, not counted as verses. Text **after** the `इति श्रीमद्भागवत…`
  line is truncated (6.18 repeats the chapter from `१।`). Meter labels like
  `(अनुष्टुप्)` are stripped.
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
  except split tens/units (`॥ २ ॥ ६ ॥` = 26, confirmed **4.2**), a
  dropped units digit (`॥ २ ॥` then `॥ २७ ॥` after 25 = 26, confirmed **4.6**),
  and an extra stray digit (`॥ ८३ ।` then `॥ ९ ॥` after 7 = 8; `॥ ३२३ ।`
  after 32 before 33 is a garbled 32, confirmed **7.4**), and a same-line empty
  close `॥ ॥` with no digits (mūla is on the page; number inferred as last+1
  when the next marker is last+2, confirmed **10.11** / **9.11**).

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

## Remaining printed-number gaps (live Wikisource, 2026-09-22)

Parser closes that keep page mūla (not invented):

* `N ॥` / `N ।` with space between number and danda (6.1.44, 6.8.27)
* number glued to the last akṣara then a danda (8.8.23, 11.23.52)
* `[http://…]` footnote or `(…पाठभेदः)` between number and danda (8.11.16, 9.24.20)
* one-word gloss after the number at EOL (`२६ अभिजित्।`, 10.83.26)

Edition jumps with no mūla on the Wikisource page. Other vulgate witnesses
(Gita Press / BBT / GRETIL) sometimes print a verse here. Those wordings are
**not** CC BY-SA Wikisource. This build **does** ship seven of them as
traditional mūla fills, taken from the cited BBT Vedabase Devanagari after
verification (no BBT English, synonyms, or purports). Wikisource neighbours
were not rewritten. See `docs/bhagavata-completeness.md` and verse
`metadata.source_witness = bbt-vedabase`.

* 1.13.36, 4.1.52 (`/sb/4/1/49-52/`; `/sb/4/1/52/` is 404), 4.21.45, 8.7.5,
  8.16.23, 11.11.13 (line after `॥ १२ ॥` on `/sb/11/11/12-13/`), 11.27.40
  (`/sb/11/27/38-41/`; Vedabase `हवि:` stored as supplied `हविः`).

---

## Additive editions, 2026-10-02: word-by-word, English, Malayalam

Requested additions to the *existing published* corpus (12 cantos / 335
adhyāyas / 14,105 verses), additively only. Nothing below rewrote the Sanskrit
mūla, the IAST, the refs, the ordinals or the structure; `scripts/ingest.py` and
`scripts/export_bundle.py` were only extended where a second edition of the same
kind needed its own verse field.

### 1. Word-by-word meaning — SHIPPED (Digital Corpus of Sanskrit, CC BY 4.0)

* Source: Oliver Hellwig, *Digital Corpus of Sanskrit*, 2010–2021 —
  `github.com/OliverHellwig/sanskrit`. Licence per `dcs/data/readme.md`:
  “The data of the DCS and any data in child directories are licensed under the
  Creative Common BY 4.0 (CC BY 4.0) license.”
* Data: `dcs/data/conllu/files/Bhāgavatapurāṇa/*.conllu` (437 files) joined to
  `dcs/data/conllu/lookup/dictionary.csv` (180,455 lemmas). Each CoNLL-U
  sentence is one pāda; `# sent_counter` is the verse number and
  `# sent_subcounter` the pāda, so the parse is *verse-aligned* by construction —
  no guessing is involved.
* Result: **5,007 of 14,105 verses (35.5%), 117 of 335 adhyāyas, 77,350 glossed
  words.** Cantos 5, 6, 7, 9 and 12 have no DCS parse at all; those chapters keep
  whatever they already had. Measured in
  `docs/dcs-word-meanings-coverage.json`.
* Shipped as edition `sb-wm-dcs-en` (`kind: word_meanings`, `en`/`Latn`, rights
  `dcs-cc-by-4.0` = `open_license`, CC BY 4.0), stored in a **new** verse field
  `wm_dcs` so it cannot overwrite the existing `sb-wm-en` editorial glosses.
  `scripts/ingest.py` now iterates every `word_meanings` edition off its own
  `content_field`.
* **Caveat, stated in the edition description:** these are *dictionary* senses
  (first three, capped at 140 characters), not contextual translations. For
  1.1.1, `brahma` yields “pious effusion or utterance; outpouring of the heart
  in worshipping the gods; prayer”, not the contextual “the Veda”.

### 2. English translation — M. N. Dutt 1895: BLOCKED (alignment, not rights)

* Verified public domain. Three Internet Archive scans were located and together
  cover **all twelve books**:
  * `proseenglishtran12dutt` — *A prose English translation of Shrimadbhagabatam*,
    H. C. Dass, Elysium Press, Calcutta, 1895. Books I–II. Cleanest OCR.
  * `india.history.resource.40625` — Books VII–XII, 1895. Heavily degraded OCR.
  * `in.ernet.dli.2015.272582` — *Shrimad Bhagwatam*, 1896, 744 pp. Books I–VII,
    with a footnote apparatus.
* **Blocker — Dutt's own introduction:** “I have not considered it necessary to
  put in the numbers of the Slokas.” The translation is continuous, unnumbered
  prose. Measured against the corpus, sentence counts diverge wildly from verse
  counts (1.1: 101 sentences for 23 verses; 1.9: 147 for 49; 1.13: 115 for 60),
  single paragraphs span up to 30+ ślokas, and single sentences merge several.
* **What was tried.** `scripts/ingest_dutt_translation.py` parses the scans into
  (skandha, adhyāya) with OCR-tolerant BOOK/CHAPTER heading detection, splits
  each adhyāya into sentences, and aligns them to the corpus refs with a monotone
  Viterbi pass that maximises transliteration + DCS-dictionary evidence, gated
  on both an absolute and a relative confidence bar. Even at a deliberately lax
  threshold (accept 0.10, margin 0.02) it reaches only **285 of 14,105 verses
  (2.0%)**, and 256 of 335 adhyāyas never parse cleanly at all.
* **Verdict.** A trustworthy per-verse mapping is not achievable from this
  source. Ingesting `en_dutt` would misattribute prose to the wrong verse, which
  this project does not do. Dutt is therefore registered as a verified
  public-domain *source* row (with the provenance above and this verdict) and
  **no edition is shipped from it**. The measurement stays reproducible:
  `.github/workflows/dutt-translation.yml` regenerates
  `docs/dutt-translation-coverage.json` on every push.

### 3. Malayalam translation — BLOCKED (rights)

* The only verse-aligned Malayalam translation located —
  *Śrīmad Bhāgavatam with anvayakrama and paribhāṣā*,
  `archive.org/details/Srimad_Bhagavatam_Malayalam_Anvayakrama_Paribhasha_sahitam`
  — carries **“Attribution-Noncommercial-No Derivative Works 3.0 Creative
  Commons License”**. Both the non-commercial and the no-derivatives terms
  conflict with `docs/rights-policy.md`, so it cannot be served.
* Malayalam Wikisource has no usable Bhagavata text (prefix `ഭാഗവत` returns one
  irrelevant page).
* The existing Dharma Library Malayalam draft on 1.1.1–1.1.10 is unchanged and no
  Malayalam text was invented.

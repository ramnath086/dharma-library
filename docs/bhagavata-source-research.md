# Śrīmad Bhāgavata Purāṇa — source research (this pass)

This note records what was verified, what is **not** cleared to ship, and why
the app still contains the **pilot** (Canto 1, Chapter 1, verses 1.1.1–1.1.10)
rather than a complete 12-skandha corpus.

**Do not treat this document as a public-domain certificate.** Rights status is
per edition, with named witnesses.

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
must be ignored) and Devanagari digits:

`श्रीमद्भागवतपुराणम्/स्कन्धः N/अध्यायः M`

Skandha 10 is split पूर्वार्धः (1–49) / उत्तरार्धः (50–90) in the printed
tradition; on Wikisource the adhyāya pages still number 1–90.

| Skandha | Adhyāya pages (स्कन्धः spelling) |
|---|---|
| 1 | 19 |
| 2 | 10 |
| 3 | 33 |
| 4 | 31 |
| 5 | 26 |
| 6 | 19 |
| 7 | 15 |
| 8 | 24 |
| 9 | 24 |
| 10 | 90 |
| 11 | 31 |
| 12 | 13 |
| **Total** | **335 chapter pages** |

Junk titles spotted and excluded: `स्कन्धः १२/अध्यायः/अध्यायः २`, `स्कन्धः १२अध्यायः २`.

Verse totals are **unknown until each page is parsed**. Do not invent them.

Sample check (Canto 1, Chapter 1): Wikisource has **23** numbered verses in that
adhyāya. The app currently ships **10** (the existing pilot). Expanding that
single chapter without the other 334 would still not be a complete Bhāgavata.

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
  model as `open_license`, provided attribution is kept).
* This is the only complete electronic candidate identified in this pass that
  is compatible with redistribution **in principle**.
* MediaWiki API: `action=query&prop=revisions&rvprop=content&rvslots=main&format=json&formatversion=2`
  with `generator=allpages` / `gapprefix=श्रीमद्भागवतपुराणम्/स्कन्धः N/अध्यायः`.

### 5. 19th-century printed editions (e.g. Burnouf 1840s)

Public-domain **prints** exist (Internet Archive scans). Turning those into a
verified e-text requires OCR + human collation far beyond this pass. Not used
as a silent substitute.

### 6. Legal backdrop (mūla vs. translation)

Indian courts have treated **Purāṇa mūla** as not subject to copyright in the
way a modern translation is (Delhi High Court, 2023, in the Gita Press / Bhagavad
Gītā context — mūla PD; translations remain protected). That supports treating
the **ancient work** as public domain. It does **not**:

* turn a modern e-text (GRETIL) into a commercial redistribution grant;
* clear any translation, commentary, or recording;
* tell us which recension to publish.

## SOURCE BLOCKER (this environment)

A rights-compatible complete e-text **exists** (Wikisource, CC BY-SA 4.0).

This sandbox **cannot bulk-download it**:

* `urllib` / OpenSSL: `SSLZeroReturnError` / handshake EOF to Wikimedia
* `curl` / `openssl s_client`: `SSL_ERROR_SYSCALL` at ClientHello
* Node `fetch`: `ECONNRESET` before TLS is established
* No HTTP(S) proxy is configured
* The only working outbound HTTPS helper is a page-fetch tool that cannot
  persist ~335 chapters × multi-chunk API responses as a corpus

Reconstructing 335 chapters through that helper would be incomplete, unreviewed,
and would still risk silently shipping a partial corpus as “complete”.

**Therefore this pass does not ingest a complete Bhāgavata.** It keeps the
existing 10-verse pilot, corrects provenance so GRETIL is not claimed as a
cleared commercial source, and leaves a ready importer
(`scripts/generate_bhagavata_corpus.py`) for an environment that can reach
`sa.wikisource.org`.

When that importer succeeds it must:

1. Parse every canonical अध्याय page (335) and refuse to mark the work complete
   if any skandha is short.
2. Write Devanagari + IAST only from the fetched mūla (IAST via
   `scripts/translit.py`). **Do not invent translations.**
3. Report the **actual** verse count parsed from that edition.
4. Keep Gita Press / GRETIL as numbering/collation witnesses, not as the
   shipped file.
5. Attribute Wikimedia / CC BY-SA 4.0 on the electronic Sanskrit edition.

## What remains in the app

* Pilot: `content/bhagavata-purana/1/1/verses.json` — **10 verses** (1.1.1–1.1.10).
* Bhagavad Gītā: **18 chapters / 700 verses** — unchanged.
* Original English & Malayalam translations on the pilot verses: Dharma Library,
  CC BY-SA 4.0, labelled draft.

Anyone quoting “the complete Bhāgavata is in this build” is wrong until the
importer has been run successfully and the reported counts replace
`metadata.pilot_scope`.

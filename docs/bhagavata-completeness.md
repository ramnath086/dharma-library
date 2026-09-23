# Bhāgavata completeness vs sa.wikisource.org

Edition: Sanskrit Wikisource श्रीमद्भागवतपुराणम्, **CC BY-SA 4.0**.
Retrieved 2026-09-22T17:52:13Z.
GRETIL / Gita Press were collation witnesses only and are **not shipped**.

Three different counts must not be conflated:

| Axis | Count | Meaning |
|---|---|---|
| Traditional grantha | ~18,000 | Approximation; **not** an import target |
| This Wikisource parse | **14098** | Numbered units on sa.wikisource.org (`WIKISOURCE_MANIFEST.json`) |
| Shipped mūla | **14105** | 14098 Wikisource + 7 BBT-numbered fills (traditional mūla only) |

- Adhyāyas: **335 / 335**
- Unique refs: **14105**; duplicate refs: 0; empty mūla: 0
- Letter-suffix refs (same printed N twice): **10**
- Remaining printed-number gaps: **0**
- Gītā: **18 / 700** (unchanged)

Machine-readable chapter inventory: `docs/bhagavata-completeness-audit.json`.

| Skandha | Chapters | Source units |
|---|---|---|
| 1 | 19 | 812 |
| 2 | 10 | 391 |
| 3 | 33 | 1411 |
| 4 | 31 | 1451 |
| 5 | 26 | 662 |
| 6 | 19 | 851 |
| 7 | 15 | 751 |
| 8 | 24 | 936 |
| 9 | 24 | 964 |
| 10 | 90 | 3944 |
| 11 | 31 | 1368 |
| 12 | 13 | 564 |

## Printed-number fills (not invented)

Live Wikisource has no `॥ N ॥` and no mūla for these numbers.
Devanagari was inserted from the cited BBT Vedabase page after verification.
Wikisource neighbours were not rewritten. BBT English / synonyms / purports are not shipped.
BBT ASCII colon-as-visarga is stored as U+0903 `ः`.

| Ref | Vedabase URL | Note |
|---|---|---|
| 1.13.36 | https://vedabase.io/en/library/sb/1/13/36/ | Devanagari matches supplied |
| 4.1.52 | https://vedabase.io/en/library/sb/4/1/49-52/ | `/sb/4/1/52/` is 404; combined 49–52 prints `॥ ५२ ॥` |
| 4.21.45 | https://vedabase.io/en/library/sb/4/21/45/ | Devanagari matches supplied |
| 8.7.5 | https://vedabase.io/en/library/sb/8/7/5/ | Devanagari matches supplied |
| 8.16.23 | https://vedabase.io/en/library/sb/8/16/23/ | Devanagari matches supplied |
| 11.11.13 | https://vedabase.io/en/library/sb/11/11/12-13/ | Source 13 is the line after `॥ १२ ॥` |
| 11.27.40 | https://vedabase.io/en/library/sb/11/27/38-41/ | Vedabase prints `हवि:`; stored `हविः` as supplied |

Fill vs neighbour same-body (BBT number overlay, neighbours unchanged):
`1.13.35`≈`1.13.36`, `8.7.5`≈`8.7.6`, `11.27.40`≈`11.27.41`.

## Suffix refs

`1.13.40b`, `4.14.13b`, `4.22.62b`, `4.23.35b`, `4.24.11b`, `4.29.77b`, `7.4.32b`, `8.6.7b`, `8.16.39b`, `11.27.41b`

## Source-page markup leftovers (not numbering gaps)

These units still contain Wikisource editorial markup or a Latin leak from the
committed parse. Sanskrit was **not** rewritten in this pass (no invented mūla;
`strip_wiki` now drops `thumb|` / ASCII-only / `तुलनीय` lines for future ingest).

| Ref | Leftover |
|---|---|
| 1.13.1 | Latin `t` in `ज्ञात्वागाt` |
| 2.2.25 | English Madhva-school note + bracketed extra ślokas |
| 3.12.47 | `thumb\|400px\|` |
| 4.26.2 | `[http://…]` footnote |
| 4.26.16 | `तुलनीय` + wiki link |
| 5.1.31 | `thumb\|` |
| 5.1.32 | `तुलनीय` + wiki link |
| 8.8.1 | `thumb\|` + `अथाष्टमोऽध्यायः` |
| 8.8.3 | `[http://…]` |
| 8.11.17 | `[http://…]` |

Vulgate repeats of the same śloka at different refs (not parser errors):
`1.8.22`/`10.59.26`, `10.11.59`/`10.14.61`, `10.26.21`/`10.8.18`,
`10.48.31`/`10.84.11`, `10.89.55`/`10.89.56`, `11.28.13`/`3.27.4`/`4.29.73`.

Gītā remains 18 chapters / 700 verses. Do not merge until Flutter CI on this SHA is green.

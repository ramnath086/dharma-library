# Bhāgavata completeness vs sa.wikisource.org

Edition: Sanskrit Wikisource श्रीमद्भागवतपुराणम्, CC BY-SA 4.0.
Retrieved with the last complete ingest. GRETIL was not shipped.
Traditional ~18,000 is not an import target.

- Chapters on disk: **335 / 335**
- Numbered verses parsed: **14091** (unique refs 14091)
- Duplicate refs: 0
- Empty mūla: 0
- Letter-suffix refs (duplicate printed numbers): 10
- Printed-number gaps with no mūla on the page: **14**

| Skandha | Chapters | Verses |
|---|---|---|
| 1 | 19 | 811 |
| 2 | 10 | 391 |
| 3 | 33 | 1411 |
| 4 | 31 | 1449 |
| 5 | 26 | 662 |
| 6 | 19 | 849 |
| 7 | 15 | 751 |
| 8 | 24 | 932 |
| 9 | 24 | 963 |
| 10 | 90 | 3943 |
| 11 | 31 | 1365 |
| 12 | 13 | 564 |

## Printed gaps (edition numbering; not invented)

These numbers are absent as `॥ N ॥` (or equivalent) on the Wikisource
page. The parser records the skip and does not fabricate Sanskrit.
Live checks: **1.13.36**, **4.1.52**, **8.7.5**, **11.27.40** are jumps
on the page (35→37, 51→53, 4→6, 39→41).

| Chapter | Skipped printed N | Imported verses | Last printed |
|---|---|---|---|
| 1.13 | 36 | 59 | — |
| 4.1 | 52 | 65 | — |
| 4.21 | 45 | 52 | — |
| 6.1 | 44 | 67 | — |
| 6.8 | 27 | 41 | — |
| 8.7 | 5 | 46 | — |
| 8.8 | 23 | 46 | — |
| 8.11 | 16 | 47 | — |
| 8.16 | 23 | 62 | — |
| 9.24 | 20 | 66 | — |
| 10.83 | 26 | 42 | — |
| 11.11 | 13 | 48 | — |
| 11.23 | 52 | 60 | — |
| 11.27 | 40 | 55 | — |

## Suffix refs

`1.13.40b`, `4.14.13b`, `4.22.62b`, `4.23.35b`, `4.24.11b`, `4.29.77b`, `7.4.32b`, `8.6.7b`, `8.16.39b`, `11.27.41b`

Do not merge until Flutter CI on this corpus SHA is actually green.

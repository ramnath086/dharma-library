# Bhāgavata Purāṇa — what is in this folder

**Shipped scope:** complete Śrīmad Bhāgavata Purāṇa mūla from
[sa.wikisource.org](https://sa.wikisource.org/wiki/श्रीमद्भागवतपुराणम्)
(CC BY SA 4.0).

| Axis | This ingest |
|---|---|
| Retrieved | 2026-09-22T16:34:15Z |
| Licence | [CC-BY-SA-4.0](https://creativecommons.org/licenses/by-sa/4.0/) |
| Attribution | Sanskrit Wikisource contributors |
| Skandhas | 12 |
| Adhyāyas parsed | 335 (expected 335) |
| Numbered verses parsed | **14082** (this edition; not a traditional 18,000 target) |
| Translations | original Dharma Library drafts on **1.1.1–1.1.10** only; nothing invented for the rest |
| GRETIL | collation/validation only; **not shipped** |

| Skandha | Chapters | Verses |
|---|---|---|
| 1 | 19 | 810 |
| 2 | 10 | 391 |
| 3 | 33 | 1411 |
| 4 | 31 | 1449 |
| 5 | 26 | 656 |
| 6 | 19 | 849 |
| 7 | 15 | 751 |
| 8 | 24 | 932 |
| 9 | 24 | 963 |
| 10 | 90 | 3941 |
| 11 | 31 | 1365 |
| 12 | 13 | 564 |

Transformation: MediaWiki wikitext → strip templates/links → split on `॥ N ॥` →
IAST via `scripts/translit.py`. Per-page `pageid` / `revid` / `sha1` are in
`WIKISOURCE_MANIFEST.json` and each chapter's `verses.json` `_source` block.

Gita Press numbering was used only as a collation witness. Do not drop the
BY-SA attribution when redistributing this e-text.

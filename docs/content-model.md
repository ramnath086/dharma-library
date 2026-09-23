# Content model

| Entity | Purpose | Key fields |
|---|---|---|
| `works` | A scripture (Bhāgavata Purāṇa) | slug, titles, original language/script, `structure` (level names) |
| `sections` | Hierarchy (canto → chapter …), self-referential | work, parent, level, ordinal, ref `1.1` |
| `verses` | Leaf unit, language-neutral | section, ordinal, ref `1.1.4`, kind, meter, speaker, `metadata` (e.g. editorial audio cues) |
| `languages` / `scripts` | BCP-47 / ISO 15924 reference | `sa` `en` `ml` … / `Deva` `Latn` `Mlym` … |
| `sources` | Bibliographic provenance | title, publisher, year, url, archive_url |
| `rights` | **Mandatory** legal status per edition | status, license, attribution_text, permission doc, expiry |
| `editions` | A coherent rendering set of a work | kind (base_text / transliteration / translation / word_meanings / commentary / summary / audio), language, script, source, **rights**, derived_from, is_machine |
| `verse_contents` | Text of one verse in one edition | body, body_html, word_meanings JSON, footnotes JSON, folded (search) |
| `section_contents` | Chapter titles / intros per edition | title, intro, summary |
| `cross_references` | verse ↔ verse | kind (parallel, quotation, see_also …), note |
| `people` / `places` / `topics` / `stories` | Knowledge graph | slugs, IAST + Devanagari names, descriptions, geo, verse ranges |
| `entity_names` | Localised names for graph entities | language, script, name |
| `verse_mentions` | entity ↔ verse with role | role (speaker/addressee/subject/setting/theme), surface_form |
| `entity_relations` | entity ↔ entity | relation (son_of, disciple_of, located_in, about …) |
| `audio_tracks` / `audio_segments` | Recordings + verse timing | storage path or external URL, start/end ms |
| `bookmarks` / `reading_progress` / `verse_reads` | User data | owner-only RLS |
| `content_embeddings` | pgvector for AI retrieval | per verse_content, model |
| `qa_sessions` / `qa_messages` | AI Q&A log with citations | grounded flag, feedback |
| `audit_log` | Every content change with actor | admin-only |

Commentaries are editions of kind `commentary` (e.g. Śrīdhara's *Bhāvārtha-dīpikā*
when a cleared source exists) — no separate table is needed.

Editorial audio cues live on `verses.metadata.audio` (`important`, `cue_asset`,
`label`). They are a small named set in content JSON, never an automatic
classification of the corpus. `get_section_verses` includes `metadata` so
offline bundles carry the cue.

## Content files
`content/<work>/work.json` declares sources, rights and editions.
`content/<work>/<canto>/<chapter>/verses.json` holds verses. `scripts/ingest.py`
validates (rights present, refs match, ordinals dense, base text non-empty),
generates machine transliterations for Indic-script editions, and emits
idempotent SQL. Editions whose rights are `pending`/`restricted` are forced to
`draft`.

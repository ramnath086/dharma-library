# Contributing

* **Text accuracy first.** Sanskrit must match a named, rights-compatible
  witness; note variants. Never claim public domain without evidence. GRETIL
  is scholarly/non-commercial — collation only, never the shipped file.
  Translations must be your own work (or cleared) and are released under
  CC BY-SA 4.0. Never paste from copyrighted translations. A complete
  Bhāgavata ingest is `python3 scripts/generate_bhagavata_corpus.py` (Wikisource
  CC BY-SA 4.0) or the `Ingest Bhāgavata from Wikisource` GitHub Action. If that
  cannot run, leave the 10-verse pilot and do not invent verses. See
  `docs/bhagavata-source-research.md`.
* Content lives in `content/**/*.json`; never edit `content/generated/`.
* Run before pushing:
  ```bash
  python3 scripts/localdb.py reset && python3 scripts/ingest.py --apply && python3 scripts/localdb.py test
  python3 -m unittest discover -s scripts/tests
  python3 scripts/export_bundle.py && python3 scripts/dart_lint_lite.py
  cd app && flutter analyze && flutter test
  ```
* No secrets in git. `.env`, `env.json`, keystores and `key.properties` are ignored.

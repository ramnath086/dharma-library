# Contributing

* **Text accuracy first.** Sanskrit must match a named public-domain witness;
  note variants. Translations must be your own work (or cleared) and are
  released under CC BY-SA 4.0. Never paste from copyrighted translations.
* Content lives in `content/**/*.json`; never edit `content/generated/`.
* Run before pushing:
  ```bash
  python3 scripts/localdb.py reset && python3 scripts/ingest.py --apply && python3 scripts/localdb.py test
  python3 -m unittest discover -s scripts/tests
  python3 scripts/export_bundle.py && python3 scripts/dart_lint_lite.py
  cd app && flutter analyze && flutter test
  ```
* No secrets in git. `.env`, `env.json`, keystores and `key.properties` are ignored.

# Bhāgavata Purāṇa — what is in this folder

**Shipped scope:** Canto 1, Chapter 1, verses **1.1.1–1.1.10** (pilot).

This is **not** a complete Śrīmad Bhāgavata Purāṇa. A complete electronic
candidate (sa.wikisource.org, CC BY-SA 4.0, 12 skandhas / 335 adhyāya pages)
was identified but could not be ingested in the environment that produced this
tree. See `docs/bhagavata-source-research.md`.

To ingest later (from a machine that can reach Wikimedia):

```
python3 scripts/generate_bhagavata_corpus.py
python3 scripts/ingest.py
```

GRETIL may be used to *collate* readings. It must not be copied into this
folder as the shipped mūla.

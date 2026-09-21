# Bhāgavata Purāṇa — what is in this folder

**Shipped scope:** Canto 1, Chapter 1, verses **1.1.1–1.1.10** (pilot), unless
`work.json` `metadata.complete` is true.

This is **not** a complete Śrīmad Bhāgavata Purāṇa until the Wikisource ingest
has parsed all 12 skandhas / 335 adhyāyas. A rights-compatible electronic
candidate (sa.wikisource.org, CC BY-SA 4.0) is identified; see
`docs/bhagavata-source-research.md` for routes tried (local TLS dead;
`fetch_page` reaches the API; GitHub Actions is the bulk download).

To ingest (from a machine that can reach Wikimedia, including GitHub-hosted
runners via `.github/workflows/ingest-bhagavata.yml`):

```
python3 scripts/generate_bhagavata_corpus.py
python3 scripts/ingest.py
```

GRETIL may be used to *collate* readings. It must not be copied into this
folder as the shipped mūla.

# Rights & sourcing policy

1. **Every edition has a `rights` row.** The FK is `not null`; ingestion refuses
   editions without one.
2. **Only cleared rights are served.** `rights_is_cleared()` ⇒ status in
   {public_domain, open_license, permission_granted, original} and not expired.
   RLS uses it for editions, verse_contents, section_contents, audio. Search,
   the AI retriever, the offline bundle and the CMS "publish" action all inherit
   the same gate.
3. **`permission_granted` requires a document.** DB constraint: a permission
   document URL (private `rights-documents` bucket) must be attached; expiry
   dates are honoured automatically.
4. **Attribution is displayed.** `attribution_text` is shown in the reader
   (per rendering label + "Source & rights" sheet) and included in shared text.
5. **No copyrighted translations or recordings** are ingested without written
   permission. Popular modern translations (e.g. BBT/Prabhupāda, Motilal
   Banarsidass editions, Gita Press Hindi) are **not** included. Publicly
   accessible is not the same as cleared. The Bhāgavata **pilot** (1.1.1–1.1.10)
   uses:
   * Sanskrit mūla — ancient work treated as public-domain mūla (Delhi High
     Court, 2023, on Purāṇa mūla). The **electronic edition** shipped here
     follows sa.wikisource.org under **CC BY-SA 4.0** (`open_license`). GRETIL
     is a scholarly/non-commercial witness used for collation only and is **not
     redistributed**. Gita Press numbering is a collation reference; its Hindi
     is not used. Text-critical notes are recorded per verse (e.g. 1.1.4
     `ṛṣayaḥ`, not GRETIL `īśayaḥ`).
   * English & Malayalam translations, word meanings, graph annotations —
     original Dharma Library work, CC BY-SA 4.0, labelled *draft — pending
     scholarly review*.
   * Indic-script renderings — deterministic conversion of that mūla (CC0 for
     the conversion; the underlying text keeps its edition licence), labelled
     *automatic script conversion*; Tamil/Gurmukhi flagged lossy.
   A complete 12-skandha Bhāgavata is **not** in this tree until
   `scripts/generate_bhagavata_corpus.py` has been run successfully. See
   `docs/bhagavata-source-research.md`.
6. **Audio** follows the same rule: a recitation track belongs to an `audio`
   edition with rights. Recitations should be commissioned/recorded under
   CC BY-SA or with signed permission; the private bucket + signed URLs prevent
   hot-linking. Short launch/śloka **cues** shipped in `app/assets/audio/` are
   original synthesized PCM (not recitations, not commercial samples) and are
   preference-gated; launch autoplay defaults to OFF. “Important śloka” cues
   are editorial metadata on a small named set — never an AI ranking of the
   corpus.
7. **Never fabricate.** No verse, variant reading, commentary or source may be
   invented. Uncertain readings go in `notes` with the witnesses named. Never
   claim public-domain status without evidence; never silently normalise
   variants.

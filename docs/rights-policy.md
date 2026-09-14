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
   Banarsidass editions, Gita Press Hindi) are **not** included. The pilot uses:
   * Sanskrit mūla — public domain; collated from GRETIL and sa.wikisource
     against the Gita Press vulgate numbering (text-critical notes recorded per
     verse, e.g. 1.1.4 `ṛṣayaḥ`).
   * English & Malayalam translations, word meanings, graph annotations —
     original Dharma Library work, CC BY-SA 4.0, labelled *draft — pending
     scholarly review*.
   * Indic-script renderings — deterministic conversion of the public-domain
     text (CC0), labelled *automatic script conversion*; Tamil/Gurmukhi flagged lossy.
6. **Audio** follows the same rule: a track belongs to an `audio` edition with
   rights. Recitations should be commissioned/recorded under CC BY-SA or with
   signed permission; the private bucket + signed URLs prevent hot-linking.
7. **Never fabricate.** No verse, variant reading, commentary or source may be
   invented. Uncertain readings go in `notes` with the witnesses named.

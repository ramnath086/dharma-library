# Bounded offline startup import

## Root cause

The previous startup path loaded a 51 MB Bhāgavata asset using
`rootBundle.loadString` (cached by `CachingAssetBundle`), decoded the entire JSON
object graph before checking readiness, and assembled a single sqflite batch
with 98,765 search inserts plus chapter and verse cache JSON. Android must decode
the whole batch's platform-channel message into Java objects too. This creates
both Dart and Android heap amplification; raising `largeHeap` is not a fix.

## Import contract

- Run `python3 scripts/prepare_offline_assets.py` before Flutter test/run/build.
  CI and the release build script do this automatically. Output lives in ignored
  `app/assets/offline_parts/*.json`; canonical bundles remain read-only.
- Each generated chapter is losslessly serialized from the canonical bundle.
  The largest current asset is 371,839 bytes. Generation rejects assets over
  1 MiB. Existing canonical bundle assets remain packaged for the established
  corpus audit, but runtime import never loads them.
- Warm startup loads only the small generated catalogue, checks source hash,
  generation, index version, expected rendering count and actual SQLite count.
  Old installations lacking the hash perform a one-time bounded rebuild.
- Cold startup/rebuild loads metadata and then one chapter at a time, always
  with `cache: false`. No corpus-wide Dart list or parallel chapter prefetch.
- SQLite batches are capped at 128 operations and a conservative 2 MiB encoded
  payload budget. Chapter boundaries also flush the current batch. Per-verse
  reader payloads retain the existing format, but no whole-corpus batch of
  their encoded copies is retained.
- All flushed batches run inside one work transaction. Flush is **not** an
  outer commit: SQLite's disk-backed rollback journal preserves all-or-nothing
  index/cache/catalogue readiness. Counts are checked before publishing the
  marker; failed imports roll back, preserving any previously ready work.
- Full persistent search remains available before the normal app starts:
  Bhāgavata 335 chapters / 14,105 verses / 98,765 renderings;
  Gītā 18 chapters / 700 verses / 6,300 renderings. Search/UI semantics and
  existing rendering/provenance fields are unchanged.

## Regression coverage

- Actual full-corpus startup path: bounded reads, caching disabled, 353 chapter
  reads, complete verse/index counts, both works searchable including late refs.
- Reopen/warm launch loads no chapter assets; corrupt indexes rebuild.
- Failure after a flushed chapter publishes no partial cache/index. Retry works.
- Failed update retains previous ready data and can retry after reopening.
- Verse/section/rendering count mismatches and duplicate index keys fail closed.
- Batch operation and byte limits are tested independently.
- Python checks exact reconstructed object equality (including all scripture,
  translations, word meanings, rights and provenance), deterministic generation,
  oversize rejection, and archive verifier corruption detection.
- CI checks every generated chapter's exact bytes inside both APK and AAB against
  fresh derivation from canonical bundles, in addition to existing corpus and
  release signing gates.

## Device checks still required

No Android device/emulator or Flutter SDK is available in the coding sandbox.
CI tests do not establish an Android peak heap measurement. Validate the signed
APK on the reported OnePlus Nord 5 with the normal 256 MiB growth limit:

1. Fresh app data, airplane mode: launch through completed first import; open
   early/late chapters of both works and search refs `12.13.23` and `18.66`.
2. Force-stop/relaunch: complete offline search without a fresh import.
3. Interrupt a fresh import and relaunch: rollback/rebuild, no partial readiness.
4. Capture logcat and `adb shell dumpsys meminfo <application-id>` during cold
   import and warm launch; confirm no OOM and record peak memory/startup latency.

Cold import still occurs before the normal reader UI. This change bounds memory;
it does not claim measured startup speed or a measured device heap ceiling.

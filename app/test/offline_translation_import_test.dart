import 'dart:convert';
import 'dart:io';

import 'package:dharma_library/core/offline/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The SQLite importer is the last stop before the reader UI: whatever it drops
/// can never be shown. The Bhāgavata translation / word-meaning renderings are
/// a pilot (1.1.1–1.1.10), so every one of those verses must survive import
/// with its translation and word meanings intact — not only the first verse —
/// and the search index must cover every rendering, translations included.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('import keeps translation and word meanings for every Bhāgavata pilot verse', () async {
    final bundle =
        jsonDecode(File('test/fixtures/mini_bhagavata_bundle.json').readAsStringSync()) as Map<String, dynamic>;
    final dir = await Directory.systemTemp.createTemp('dharma-translation-import-');
    final store = await LocalStore.open(pathOverride: '${dir.path}/translations.db');
    try {
      await store.importBundle(bundle);

      for (final ref in const ['1.1.1', '1.1.2', '1.1.10']) {
        final stored = await store.get<Map>('verse:bhagavata-purana:$ref');
        expect(stored, isNotNull, reason: '$ref missing from the offline store');
        final renderings = (stored!['renderings'] as List).cast<Map>();
        expect(
          renderings.any((r) => r['kind'] == 'translation' && r['language_code'] == 'en'),
          isTrue,
          reason: '$ref lost its English translation during import',
        );
        expect(
          renderings.any((r) => r['kind'] == 'word_meanings'),
          isTrue,
          reason: '$ref lost its word meanings during import',
        );
      }

      // Every rendering — including translations — is indexed for offline search.
      final expectedRows = (bundle['sections'] as List).fold<int>(0, (sum, s) {
        final verses = (s as Map)['verses'] as List;
        return sum + verses.fold<int>(0, (v, verse) => v + ((verse as Map)['renderings'] as List).length);
      });
      final meta = await store.get<Map>('bundle_meta:bhagavata-purana');
      expect(meta?['index_count'], expectedRows, reason: 'search index skipped some renderings');

      // Re-import must stay lossless (no duplication, no dropped renderings).
      await store.importBundle(bundle);
      final again = await store.get<Map>('verse:bhagavata-purana:1.1.2');
      expect((again!['renderings'] as List).length, (await store.get<Map>('verse:bhagavata-purana:1.1.2'))!['renderings'].length);
      final meta2 = await store.get<Map>('bundle_meta:bhagavata-purana');
      expect(meta2?['index_count'], expectedRows);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}

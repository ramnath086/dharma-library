import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dharma_library/core/offline/bounded_batch.dart';
import 'package:dharma_library/core/offline/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/recording_assets.dart';

class _Executor extends Mock implements DatabaseExecutor {}
class _Batch extends Mock implements Batch {}

void main() {
  const slug = 'bhagavata-purana';
  const catalogPath = 'assets/offline_parts/catalog.json';
  const metadataPath = 'assets/offline_parts/metadata.json';
  const firstPath = 'assets/offline_parts/first.json';
  const secondPath = 'assets/offline_parts/second.json';
  late Map<String, dynamic> bundle;
  late Map<String, dynamic> work;
  late Map<String, Uint8List> files;
  late LocalStore store;
  late Directory dir;

  Uint8List bytes(Object value) => Uint8List.fromList(utf8.encode(jsonEncode(value)));
  void updateCatalogue() => files[catalogPath] = bytes({'format_version': 1, 'works': [work]});

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline-startup-');
    store = await LocalStore.open(pathOverride: '${dir.path}/cache.db');
    bundle = jsonDecode(File('test/fixtures/mini_bhagavata_bundle.json').readAsStringSync()) as Map<String, dynamic>;
    final section = (bundle.remove('sections') as List).single as Map;
    final verses = section['verses'] as List;
    files = {
      metadataPath: bytes(bundle),
      firstPath: bytes({...section, 'verses': verses.take(5).toList()}),
      secondPath: bytes({...section, 'section': {...section['section'] as Map, 'id': 'second'}, 'verses': verses.skip(5).toList()}),
    };
    work = {
      'slug': slug, 'generated_at': bundle['generated_at'], 'source_sha256': 'fixture-v1',
      'metadata_asset': metadataPath, 'sections': [firstPath, secondPath],
      'section_count': 2, 'verse_count': 10, 'index_count': 100,
    };
    updateCatalogue();
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test('persistent warm startup reads catalogue only; corrupt index rebuilds from uncached chapters', () async {
    final assets = RecordingAssets(files: files);
    await store.importAllAssetBundles(assets: assets);
    expect(assets.reads, [catalogPath, metadataPath, firstPath, secondPath]);
    expect(assets.cacheRequests.every((cache) => !cache), isTrue);
    await store.close();
    store = await LocalStore.open(pathOverride: '${dir.path}/cache.db');
    assets.reads.clear();
    await store.importAllAssetBundles(assets: assets);
    expect(assets.reads, [catalogPath]);
    await store.deleteSearchIndex(slug);
    expect(await store.isBundleReady(slug, bundle['generated_at'] as String?), isFalse);
    assets.reads.clear();
    await store.importAllAssetBundles(assets: assets);
    expect(assets.reads, [catalogPath, metadataPath, firstPath, secondPath]);
    expect(await store.isBundleReady(slug, bundle['generated_at'] as String?), isTrue);
    expect(await store.searchRows(slug, 'naimisa', {}), isNotEmpty);
  });

  test('failed later chapter rolls back flushed index/cache and never publishes readiness; retry succeeds', () async {
    final saved = files.remove(secondPath)!;
    await expectLater(store.importAllAssetBundles(assets: RecordingAssets(files: files)), throwsStateError);
    expect(await store.bundleSlugs(), isEmpty);
    expect(await store.get('toc:$slug'), isNull);
    expect(await store.get('verse:$slug:1.1.1'), isNull);
    expect(await store.searchRows(slug, '', {}), isEmpty);
    expect(await store.isBundleReady(slug, bundle['generated_at'] as String?), isFalse);
    files[secondPath] = saved;
    await store.importAllAssetBundles(assets: RecordingAssets(files: files));
    expect(await store.isBundleReady(slug, bundle['generated_at'] as String?), isTrue);
  });

  test('failed upgrade preserves previous ready index and retries after reopening', () async {
    await store.importAllAssetBundles(assets: RecordingAssets(files: files));
    work['source_sha256'] = 'fixture-v2';
    updateCatalogue();
    final saved = files.remove(secondPath)!;
    await expectLater(store.importAllAssetBundles(assets: RecordingAssets(files: files)), throwsStateError);
    expect(await store.isBundleReady(slug, bundle['generated_at'] as String?, sourceHash: 'fixture-v1'), isTrue);
    expect(await store.isBundleReady(slug, bundle['generated_at'] as String?, sourceHash: 'fixture-v2'), isFalse);
    await store.close();
    store = await LocalStore.open(pathOverride: '${dir.path}/cache.db');
    files[secondPath] = saved;
    await store.importAllAssetBundles(assets: RecordingAssets(files: files));
    expect(await store.isBundleReady(slug, bundle['generated_at'] as String?, sourceHash: 'fixture-v2'), isTrue);
  });

  test('expected verse/section/rendering counts all gate readiness', () async {
    for (final key in ['verse_count', 'section_count', 'index_count']) {
      final original = work[key] as int;
      work[key] = original + 1;
      updateCatalogue();
      await expectLater(store.importAllAssetBundles(assets: RecordingAssets(files: files)), throwsStateError);
      expect(await store.hasBundle(slug), isFalse);
      expect(await store.searchRows(slug, '', {}), isEmpty);
      work[key] = original;
    }
  });

  test('duplicate rendering identities cannot publish a count-valid index', () async {
    final section = jsonDecode(utf8.decode(files[firstPath]!)) as Map;
    final renderings = section['verses'][0]['renderings'] as List;
    renderings.add(renderings.first);
    files[firstPath] = bytes(section);
    work['index_count'] = 101;
    updateCatalogue();
    await expectLater(store.importAllAssetBundles(assets: RecordingAssets(files: files)), throwsStateError);
    expect(await store.hasBundle(slug), isFalse);
  });

  test('platform batches flush by operation count and byte budget', () async {
    final executor = _Executor();
    final sizes = <int>[];
    var pending = 0;
    when(() => executor.batch()).thenAnswer((_) {
      final batch = _Batch();
      when(() => batch.insert(any(), any(), conflictAlgorithm: ConflictAlgorithm.replace)).thenAnswer((_) { pending++; });
      when(() => batch.commit(noResult: true)).thenAnswer((_) async {
        sizes.add(pending);
        pending = 0;
        return <Object?>[];
      });
      return batch;
    });
    final batch = BoundedBatch(executor);
    for (var i = 0; i < 300; i++) {
      await batch.insert('kv', {'v': 'small'});
    }
    await batch.flush();
    expect(sizes, [128, 128, 44]);
    sizes.clear();
    for (var i = 0; i < 3; i++) {
      await batch.insert('kv', {'v': 'x' * 400000});
    }
    await batch.flush();
    expect(sizes, [1, 1, 1]);
    await expectLater(batch.insert('kv', {'v': 'x' * BoundedBatch.maxBytes}), throwsStateError);
  });
}

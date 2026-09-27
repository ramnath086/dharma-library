import 'dart:convert';
import 'dart:io';

import 'package:dharma_library/core/db/repository.dart';
import 'package:dharma_library/core/offline/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the offline path end-to-end against the shipped Wikisource bundle:
/// import → toc → chapter → verse → search → bookmarks → progress.
void main() {
  late LocalStore store;
  late Repository repo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    store = await LocalStore.inMemory();
    final bundle = jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map<String, dynamic>;
    await store.importBundle(bundle);
  });

  setUp(() {
    repo = Repository(store: store);
  });

  tearDown(() async {
    await store.clearUserData();
    await store.clearErrorLog();
  });

  tearDownAll(() => store.close());

  test('toc and chapter load from bundle', () async {
    final toc = await repo.toc('bhagavata-purana');
    expect(toc.work.shortCode, 'SB');
    final ch = await repo.chapter(toc.chapters.first.id);
    expect(ch.verses.length, greaterThanOrEqualTo(10));
    expect(ch.verses.first.ref, '1.1.1');
    expect(ch.verses.first.hasEditorialCue, isTrue);
    expect(ch.verses[3].hasEditorialCue, isFalse);
    expect(ch.editions.every((e) => e.isCleared), isTrue, reason: 'bundle must only contain rights-cleared editions');
    if (toc.work.isPilot) {
      expect(toc.chapters, hasLength(1));
      expect(ch.verses, hasLength(10));
    } else {
      expect(toc.chapters, hasLength(335));
    }
  });

  test('library imports Gita alongside Bhāgavata and searches both works', () async {
    final gita = jsonDecode(File('assets/bundles/bhagavad-gita.json').readAsStringSync()) as Map<String, dynamic>;
    await store.importBundle(gita);
    expect(await store.bundleSlugs(), ['bhagavad-gita', 'bhagavata-purana']);

    final toc = await repo.toc('bhagavad-gita');
    expect(toc.chapters, hasLength(18));
    final total = toc.chapters.fold<int>(0, (n, c) => n + c.verseCount);
    expect(total, 700);
    expect((await repo.search('Kurukshetra')).any((h) => h.workSlug == 'bhagavad-gita'), isTrue);
    expect((await repo.search('naimisa')).any((h) => h.workSlug == 'bhagavata-purana'), isTrue);
  });

  test('verse detail has renderings and mentions', () async {
    final v = await repo.verse('bhagavata-purana', '1.1.4');
    expect(v.verse.byKind('base_text')!.body, contains('नैमिषे'));
    expect(v.verse.byKind('translation', lang: 'ml')!.body, contains('നൈമിഷാരണ്യ'));
    expect(v.mentions.any((m) => m['entity_kind'] == 'place'), isTrue);
    expect(v.nextRef, '1.1.5');
    expect(v.prevRef, '1.1.3');
  });

  test('offline search is diacritic/script insensitive', () async {
    expect((await repo.search('naimisa')).map((h) => h.ref), contains('1.1.4'));
    expect((await repo.search('krishna')), isNotEmpty);
    expect((await repo.search('കലിയുഗ')).map((h) => h.ref), contains('1.1.10'));
    expect((await repo.search('1.1.7')).first.ref, '1.1.7');
    expect(await repo.search('zzzz-nothing'), isEmpty);
  });

  test('entity search offline', () async {
    final hits = await repo.searchEntities('vyasa');
    expect(hits.map((h) => h.slug), contains('vyasa'));
    expect((await repo.searchEntities('സൂതൻ')).map((h) => h.slug), contains('suta'));
  });

  test('bookmarks and progress are local-first', () async {
    final toc = await repo.toc('bhagavata-purana');
    final ch = await repo.chapter(toc.chapters.first.id);
    final v3 = ch.verses[2];
    await repo.toggleBookmark(v3);
    expect(await repo.isBookmarked(v3.id), isTrue);
    expect((await repo.bookmarks()).single.verseRef, '1.1.3');
    await repo.updateBookmarkNote(v3.id, 'sweet');
    expect((await repo.bookmarks()).single.note, 'sweet');
    await repo.toggleBookmark(v3);
    expect(await repo.bookmarks(), isEmpty);

    await repo.recordProgress(workId: toc.work.id, verse: ch.verses[4], sectionId: ch.id, totalVerses: 10, position: 5);
    final p = await repo.progress(toc.work.id);
    expect(p!.percent, 50.0);
    expect(p.verseRef, '1.1.5');
  });

  test('bookmark tags: set, preserved on note edit, filtered decode', () async {
    final toc = await repo.toc('bhagavata-purana');
    final ch = await repo.chapter(toc.chapters.first.id);
    await repo.toggleBookmark(ch.verses[3]);
    await repo.updateBookmarkNote(ch.verses[3].id, null, tags: ['bhakti', 'naimisha']);
    expect((await repo.bookmarks()).single.tags, ['bhakti', 'naimisha']);
    // editing the note without tags keeps them
    await repo.updateBookmarkNote(ch.verses[3].id, 'deep');
    final b = (await repo.bookmarks()).single;
    expect(b.note, 'deep');
    expect(b.tags, ['bhakti', 'naimisha']);
    // whitespace/empty tags are discarded
    await repo.updateBookmarkNote(ch.verses[3].id, null, tags: [' x ', '', 'y']);
    expect((await repo.bookmarks()).single.tags, ['x', 'y']);
  });

  test('reading history records refs, newest first, and clears', () async {
    final toc = await repo.toc('bhagavata-purana');
    final ch = await repo.chapter(toc.chapters.first.id);
    for (final i in [1, 5, 2]) {
      await repo.recordProgress(workId: toc.work.id, verse: ch.verses[i], sectionId: ch.id, totalVerses: 10, position: i + 1);
    }
    final hist = await store.readingHistory();
    expect(hist, hasLength(3));
    expect(hist.map((h) => h['verse_ref']).toSet(), {'1.1.3', '1.1.6', '1.1.2'});
    expect((await store.readVerseIds()).length, 3);
    await store.clearVerseReads();
    expect(await store.readingHistory(), isEmpty);
    expect(await store.readVerseIds(), isEmpty);
  });

  test('iast fold', () {
    expect(Repository.fold('Kṛṣṇa'), 'krsna');
    expect(Repository.fold('krishna'), 'krsna');
    expect(Repository.fold('Śrī'), 'sr');
  });

  test('diagnostics error log: newest first, capped, clearable', () async {
    await store.appendErrorLog('flutter', 'a'.padRight(500, 'a'));
    await store.appendErrorLog('platform', 'small error');
    final log = await store.errorLog();
    expect(log.first.contains('small error'), isTrue);
    expect(log.first.startsWith('2'), isTrue); // ISO timestamp prefix
    expect(log[1].length < 500, isTrue); // long messages are truncated
    for (var i = 0; i < 60; i++) {
      await store.appendErrorLog('x', 'msg$i');
    }
    expect((await store.errorLog()).length, 50);
    await store.clearErrorLog();
    expect(await store.errorLog(), isEmpty);
  });

  test('analytics guard: no client / signed-out logs nothing and throws nothing', () async {
    await repo.logAnalytics('daily_open');
    await repo.logAnalytics('search', {'hits': 3, 'offline': true});
  });
  test('offline index covers late chapters; readiness, rebuild and removal', () async {
    final bundle = jsonDecode(File('test/fixtures/mini_bhagavata_bundle.json').readAsStringSync()) as Map<String, dynamic>;
    final dir = await Directory.systemTemp.createTemp('dharma-search-test-');
    final fresh = await LocalStore.open(pathOverride: '${dir.path}/search.db');
    try {
      await fresh.importBundle(bundle);
      final slug = (bundle['toc']['work'] as Map)['slug'] as String;
      final generated = bundle['generated_at'] as String?;
      expect(await fresh.isBundleReady(slug, generated), isTrue);
      final count = (await fresh.searchRows(slug, 'naimisa', {})).length;
      await fresh.importBundle(bundle);
      expect((await fresh.searchRows(slug, 'naimisa', {})).length, count, reason: 'reimport must not duplicate rows');

      await fresh.deleteSearchIndex(slug); // simulate a damaged/interrupted index
      expect(await fresh.isBundleReady(slug, generated), isFalse);
      await fresh.importBundle(bundle);
      expect(await fresh.isBundleReady(slug, generated), isTrue);
      expect((await fresh.searchRows(slug, 'naimisa', {})).length, count);
      final offline = Repository(store: fresh);
      expect((await offline.search('1.1.7')).first.ref, '1.1.7');
      await offline.removeDownload(slug);
      expect(await fresh.bundleSlugs(), isEmpty);
      expect(await fresh.searchRows(slug, 'naimisa', {}), isEmpty);
      expect(await fresh.isBundleReady(slug, generated), isFalse);
      await fresh.importBundle(bundle);
      expect(await fresh.isBundleReady(slug, generated), isTrue);
    } finally {
      await fresh.close();
      await dir.delete(recursive: true);
    }
  });

  test('index searches late Bhāgavata verse and BG 18.66 by exact ref', () async {
    final late = await repo.search('12.13.23', workSlug: 'bhagavata-purana');
    expect(late.map((h) => h.ref), contains('12.13.23'));
    final gita = jsonDecode(File('assets/bundles/bhagavad-gita.json').readAsStringSync()) as Map<String, dynamic>;
    await store.importBundle(gita);
    final bg = await repo.search('18.66', workSlug: 'bhagavad-gita');
    expect(bg.map((h) => h.ref), contains('18.66'));
    expect(bg.every((h) => h.workSlug == 'bhagavad-gita'), isTrue);
  });

}

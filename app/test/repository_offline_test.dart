import 'dart:convert';
import 'dart:io';

import 'package:dharma_library/core/db/repository.dart';
import 'package:dharma_library/core/offline/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the offline path end-to-end against the shipped pilot bundle:
/// import → toc → chapter → verse → search → bookmarks → progress.
void main() {
  late LocalStore store;
  late Repository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    store = await LocalStore.inMemory();
    final bundle = jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map<String, dynamic>;
    await store.importBundle(bundle);
    repo = Repository(store: store);
  });

  tearDown(() => store.close());

  test('toc and chapter load from bundle', () async {
    final toc = await repo.toc('bhagavata-purana');
    expect(toc.work.shortCode, 'SB');
    expect(toc.chapters, hasLength(1));
    final ch = await repo.chapter(toc.chapters.first.id);
    expect(ch.verses, hasLength(10));
    expect(ch.verses.first.ref, '1.1.1');
    expect(ch.editions.every((e) => e.isCleared), isTrue, reason: 'bundle must only contain rights-cleared editions');
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
    expect((await repo.search('krishna')).map((h) => h.ref), contains('1.1.1'));
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

  test('iast fold', () {
    expect(Repository.fold('Kṛṣṇa'), 'krsna');
    expect(Repository.fold('krishna'), 'krsna');
    expect(Repository.fold('Śrī'), 'sr');
  });
}

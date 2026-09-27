import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'search_fold.dart';

/// On-device cache (SQLite via sqflite).
///
/// Tables
///   kv            — arbitrary JSON blobs keyed by string (toc, chapters, verses, bundles)
///   bookmarks     — local copy of the user's bookmarks (+ dirty flag for sync)
///   progress      — local reading progress per work (+ dirty flag)
///   outbox        — pending mutations to replay when online
///
/// Design: the Supabase RPC payloads are cached verbatim under deterministic
/// keys, so every screen has exactly one code path (parse JSON) whether the
/// data came from the network, the cache, or the shipped asset bundle.
class LocalStore {
  LocalStore._(this._db);
  final Database _db;

  static Future<LocalStore> open({String? pathOverride}) async {
    final dir = await getApplicationSupportDirectory();
    final path = pathOverride ?? p.join(dir.path, 'dharma_library.db');
    final db = await openDatabase(path, version: 5, onCreate: _create, onUpgrade: _upgrade);
    return LocalStore._(db);
  }

  static Future<LocalStore> inMemory() async {
    final db = await openDatabase(inMemoryDatabasePath, version: 5, onCreate: _create);
    return LocalStore._(db);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _create(db, to);
    // v3: reading history keeps the verse ref so the history screen needs no join
    if (from < 3 && !await _hasColumn(db, 'verse_reads', 'verse_ref')) {
      await db.execute('alter table verse_reads add column verse_ref text');
    }
    if (from < 5) await _createSearchTable(db);
    if (from < 4 && !await _hasColumn(db, 'verse_reads', 'work_slug')) {
      await db.execute('alter table verse_reads add column work_slug text');
    }
  }

  static Future<bool> _hasColumn(Database db, String table, String column) async {
    final rows = await db.rawQuery('pragma table_info($table)');
    return rows.any((r) => r['name'] == column);
  }

  static Future<void> _create(Database db, int v) async {
    await db.execute('create table if not exists kv (k text primary key, v text not null, updated_at integer not null)');
    await db.execute('''create table if not exists bookmarks (
      id text primary key, verse_id text not null, verse_ref text, edition_id text, note text, color text, tags text,
      created_at text not null, updated_at text not null, dirty integer not null default 0, deleted integer not null default 0)''');
    await db.execute('create unique index if not exists bookmarks_verse on bookmarks (verse_id)');
    await db.execute('''create table if not exists progress (
      work_id text primary key, verse_id text not null, section_id text, verse_ref text, percent real not null,
      last_read_at text not null, dirty integer not null default 0)''');
    await db.execute('''create table if not exists outbox (
      id integer primary key autoincrement, kind text not null, payload text not null, created_at integer not null)''');
    await db.execute('create table if not exists verse_reads (verse_id text primary key, verse_ref text, work_slug text, read_at text not null, dirty integer not null default 1)');
    await _createSearchTable(db);
  }

  static Future<void> _createSearchTable(Database db) async {
    await db.execute('''create table if not exists search_index (
      work_slug text not null, verse_id text not null, ref text not null,
      edition_id text not null, edition_title text not null,
      language_code text not null, script_code text not null, kind text not null,
      body text not null, folded_body text not null,
      primary key (work_slug, ref, edition_id)
    )''');
    await db.execute('create index if not exists search_work_ref on search_index(work_slug, ref)');
  }

  /// Index and bundle keys are committed together. Incomplete imports can
  /// never publish a ready marker, and an interrupted transaction rolls back.
  /// An explicit count check detects stale/partial indexes on the next launch.
  Future<bool> isBundleReady(String slug, String? generatedAt) async {
    final meta = await get<Map<String, dynamic>>('bundle_meta:$slug');
    if (meta == null || meta['index_version'] != 1 || meta['generated_at'] != generatedAt) return false;
    final rows = await _db.rawQuery('select count(*) as n from search_index where work_slug = ?', [slug]);
    return rows.first['n'] == meta['index_count'];
  }

  Future<List<Map<String, Object?>>> searchRows(String slug, String foldedQuery, Set<String> mentioned) {
    // Escape SQL wildcards: a literal '%' or '_' must not match every verse.
    final escaped = foldedQuery.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
    final ids = mentioned.toList();
    final mentionsClause = ids.isEmpty ? '' : ' or verse_id in (${List.filled(ids.length, '?').join(',')})';
    return _db.query('search_index',
        where: "work_slug = ? and (folded_body like ? escape '\' or ref = ?$mentionsClause)",
        whereArgs: [slug, '%$escaped%', foldedQuery, ...ids], orderBy: 'ref, edition_id');
  }

  Future<void> deleteSearchIndex(String slug) =>
      _db.delete('search_index', where: 'work_slug = ?', whereArgs: [slug]);

  // ---------------------------------------------------------------- kv
  Future<void> put(String key, Object json) async {
    await _db.insert('kv', {'k': key, 'v': jsonEncode(json), 'updated_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<T?> get<T>(String key) async {
    final rows = await _db.query('kv', where: 'k = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['v'] as String) as T;
  }

  Future<DateTime?> ageOf(String key) async {
    final rows = await _db.query('kv', columns: ['updated_at'], where: 'k = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(rows.first['updated_at'] as int);
  }

  Future<void> deletePrefix(String prefix) => _db.delete('kv', where: 'k like ?', whereArgs: ['$prefix%']);
  Future<void> delete(String key) => _db.delete('kv', where: 'k = ?', whereArgs: [key]);

  Future<int> sizeBytes() async {
    final r = await _db.rawQuery('select coalesce(sum(length(v)),0) as n from kv');
    return (r.first['n'] as int?) ?? 0;
  }

  // ---------------------------------------------------------- bundles
  /// Import a work bundle (output of get_work_bundle) into the kv cache under
  /// the same keys the repository uses for live data.
  Future<void> importBundle(Map<String, dynamic> bundle) async {
    final toc = (bundle['toc'] as Map).cast<String, dynamic>();
    final slug = toc['work']['slug'] as String;
    if (await isBundleReady(slug, bundle['generated_at'] as String?)) return;
    final knownSlugs = await bundleSlugs();
    final mentionsByVerse = <Object?, List<dynamic>>{};
    for (final m in (bundle['mentions'] as List)) {
      mentionsByVerse.putIfAbsent((m as Map)['verse_id'], () => []).add(m);
    }
    await _db.transaction((txn) async {
    final batch = txn.batch();
    batch.delete('search_index', where: 'work_slug = ?', whereArgs: [slug]);
    void putB(String k, Object v) =>
        batch.insert('kv', {'k': k, 'v': jsonEncode(v), 'updated_at': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
    putB('toc:$slug', toc);
    putB('editions:$slug', bundle['editions']);
    putB('graph:$slug', {
      'people': bundle['people'], 'places': bundle['places'], 'topics': bundle['topics'], 'stories': bundle['stories'],
      'entity_names': bundle['entity_names'], 'mentions': bundle['mentions'], 'cross_references': bundle['cross_references'],
    });
    final titles = {for (final e in (bundle['editions'] as List)) (e as Map)['id']: e['title']};
    var indexCount = 0;
    for (final sec in (bundle['sections'] as List)) {
      final s = (sec as Map).cast<String, dynamic>();
      putB('chapter:${s['section']['id']}', s);
      // also derive per-verse detail (subset) so verse pages work offline
      final verses = (s['verses'] as List).map((v) => (v as Map).cast<String, dynamic>()).toList();
      for (var i = 0; i < verses.length; i++) {
        final v = verses[i];
        for (final raw in (v['renderings'] as List? ?? const [])) {
          final r = raw as Map;
          final body = r['body'] as String? ?? '';
          batch.insert('search_index', {
            'work_slug': slug, 'verse_id': v['id'], 'ref': v['ref'],
            'edition_id': r['edition_id'], 'edition_title': titles[r['edition_id']] ?? r['kind'],
            'language_code': r['language_code'], 'script_code': r['script_code'], 'kind': r['kind'],
            'body': body, 'folded_body': foldSearch(body),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          indexCount++;
        }
        putB('verse:$slug:${v['ref']}', {
          'verse': v, 'section': s['section'], 'renderings': v['renderings'],
          'mentions': mentionsByVerse[v['id']] ?? const [],
          'cross_references': [],
          'prev_ref': i > 0 ? verses[i - 1]['ref'] : null,
          'next_ref': i < verses.length - 1 ? verses[i + 1]['ref'] : null,
        });
      }
    }
    putB('bundle_meta:$slug', {'generated_at': bundle['generated_at'], 'imported_at': DateTime.now().toIso8601String(), 'index_version': 1, 'index_count': indexCount});
    putB('bundle_slugs', {...knownSlugs, slug}.toList()..sort());
    await batch.commit(noResult: true);
    });
  }

  Future<bool> hasBundle(String slug) async => (await get('bundle_meta:$slug')) != null;

  /// Slugs whose bundles have been imported into this device.  This is the
  /// app's local catalogue: it lets the reader and offline search operate on
  /// every work shipped in the APK, not only the historical pilot work.
  Future<List<String>> bundleSlugs() async {
    final raw = await get<List>('bundle_slugs');
    if (raw == null) return const <String>[];
    final slugs = raw.whereType<String>().toList();
    slugs.sort();
    return slugs;
  }

  /// Discover every bundle declared in Flutter's generated asset manifest and
  /// import it.  Asset directories cannot be listed directly at runtime, so
  /// the manifest is the source of truth and adding a new JSON asset is all
  /// that is needed to add a work to the offline catalogue.
  Future<List<String>> importAllAssetBundles() async {
    final manifest = jsonDecode(await rootBundle.loadString('AssetManifest.json'));
    final paths = manifest is Map
        ? manifest.keys.cast<String>()
        : manifest is List
            ? manifest.whereType<String>()
            : const <String>[];
    final slugs = paths
        .where((path) => path.startsWith('assets/bundles/') && path.endsWith('.json'))
        .map((path) => path.substring('assets/bundles/'.length, path.length - '.json'.length))
        .where((slug) => slug.isNotEmpty && !slug.contains('/') && slug != 'manifest' && slug != 'catalog')
        .toSet()
        .toList()
      ..sort();
    for (final slug in slugs) {
      await importAssetBundle(slug);
    }
    return slugs;
  }

  Future<void> importAssetBundle(String slug) async {
    final txt = await rootBundle.loadString('assets/bundles/$slug.json');
    final bundle = jsonDecode(txt) as Map<String, dynamic>;
    final meta = (bundle['toc'] as Map)['work'] as Map;
    if (await isBundleReady(meta['slug'] as String, bundle['generated_at'] as String?)) return;
    await importBundle(bundle);
  }

  // -------------------------------------------------------- bookmarks
  Future<List<Map<String, dynamic>>> bookmarks() =>
      _db.query('bookmarks', where: 'deleted = 0', orderBy: 'created_at desc');

  Future<void> upsertBookmark(Map<String, dynamic> b, {bool dirty = true}) async {
    await _db.insert('bookmarks', {
      'id': b['id'], 'verse_id': b['verse_id'], 'verse_ref': b['verse_ref'], 'edition_id': b['edition_id'], 'note': b['note'],
      'color': b['color'], 'tags': jsonEncode(b['tags'] ?? []), 'created_at': b['created_at'], 'updated_at': b['updated_at'],
      'dirty': dirty ? 1 : 0, 'deleted': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBookmark(String verseId, {bool hard = false}) async {
    if (hard) {
      await _db.delete('bookmarks', where: 'verse_id = ?', whereArgs: [verseId]);
    } else {
      await _db.update('bookmarks', {'deleted': 1, 'dirty': 1, 'updated_at': DateTime.now().toIso8601String()}, where: 'verse_id = ?', whereArgs: [verseId]);
    }
  }

  Future<List<Map<String, dynamic>>> dirtyBookmarks() => _db.query('bookmarks', where: 'dirty = 1');
  Future<void> markBookmarkClean(String id) => _db.update('bookmarks', {'dirty': 0}, where: 'id = ?', whereArgs: [id]);
  Future<void> purgeDeletedBookmarks() => _db.delete('bookmarks', where: 'deleted = 1 and dirty = 0');

  // --------------------------------------------------------- progress
  Future<Map<String, dynamic>?> progress(String workId) async {
    final r = await _db.query('progress', where: 'work_id = ?', whereArgs: [workId], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<void> putProgress(Map<String, dynamic> pr, {bool dirty = true}) async {
    await _db.insert('progress', {
      'work_id': pr['work_id'], 'verse_id': pr['verse_id'], 'section_id': pr['section_id'], 'verse_ref': pr['verse_ref'],
      'percent': pr['percent'], 'last_read_at': pr['last_read_at'], 'dirty': dirty ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> dirtyProgress() => _db.query('progress', where: 'dirty = 1');
  Future<void> markProgressClean(String workId) => _db.update('progress', {'dirty': 0}, where: 'work_id = ?', whereArgs: [workId]);

  Future<void> markRead(String verseId, {String? verseRef}) => _db.insert(
      'verse_reads',
      {'verse_id': verseId, 'verse_ref': verseRef, 'read_at': DateTime.now().toIso8601String(), 'dirty': 1},
      conflictAlgorithm: ConflictAlgorithm.replace);
  Future<Set<String>> readVerseIds() async => (await _db.query('verse_reads')).map((r) => r['verse_id'] as String).toSet();

  /// Reading history, newest first: {verse_id, verse_ref, read_at}.
  Future<List<Map<String, dynamic>>> readingHistory({int limit = 200}) =>
      _db.query('verse_reads', orderBy: 'read_at desc', limit: limit);

  Future<void> clearVerseReads() => _db.delete('verse_reads');

  Future<void> clearUserData() async {
    await _db.delete('bookmarks');
    await _db.delete('progress');
    await _db.delete('verse_reads');
    await _db.delete('outbox');
  }

  // -------------------------------------------------------- diagnostics
  static const _errorLogKey = 'error_log';
  static const _errorLogCap = 50;
  static const _errorEntryMaxLen = 400;

  /// Append a crash/error entry to the on-device diagnostics log (capped,
  /// newest first). Never throws — diagnostics must not crash the app.
  Future<void> appendErrorLog(String kind, String message) async {
    try {
      final cur = await errorLog();
      final trimmed = message.length > _errorEntryMaxLen ? message.substring(0, _errorEntryMaxLen) : message;
      await put(_errorLogKey, ['${DateTime.now().toIso8601String()} [$kind] $trimmed', ...cur].take(_errorLogCap).toList());
    } catch (_) {/* ignore */}
  }

  Future<List<String>> errorLog() async {
    final raw = await get<List>(_errorLogKey);
    return raw == null ? const [] : raw.map((e) => e.toString()).toList();
  }

  Future<void> clearErrorLog() => _db.delete('kv', where: 'k = ?', whereArgs: [_errorLogKey]);

  Future<void> close() => _db.close();
}

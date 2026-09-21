import 'dart:async';

import 'package:collection/collection.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../offline/local_store.dart';
import '../offline/prefetch.dart';
import 'models.dart';

/// Single data-access layer for the app.
///
/// Read strategy: **network-first with cache fallback** for live data, and
/// **cache-only** when offline or when no backend is configured. Every read
/// caches the raw JSON so subsequent offline opens work.
///
/// Write strategy (bookmarks / progress): **local-first**. Writes land in
/// SQLite immediately (dirty=1) and are pushed by [syncUserData] when a
/// session exists and the network is reachable. Server rows win on pull by
/// updated_at.
class Repository {
  Repository({required this.store, SupabaseClient? client}) : _client = client;

  final LocalStore store;
  final SupabaseClient? _client;
  final _uuid = const Uuid();

  bool get online => _online;
  bool _online = true;
  void setOnline(bool v) => _online = v;

  SupabaseClient? get client => _client;
  bool get hasBackend => _client != null;
  bool get isSignedIn => _client?.auth.currentSession != null;
  String? get userId => _client?.auth.currentUser?.id;

  // -------------------------------------------------------------- helpers
  Future<T> _cached<T>(String key, Future<dynamic> Function() fetch, T Function(dynamic) parse,
      {Duration maxAge = const Duration(hours: 12)}) async {
    if (_client != null && _online) {
      try {
        final data = await fetch().timeout(const Duration(seconds: 15));
        if (data != null) {
          await store.put(key, data);
          return parse(data);
        }
      } catch (_) {
        // fall through to cache
      }
    }
    final cached = await store.get(key);
    if (cached != null) return parse(cached);
    throw RepositoryException('No data for $key (offline and not cached)');
  }

  // ------------------------------------------------------------ content
  Future<Toc> toc(String workSlug) => _cached('toc:$workSlug',
      () => _client!.rpc('get_toc', params: {'p_work_slug': workSlug}), (d) => Toc.fromJson((d as Map).cast<String, dynamic>()));

  Future<List<Edition>> editions(String workSlug) => _cached('editions:$workSlug', () async {
        // v_editions is global; constrain it through the work id so a
        // multi-work library never mixes Bhāgavata and Gītā layouts.
        final work = await _client!.from('works').select('id').eq('slug', workSlug).single();
        return _client!.from('v_editions').select().eq('work_id', work['id']).order('sort_order');
      }, (d) => (d as List).map((e) => Edition.fromJson((e as Map).cast<String, dynamic>())).where((e) => e.isCleared).toList());

  Future<Chapter> chapter(String sectionId) => _cached('chapter:$sectionId',
      () => _client!.rpc('get_section_verses', params: {'p_section_id': sectionId}), (d) => Chapter.fromJson((d as Map).cast<String, dynamic>()));

  Future<VerseDetail> verse(String workSlug, String ref) => _cached('verse:$workSlug:$ref',
      () => _client!.rpc('get_verse', params: {'p_work_slug': workSlug, 'p_ref': ref}), (d) => VerseDetail.fromJson((d as Map).cast<String, dynamic>()));

  Future<Map<String, dynamic>> entity(String kind, String slug) => _cached('entity:$kind:$slug',
      () => _client!.rpc('get_entity', params: {'p_kind': kind, 'p_slug': slug}), (d) => (d as Map).cast<String, dynamic>());

  Future<Map<String, dynamic>?> graph(String workSlug) async => (await store.get('graph:$workSlug')) as Map<String, dynamic>?;

  // ------------------------------------------------------------- search
  Future<List<SearchHit>> search(String q, {String? workSlug, String? language, int limit = 30}) async {
    if (_client != null && _online) {
      try {
        final rows = await _client.rpc('search_verses', params: {
          'p_query': q, 'p_work_slug': workSlug, 'p_language': language, 'p_edition_ids': null, 'p_limit': limit, 'p_offset': 0,
        }).timeout(const Duration(seconds: 15));
        return (rows as List).map((r) => SearchHit.fromJson((r as Map).cast<String, dynamic>())).toList();
      } catch (_) {/* offline fallback */}
    }
    return _offlineSearch(q, workSlug: workSlug, language: language, limit: limit);
  }

  Future<List<EntityHit>> searchEntities(String q, {int limit = 20}) async {
    if (_client != null && _online) {
      try {
        final rows = await _client.rpc('search_entities', params: {'p_query': q, 'p_limit': limit});
        return (rows as List).map((r) => EntityHit.fromJson((r as Map).cast<String, dynamic>())).toList();
      } catch (_) {}
    }
    final f = fold(q);
    final out = <EntityHit>[];
    for (final slug in await store.bundleSlugs()) {
      final g = await graph(slug);
      if (g == null) continue;
      for (final kind in const ['people', 'places', 'topics', 'stories']) {
        for (final e in (g[kind] as List? ?? [])) {
          final name = (e['name_iast'] ?? e['title_iast'] ?? '') as String;
          final names = (g['entity_names'] as List? ?? []).where((n) => n['entity_id'] == e['id']).map((n) => n['name'] as String);
          if (fold(name).contains(f) || names.any((n) => fold(n).contains(f) || n.contains(q))) {
            out.add(EntityHit.fromJson({
              'entity_kind': kind == 'people' ? 'person' : kind.substring(0, kind.length - 1),
              'entity_id': e['id'], 'slug': e['slug'], 'name_iast': name, 'matched_name': name, 'language_code': 'sa',
            }));
          }
        }
      }
    }
    return out.take(limit).toList();
  }

  String workSlugDefault = 'bhagavata-purana';

  /// Offline search over every imported work unless a caller asks for one
  /// work explicitly.  Hits retain their work slug so the UI can navigate to
  /// the matching reader instead of assuming Bhāgavata.
  Future<List<SearchHit>> _offlineSearch(String q, {String? workSlug, String? language, int limit = 30}) async {
    final slugs = workSlug == null ? await store.bundleSlugs() : [workSlug];
    final f = fold(q);
    final hits = <SearchHit>[];

    for (final slug in slugs) {
      final toc = await store.get('toc:$slug');
      if (toc == null) continue;

      // Entity-name expansion mirrors search_verses: a query for an entity
      // can find verses that mention it even when the name is not literal in
      // the selected rendering.
      final mentioned = <String>{};
      final g = await graph(slug);
      if (g != null && f.length >= 3) {
        final ids = <String>{};
        for (final kind in const ['people', 'places', 'topics', 'stories']) {
          for (final e in (g[kind] as List? ?? [])) {
            final name = (e['name_iast'] ?? e['title_iast'] ?? '') as String;
            final names = (g['entity_names'] as List? ?? [])
                .where((n) => n['entity_id'] == e['id'])
                .map((n) => n['name'] as String);
            if (fold(name).contains(f) || names.any((n) => fold(n).contains(f) || n.contains(q))) ids.add(e['id'] as String);
          }
        }
        for (final m in (g['mentions'] as List? ?? [])) {
          if (ids.contains(m['entity_id'])) mentioned.add(m['verse_id'] as String);
        }
      }

      for (final ch in Toc.fromJson((toc as Map).cast<String, dynamic>()).chapters) {
        final raw = await store.get('chapter:${ch.id}');
        if (raw == null) continue;
        final chapter = Chapter.fromJson((raw as Map).cast<String, dynamic>());
        final edById = {for (final e in chapter.editions) e.id: e};
        for (final v in chapter.verses) {
          if (v.ref == q.trim()) {
            final r = v.renderings.firstOrNull;
            if (r != null) hits.add(_hit(v, r, edById[r.editionId], slug, r.body, 1.0));
            continue;
          }
          var matched = false;
          for (final r in v.renderings) {
            if (language != null && r.languageCode != language) continue;
            final body = r.body;
            final idx = fold(body).indexOf(f);
            if (idx >= 0 || body.contains(q)) {
              final at = idx >= 0 ? idx : body.indexOf(q);
              final start = (at - 60).clamp(0, body.length);
              final end = (at + 100).clamp(0, body.length);
              hits.add(_hit(v, r, edById[r.editionId], slug,
                  '${start > 0 ? '…' : ''}${body.substring(start, end)}${end < body.length ? '…' : ''}', 0.9));
              matched = true;
            }
          }
          if (!matched && mentioned.contains(v.id)) {
            final r = v.renderings.where((r) => r.kind == 'translation' && (language == null || r.languageCode == language)).firstOrNull ?? v.renderings.firstOrNull;
            if (r != null) hits.add(_hit(v, r, edById[r.editionId], slug, r.body.length > 160 ? '${r.body.substring(0, 160)}…' : r.body, 0.5));
          }
        }
      }
    }
    hits.sort((a, b) => b.rank.compareTo(a.rank));
    return hits.take(limit).toList();
  }

  SearchHit _hit(Verse v, Rendering r, Edition? e, String slug, String snippet, double rank) => SearchHit.fromJson({
        'verse_id': v.id, 'ref': v.ref, 'work_slug': slug, 'edition_id': r.editionId, 'edition_title': e?.title ?? r.kind,
        'language_code': r.languageCode, 'script_code': r.scriptCode, 'kind': r.kind, 'snippet': snippet, 'rank': rank,
      });

  /// Dart mirror of SQL `iast_fold`: lower-case, strip IAST diacritics,
  /// normalise popular spellings.
  static String fold(String s) {
    const from = 'āīūṛṝḷḹṃṁḥṅñṭḍṇśṣ\'’';
    const to = 'aiurrllmmhnntdnss';
    var out = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], i < to.length ? to[i] : '');
    }
    return out.replaceAll('sh', 's').replaceAll('ri', 'r').replaceAll('ee', 'i');
  }

  // ---------------------------------------------------------- bookmarks
  Future<List<Bookmark>> bookmarks() async {
    final rows = await store.bookmarks();
    return rows.map((r) => Bookmark.fromJson({...r, 'tags': _decodeTags(r['tags'])})).toList();
  }

  List<String> _decodeTags(Object? t) {
    if (t is List) return t.cast<String>();
    if (t is String && t.startsWith('[')) {
      return (t.substring(1, t.length - 1)).split(',').where((s) => s.trim().isNotEmpty).map((s) => s.trim().replaceAll('"', '')).toList();
    }
    return const [];
  }

  Future<bool> isBookmarked(String verseId) async => (await store.bookmarks()).any((b) => b['verse_id'] == verseId);

  Future<void> toggleBookmark(Verse verse, {String? editionId, String? note}) async {
    if (await isBookmarked(verse.id)) {
      await store.deleteBookmark(verse.id);
    } else {
      final now = DateTime.now().toUtc().toIso8601String();
      await store.upsertBookmark({
        'id': _uuid.v4(), 'verse_id': verse.id, 'verse_ref': verse.ref, 'edition_id': editionId, 'note': note, 'tags': [],
        'created_at': now, 'updated_at': now,
      });
    }
    unawaited(syncUserData());
  }

  Future<void> updateBookmarkNote(String verseId, String? note, {List<String>? tags}) async {
    final rows = await store.bookmarks();
    final b = rows.where((r) => r['verse_id'] == verseId).firstOrNull;
    if (b == null) return;
    await store.upsertBookmark({
      ...b,
      'tags': tags?.where((t) => t.trim().isNotEmpty).map((t) => t.trim()).toList() ?? _decodeTags(b['tags']),
      'note': note,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    unawaited(syncUserData());
  }

  // ----------------------------------------------------------- progress
  Future<ReadingProgress?> progress(String workId) async {
    final r = await store.progress(workId);
    return r == null ? null : ReadingProgress.fromJson(r);
  }

  Future<void> recordProgress({required String workId, required Verse verse, required String sectionId, required int totalVerses, required int position}) async {
    final pct = totalVerses == 0 ? 0.0 : (100.0 * position / totalVerses);
    await store.putProgress({
      'work_id': workId, 'verse_id': verse.id, 'section_id': sectionId, 'verse_ref': verse.ref,
      'percent': double.parse(pct.toStringAsFixed(2)), 'last_read_at': DateTime.now().toUtc().toIso8601String(),
    });
    await store.markRead(verse.id, verseRef: verse.ref);
  }

  // --------------------------------------------------------------- sync
  Future<void> syncUserData() async {
    final c = _client;
    if (c == null || !_online || c.auth.currentSession == null) return;
    final uid = c.auth.currentUser!.id;
    try {
      // push bookmarks
      for (final b in await store.dirtyBookmarks()) {
        if (b['deleted'] == 1) {
          await c.from('bookmarks').delete().match({'user_id': uid, 'verse_id': b['verse_id']});
        } else {
          await c.from('bookmarks').upsert({
            'user_id': uid, 'verse_id': b['verse_id'], 'edition_id': b['edition_id'], 'note': b['note'], 'color': b['color'],
            'tags': _decodeTags(b['tags']), 'client_id': b['id'], 'updated_at': b['updated_at'],
          }, onConflict: 'user_id,verse_id');
        }
        await store.markBookmarkClean(b['id'] as String);
      }
      await store.purgeDeletedBookmarks();
      // push progress
      for (final p in await store.dirtyProgress()) {
        await c.rpc('upsert_progress', params: {'p_work_id': p['work_id'], 'p_verse_id': p['verse_id'], 'p_edition_ids': <String>[], 'p_device_id': null});
        await store.markProgressClean(p['work_id'] as String);
      }
      // pull
      final pulled = await c.rpc('sync_pull', params: {'p_since': '-infinity'});
      final serverBookmarks = (pulled['bookmarks'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
      final localByVerse = {for (final b in await store.bookmarks()) b['verse_id']: b};
      for (final sb in serverBookmarks) {
        final local = localByVerse[sb['verse_id']];
        if (local == null || DateTime.parse(sb['updated_at'] as String).isAfter(DateTime.parse(local['updated_at'] as String))) {
          await store.upsertBookmark({...sb, 'verse_ref': local?['verse_ref'] ?? await _refFor(sb['verse_id'] as String)}, dirty: false);
        }
      }
      for (final sp in (pulled['progress'] as List).map((e) => (e as Map).cast<String, dynamic>())) {
        final local = await store.progress(sp['work_id'] as String);
        if (local == null || DateTime.parse(sp['last_read_at'] as String).isAfter(DateTime.parse(local['last_read_at'] as String))) {
          await store.putProgress({...sp, 'verse_ref': await _refFor(sp['verse_id'] as String)}, dirty: false);
        }
      }
    } catch (_) {
      // best-effort; will retry on next trigger
    }
  }

  Future<String?> _refFor(String verseId) async {
    try {
      final r = await _client!.from('verses').select('ref').eq('id', verseId).maybeSingle();
      return r?['ref'];
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- QA (Ask Dharma)
  Future<QaAnswer> ask(String question, {String language = 'en', String? workSlug, String? sessionId}) async {
    final c = _client;
    if (c == null || !_online) throw RepositoryException('offline');
    final res = await c.functions.invoke('ask', body: {
      'question': question, 'language': language, 'work_slug': workSlug ?? workSlugDefault, 'session_id': sessionId,
    });
    if (res.status == 429) {
      final data = res.data;
      final cap = data is Map ? data['daily_cap'] : null;
      throw QaLimitException(cap is int ? cap : null);
    }
    if (res.status != 200) throw RepositoryException('ask failed: ${res.status} ${res.data}');
    return QaAnswer.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// Past conversations of the signed-in user, newest first. Empty when
  /// signed out or offline (sessions live only server-side).
  Future<List<QaSession>> qaSessions({int limit = 30}) async {
    final c = _client;
    if (c == null || !_online || !isSignedIn) return const [];
    try {
      final rows = await c.from('qa_sessions').select('id, language, title, created_at').order('created_at', ascending: false).limit(limit);
      return rows.map((r) => QaSession.fromJson((r as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Messages of one conversation, oldest first. RLS guarantees the caller
  /// can only read their own sessions.
  Future<List<QaMessage>> qaMessages(String sessionId) async {
    final c = _client;
    if (c == null || !_online || !isSignedIn) return const [];
    try {
      final rows = await c.from('qa_messages').select('id, role, content, citations, grounded, feedback, created_at')
          .eq('session_id', sessionId).order('created_at');
      return rows.map((r) => QaMessage.fromJson((r as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Record a thumb up/down on a stored assistant message.
  Future<void> submitQaFeedback(String messageId, int value) async {
    assert(value == 1 || value == -1, 'feedback must be +1 or -1');
    final c = _client;
    if (c == null || !_online || !isSignedIn) return;
    await c.from('qa_messages').update({'feedback': value}).eq('id', messageId);
  }

  /// Question starters shown on the empty Ask thread, from
  /// app_config['ask.suggested_questions'] ({en: [...], ml: [...]}). Falls
  /// back to English, then to nothing.
  Future<List<String>> askSuggestedQuestions(String locale) async {
    final c = _client;
    if (c == null || !_online) return const [];
    try {
      final row = await c.from('app_config').select('value').eq('key', 'ask.suggested_questions').maybeSingle();
      final v = row?['value'];
      if (v is! Map) return const [];
      final list = (v[locale] ?? v['en']) as List? ?? const [];
      return list.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------------- audio
  Future<String?> audioUrl(AudioTrack t) async {
    if (t.externalUrl != null) return t.externalUrl;
    final c = _client;
    if (c == null || t.storagePath == null) return null;
    // signed URL: bucket is private so rights-gated RLS on audio_tracks is the gate
    return c.storage.from('audio').createSignedUrl(t.storagePath!, 60 * 60);
  }

  // ---------------------------------------------------------- offline
  Future<void> downloadWork(String workSlug, {void Function(double)? onProgress}) async {
    final c = _client;
    if (c == null) {
      await store.importAssetBundle(workSlug);
      onProgress?.call(1);
      return;
    }
    final bundle = await c.rpc('get_work_bundle', params: {'p_work_slug': workSlug});
    onProgress?.call(0.8);
    await store.importBundle((bundle as Map).cast<String, dynamic>());
    onProgress?.call(1);
  }

  /// Warm the kv cache with the chapters adjacent to [sectionId] so moving
  /// between chapters stays instant and works offline. Opportunistic: no-op
  /// without backend/connectivity, failures are ignored.
  Future<void> prefetchAround(String workSlug, String sectionId) async {
    if (_client == null || !_online) return;
    try {
      final toc = await store.get('toc:$workSlug');
      if (toc == null) return;
      final chapters = Toc.fromJson((toc as Map).cast<String, dynamic>()).chapters;
      for (final id in adjacentChapterIds(chapters, sectionId)) {
        unawaited(chapter(id));
      }
    } catch (_) {/* prefetch is opportunistic */}
  }

  /// Metadata about the offline bundle in the cache (generation/import times).
  Future<Map<String, dynamic>?> bundleMeta(String workSlug) async =>
      (await store.get('bundle_meta:$workSlug')) as Map<String, dynamic>?;

  // -------------------------------------------------------- analytics
  /// Log an opt-in usage event. Callers gate on the analytics opt-in; this
  /// adds hard guards (signed-in, online) and swallows all failures —
  /// telemetry must never break the app. Events carry counts/facts only,
  /// never what was read, searched, or asked.
  Future<void> logAnalytics(String event, [Map<String, dynamic> payload = const {}]) async {
    final c = _client;
    if (c == null || !_online || !isSignedIn) return;
    try {
      await c.from('analytics_events').insert({'user_id': c.auth.currentUser!.id, 'event': event, 'payload': payload});
    } catch (_) {/* ignore */}
  }

  Future<bool> isDownloaded(String workSlug) => store.hasBundle(workSlug);
  Future<void> removeDownload(String workSlug) async {
    // Chapter cache keys are section-id based for RPC compatibility, so do
    // not delete every work's chapters when removing one download.
    final rawToc = await store.get('toc:$workSlug');
    if (rawToc is Map) {
      final toc = Toc.fromJson(rawToc.cast<String, dynamic>());
      for (final chapter in toc.chapters) {
        await store.delete('chapter:${chapter.id}');
      }
    }
    await store.delete('toc:$workSlug');
    await store.delete('editions:$workSlug');
    await store.delete('graph:$workSlug');
    await store.deletePrefix('verse:$workSlug:');
    await store.delete('bundle_meta:$workSlug');
    final remaining = (await store.bundleSlugs())..remove(workSlug);
    await store.put('bundle_slugs', remaining);
  }
}

class RepositoryException implements Exception {
  RepositoryException(this.message);
  final String message;
  @override
  String toString() => 'RepositoryException: $message';
}

/// Thrown when the `ask` Edge Function refuses the request because the
/// signed-in user reached their daily answer cap (HTTP 429).
class QaLimitException extends RepositoryException {
  QaLimitException(this.dailyCap) : super('daily answer cap reached');
  final int? dailyCap;
}

import 'package:collection/collection.dart';

/// Plain data classes mirroring the JSON shapes returned by the Supabase RPCs
/// (get_toc, get_section_verses, get_verse, search_verses, get_entity).
/// Kept hand-written (no codegen) so the app builds without build_runner.

class Work {
  final String id, slug, shortCode, titleIast, titleSa;
  final String? tradition, description;
  final List<Map<String, dynamic>> structure;
  Work.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        slug = j['slug'],
        shortCode = j['short_code'],
        titleIast = j['title_iast'],
        titleSa = j['title_sa'],
        tradition = j['tradition'],
        description = j['description'],
        structure = (j['structure'] as List? ?? []).cast<Map<String, dynamic>>();

  String levelLabel(int level, String lang) {
    final l = structure.firstWhereOrNull((s) => s['level'] == level);
    return l?['label_$lang'] ?? l?['label_iast'] ?? 'Section';
  }
}

class SectionNode {
  final String id, ref;
  final int level, ordinal, verseCount;
  final String? titleIast, titleSa, summary;
  final List<SectionNode> children;
  SectionNode.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        ref = j['ref'],
        level = j['level'],
        ordinal = j['ordinal'],
        verseCount = j['verse_count'] ?? 0,
        titleIast = j['title_iast'],
        titleSa = j['title_sa'],
        summary = j['summary'],
        children = (j['children'] as List? ?? []).map((c) => SectionNode.fromJson(c)).toList();

  Iterable<SectionNode> get leaves sync* {
    if (children.isEmpty) {
      yield this;
    } else {
      for (final c in children) {
        yield* c.leaves;
      }
    }
  }
}

class Toc {
  final Work work;
  final List<SectionNode> sections;
  Toc.fromJson(Map<String, dynamic> j)
      : work = Work.fromJson(j['work']),
        sections = (j['sections'] as List).map((s) => SectionNode.fromJson(s)).toList();
  List<SectionNode> get chapters => sections.expand((s) => s.leaves).toList();
}

class Edition {
  final String id, workId, slug, kind, languageCode, scriptCode, title, rightsStatus, attributionText;
  final String? license, licenseUrl, rightsHolder, sourceTitle, sourceUrl, description, languageNameEn, languageNameNative;
  final bool isDefault, isMachine;
  final int sortOrder;
  final List<String> contributors;
  Edition.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        workId = j['work_id'],
        slug = j['slug'],
        kind = j['kind'],
        languageCode = j['language_code'],
        scriptCode = j['script_code'],
        title = j['title'],
        rightsStatus = j['rights_status'] ?? 'unknown',
        attributionText = j['attribution_text'] ?? '',
        license = j['license'],
        licenseUrl = j['license_url'],
        rightsHolder = j['rights_holder'],
        sourceTitle = j['source_title'],
        sourceUrl = j['source_url'],
        description = j['description'],
        languageNameEn = j['language_name_en'],
        languageNameNative = j['language_name_native'],
        isDefault = j['is_default'] ?? false,
        isMachine = j['is_machine'] ?? false,
        sortOrder = j['sort_order'] ?? 100,
        contributors = (j['contributors'] as List? ?? []).cast<String>();

  bool get isBaseText => kind == 'base_text';
  bool get isTransliteration => kind == 'transliteration';
  bool get isTranslation => kind == 'translation';
  bool get isCleared => const {'public_domain', 'open_license', 'permission_granted', 'original'}.contains(rightsStatus);
}

class Rendering {
  final String editionId, kind, languageCode, scriptCode, body;
  final String? bodyHtml, notes;
  final List<Map<String, dynamic>>? wordMeanings, footnotes;
  Rendering.fromJson(Map<String, dynamic> j)
      : editionId = j['edition_id'],
        kind = j['kind'],
        languageCode = j['language_code'],
        scriptCode = j['script_code'],
        body = j['body'] ?? '',
        bodyHtml = j['body_html'],
        notes = j['notes'],
        wordMeanings = (j['word_meanings'] as List?)?.cast<Map<String, dynamic>>(),
        footnotes = (j['footnotes'] as List?)?.cast<Map<String, dynamic>>();
}

class Speaker {
  final String id, slug, nameIast, nameSa;
  Speaker.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        slug = j['slug'],
        nameIast = j['name_iast'],
        nameSa = j['name_sa'];
}

class AudioSegment {
  final String trackId;
  final int startMs, endMs;
  AudioSegment.fromJson(Map<String, dynamic> j)
      : trackId = j['track_id'],
        startMs = j['start_ms'],
        endMs = j['end_ms'];
}

class Verse {
  final String id, ref, kind;
  final int ordinal;
  final String? meter;
  final Speaker? speaker;
  final List<Rendering> renderings;
  final List<AudioSegment> audio;
  Verse.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        ref = j['ref'],
        kind = j['kind'] ?? 'verse',
        ordinal = j['ordinal'],
        meter = j['meter'],
        speaker = j['speaker'] == null ? null : Speaker.fromJson(j['speaker']),
        renderings = (j['renderings'] as List? ?? []).map((r) => Rendering.fromJson(r)).toList(),
        audio = (j['audio'] as List? ?? []).map((a) => AudioSegment.fromJson(a)).toList();

  Rendering? rendering(String editionId) => renderings.firstWhereOrNull((r) => r.editionId == editionId);
  Rendering? byKind(String kind, {String? lang}) =>
      renderings.firstWhereOrNull((r) => r.kind == kind && (lang == null || r.languageCode == lang));
}

class AudioTrack {
  final String id, editionId, title, kind, mimeType;
  final String? sectionId, storagePath, externalUrl;
  final int? durationMs;
  AudioTrack.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        editionId = j['edition_id'],
        title = j['title'],
        kind = j['kind'],
        mimeType = j['mime_type'] ?? 'audio/mp4',
        sectionId = j['section_id'],
        storagePath = j['storage_path'],
        externalUrl = j['external_url'],
        durationMs = j['duration_ms'];
}

class Chapter {
  final Map<String, dynamic> section;
  final List<Edition> editions;
  final List<Verse> verses;
  final List<AudioTrack> tracks;
  Chapter.fromJson(Map<String, dynamic> j)
      : section = j['section'],
        editions = (j['editions'] as List? ?? []).map((e) => Edition.fromJson(e)).toList(),
        verses = (j['verses'] as List? ?? []).map((v) => Verse.fromJson(v)).toList(),
        tracks = (j['tracks'] as List? ?? []).map((t) => AudioTrack.fromJson(t)).toList();
  String get ref => section['ref'];
  String get id => section['id'];
  Map<String, dynamic> get meta => (section['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
  String title(String lang) => meta['title_$lang'] ?? section['title_iast'] ?? ref;
  String? summary(String lang) => meta['summary_$lang'] ?? section['summary'];
}

class VerseDetail {
  final Map<String, dynamic> raw;
  final Verse verse;
  final List<Map<String, dynamic>> renderings, mentions, crossReferences;
  final String? prevRef, nextRef;
  VerseDetail.fromJson(Map<String, dynamic> j)
      : raw = j,
        verse = Verse.fromJson({...j['verse'], 'renderings': j['renderings'] ?? []}),
        renderings = (j['renderings'] as List? ?? []).cast<Map<String, dynamic>>(),
        mentions = (j['mentions'] as List? ?? []).cast<Map<String, dynamic>>(),
        crossReferences = (j['cross_references'] as List? ?? []).cast<Map<String, dynamic>>(),
        prevRef = j['prev_ref'],
        nextRef = j['next_ref'];
}

class SearchHit {
  final String verseId, ref, workSlug, editionId, editionTitle, languageCode, scriptCode, kind, snippet;
  final double rank;
  SearchHit.fromJson(Map<String, dynamic> j)
      : verseId = j['verse_id'],
        ref = j['ref'],
        workSlug = j['work_slug'],
        editionId = j['edition_id'],
        editionTitle = j['edition_title'],
        languageCode = j['language_code'],
        scriptCode = j['script_code'],
        kind = j['kind'],
        snippet = j['snippet'] ?? '',
        rank = (j['rank'] as num?)?.toDouble() ?? 0;
}

class EntityHit {
  final String kind, id, slug, nameIast, matchedName, languageCode;
  EntityHit.fromJson(Map<String, dynamic> j)
      : kind = j['entity_kind'],
        id = j['entity_id'],
        slug = j['slug'],
        nameIast = j['name_iast'],
        matchedName = j['matched_name'],
        languageCode = j['language_code'] ?? 'sa';
}

class Bookmark {
  final String id, verseId;
  final String? editionId, note, color, verseRef;
  final List<String> tags;
  final DateTime createdAt, updatedAt;
  Bookmark.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        verseId = j['verse_id'],
        editionId = j['edition_id'],
        note = j['note'],
        color = j['color'],
        verseRef = j['verse_ref'],
        tags = (j['tags'] as List? ?? []).cast<String>(),
        createdAt = DateTime.parse(j['created_at']),
        updatedAt = DateTime.parse(j['updated_at'] ?? j['created_at']);
  Map<String, dynamic> toJson() => {
        'id': id, 'verse_id': verseId, 'edition_id': editionId, 'note': note, 'color': color,
        'verse_ref': verseRef, 'tags': tags, 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String(),
      };
}

class ReadingProgress {
  final String workId, verseId;
  final String? sectionId, verseRef;
  final double percent;
  final DateTime lastReadAt;
  ReadingProgress.fromJson(Map<String, dynamic> j)
      : workId = j['work_id'],
        verseId = j['verse_id'],
        sectionId = j['section_id'],
        verseRef = j['verse_ref'],
        percent = (j['percent'] as num?)?.toDouble() ?? 0,
        lastReadAt = DateTime.parse(j['last_read_at']);
  Map<String, dynamic> toJson() => {
        'work_id': workId, 'verse_id': verseId, 'section_id': sectionId, 'verse_ref': verseRef,
        'percent': percent, 'last_read_at': lastReadAt.toIso8601String(),
      };
}

class Citation {
  final String verseId, ref, quote;
  final String? editionId, workSlug;
  Citation.fromJson(Map<String, dynamic> j)
      : verseId = j['verse_id'] ?? '',
        ref = j['ref'],
        quote = j['quote'] ?? '',
        editionId = j['edition_id'],
        workSlug = j['work_slug'];
}

class QaAnswer {
  final String answer;
  final List<Citation> citations;
  final bool grounded;
  final String? model;
  QaAnswer.fromJson(Map<String, dynamic> j)
      : answer = j['answer'] ?? '',
        citations = (j['citations'] as List? ?? []).map((c) => Citation.fromJson(c)).toList(),
        grounded = j['grounded'] ?? false,
        model = j['model'];
}

import '../db/models.dart';

/// Offline-resilience prefetch logic (pure, unit-tested).

/// Ids of the chapters immediately before/after [sectionId] within the work's
/// flat chapter list (previous first, then next — both only if they exist).
/// Prefetching these keeps swiping between chapters instant and offline-safe.
List<String> adjacentChapterIds(List<SectionNode> chapters, String sectionId) {
  final out = <String>[];
  final i = chapters.indexWhere((c) => c.id == sectionId);
  if (i < 0) return out;
  if (i > 0) out.add(chapters[i - 1].id);
  if (i < chapters.length - 1) out.add(chapters[i + 1].id);
  return out;
}

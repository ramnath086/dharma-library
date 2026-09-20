import 'package:dharma_library/core/db/models.dart';
import 'package:dharma_library/core/offline/prefetch.dart';
import 'package:flutter_test/flutter_test.dart';

SectionNode _ch(String id) => SectionNode.fromJson({
      'id': id, 'ref': id, 'level': 1, 'ordinal': int.parse(id), 'verse_count': 10, 'children': const [],
    });

void main() {
  final chapters = [_ch('1'), _ch('2'), _ch('3')];

  group('adjacentChapterIds', () {
    test('middle chapter returns previous then next', () {
      expect(adjacentChapterIds(chapters, '2'), ['1', '3']);
    });
    test('first chapter returns only next', () {
      expect(adjacentChapterIds(chapters, '1'), ['2']);
    });
    test('last chapter returns only previous', () {
      expect(adjacentChapterIds(chapters, '3'), ['2']);
    });
    test('unknown or single chapter returns empty', () {
      expect(adjacentChapterIds(chapters, 'x'), isEmpty);
      expect(adjacentChapterIds([_ch('1')], '1'), isEmpty);
      expect(adjacentChapterIds(const [], '1'), isEmpty);
    });
  });
}

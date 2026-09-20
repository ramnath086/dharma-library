import 'package:dharma_library/features/audio/segments.dart';
import 'package:dharma_library/core/db/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Verse verse(String id, List<List<int>> segs) => Verse.fromJson({
        'id': id, 'ref': '1.1.${id.substring(1)}', 'ordinal': 1, 'renderings': const [],
        'audio': [for (final s in segs) {'track_id': 't1', 'start_ms': s[0], 'end_ms': s[1]}],
      });
  final verses = [
    verse('v1', [[0, 10000]]),
    verse('v2', [[10000, 20000]]),
    verse('v3', [[20000, 30000], [40000, 45000]]), // two segments (refrain)
  ];

  group('segmentAt', () {
    test('finds the sounding verse at exact boundaries', () {
      expect(segmentAt(verses, 't1', 0)?.verseId, 'v1');
      expect(segmentAt(verses, 't1', 9999)?.verseId, 'v1');
      expect(segmentAt(verses, 't1', 10000)?.verseId, 'v2');
      expect(segmentAt(verses, 't1', 44999)?.verseId, 'v3');
    });
    test('null between segments, for unknown track, or out of range', () {
      expect(segmentAt(verses, 't1', 35000), isNull); // gap between v3's segments
      expect(segmentAt(verses, 'other', 5000), isNull);
      expect(segmentAt(verses, 't1', 45000), isNull);
    });
  });

  group('loopSeekTargetMs', () {
    test('returns the segment start once its end is crossed', () {
      expect(loopSeekTargetMs(verses, 't1', 'v2', 20000), 10000);
      expect(loopSeekTargetMs(verses, 't1', 'v2', 21000), 10000);
    });
    test('null while still inside the segment', () {
      expect(loopSeekTargetMs(verses, 't1', 'v2', 15000), isNull);
      expect(loopSeekTargetMs(verses, 't1', 'v2', 19999), isNull);
    });
    test('null for missing track or verse', () {
      expect(loopSeekTargetMs(verses, null, 'v2', 20000), isNull);
      expect(loopSeekTargetMs(verses, 't1', null, 20000), isNull);
      expect(loopSeekTargetMs(verses, 't1', 'nope', 20000), isNull);
    });
  });

  group('nextChantSpeed', () {
    test('cycles forward and wraps', () {
      expect(nextChantSpeed(0.5), 0.75);
      expect(nextChantSpeed(0.75), 1.0);
      expect(nextChantSpeed(1.0), 1.25);
      expect(nextChantSpeed(1.25), 1.5);
      expect(nextChantSpeed(1.5), 0.5);
    });
    test('values between steps pick the next faster speed', () {
      expect(nextChantSpeed(0.6), 0.75);
      expect(nextChantSpeed(1.1), 1.25);
    });
  });
}

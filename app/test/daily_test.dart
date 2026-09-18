import 'package:dharma_library/core/daily/daily.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dailyVerseIndex', () {
    test('deterministic per day and wraps over the corpus', () {
      expect(dailyVerseIndex(DateTime(2026, 1, 1), 10), 0);
      expect(dailyVerseIndex(DateTime(2026, 1, 10), 10), 9);
      expect(dailyVerseIndex(DateTime(2026, 1, 11), 10), 0); // wraps
      expect(dailyVerseIndex(DateTime(2026, 1, 31), 10), 0); // day 30 → 30 % 10
      expect(dailyVerseIndex(DateTime(2026, 3, 1), 10), dailyVerseIndex(DateTime(2026, 3, 1), 10));
      expect(dailyVerseIndex(DateTime(2026, 2, 29), 0), 0); // degenerate corpus
    });
  });

  group('isoDay', () {
    test('yyyy-MM-dd zero-padded', () {
      expect(isoDay(DateTime(2026, 2, 4)), '2026-02-04');
      expect(isoDay(DateTime(2026, 12, 25)), '2026-12-25');
    });
  });

  group('computeStreak', () {
    final today = DateTime(2026, 9, 18);
    test('empty history', () {
      expect(computeStreak(const {}, today: today), 0);
    });
    test('today only', () {
      expect(computeStreak({'2026-09-18'}, today: today), 1);
    });
    test('consecutive run ending today', () {
      expect(computeStreak({'2026-09-16', '2026-09-17', '2026-09-18'}, today: today), 3);
    });
    test('broken run stops at gap', () {
      expect(computeStreak({'2026-09-14', '2026-09-16', '2026-09-17', '2026-09-18'}, today: today), 3);
    });
    test('yesterday keeps the streak alive even without today', () {
      expect(computeStreak({'2026-09-16', '2026-09-17'}, today: today), 2);
    });
    test('older reads with no yesterday are stale', () {
      expect(computeStreak({'2026-09-16'}, today: today), 0);
    });
    test('duplicates do not inflate', () {
      expect(computeStreak({'2026-09-18', '2026-09-18', '2026-09-17'}, today: today), 2);
    });
  });
}

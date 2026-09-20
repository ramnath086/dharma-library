/// Pure daily-verse and streak logic (unit-tested).
///
/// The "daily verse" selects from the *already published* verses in the local
/// table of contents by a deterministic day-of-year index — no new content is
/// generated or ingested, a different existing verse simply surfaces each day.
library;

/// Deterministic wrap-around index of the verse for [day] out of [total].
int dailyVerseIndex(DateTime day, int total) {
  if (total <= 0) return 0;
  final doy = day.difference(DateTime(day.year, 1, 1)).inDays;
  return doy % total;
}

/// `yyyy-MM-dd` in local time — one stamp per day for streaks/resets.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Consecutive-day streak of [isoDates] ending today (or, if today hasn't
/// been logged yet, ending yesterday — the streak is still alive until the
/// day ends).
int computeStreak(Iterable<String> isoDates, {DateTime? today}) {
  final days = isoDates.toSet();
  if (days.isEmpty) return 0;
  var cur = today ?? DateTime.now();
  if (!days.contains(isoDay(cur))) {
    final yesterday = cur.subtract(const Duration(days: 1));
    if (!days.contains(isoDay(yesterday))) return 0;
    cur = yesterday;
  }
  var streak = 0;
  while (days.contains(isoDay(cur))) {
    streak++;
    cur = cur.subtract(const Duration(days: 1));
  }
  return streak;
}

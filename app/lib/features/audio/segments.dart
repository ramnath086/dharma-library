import '../../core/db/models.dart';

/// Pure audio-segment helpers (unit-tested). Chanting practice features build
/// on these: verse-follow highlighting, verse looping, and repeat seeks.

/// The verse + segment sounding in [trackId] at [ms], or null.
({String verseId, AudioSegment segment})? segmentAt(List<Verse> verses, String trackId, int ms) {
  for (final v in verses) {
    for (final a in v.audio) {
      if (a.trackId == trackId && ms >= a.startMs && ms < a.endMs) {
        return (verseId: v.id, segment: a);
      }
    }
  }
  return null;
}

/// Seek-back target for verse looping: the segment start of [verseId] once
/// playback has crossed its end; null while inside the segment (or when the
/// verse/track isn't found).
int? loopSeekTargetMs(List<Verse> verses, String? trackId, String? verseId, int ms) {
  if (trackId == null || verseId == null) return null;
  for (final v in verses) {
    if (v.id != verseId) continue;
    for (final a in v.audio) {
      if (a.trackId == trackId && ms >= a.endMs) return a.startMs;
    }
  }
  return null;
}

/// Size-bounded cycle for the chant playback speeds offered in the UI.
const chantSpeeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5];

/// Next speed in [chantSpeeds] after [current], wrapping to the slowest.
double nextChantSpeed(double current) {
  for (final s in chantSpeeds) {
    if (current < s) return s;
  }
  return chantSpeeds.first;
}

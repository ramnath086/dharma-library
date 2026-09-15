import 'dart:async';

import 'package:collection/collection.dart';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';

/// Audio architecture
/// ------------------
/// * One `audio_track` per chapter (or per verse group), stored in the private
///   Supabase Storage bucket `audio` or on an external CDN. Access is through
///   short-lived signed URLs, so RLS on `audio_tracks` (rights-gated via the
///   edition) is the single gate.
/// * `audio_segments` map [start_ms, end_ms] → verse, enabling
///   verse-highlighting during playback, "play from this verse", and
///   auto-scroll.
/// * Playback uses just_audio + audio_session (background audio & interruptions).
///   Downloaded tracks (offline) are served from the app's file cache via
///   `LockCachingAudioSource`.
class AudioState {
  const AudioState({this.track, this.chapter, this.playing = false, this.position = Duration.zero, this.duration, this.currentVerseId, this.error});
  final AudioTrack? track;
  final Chapter? chapter;
  final bool playing;
  final Duration position;
  final Duration? duration;
  final String? currentVerseId;
  final String? error;

  AudioState copyWith({AudioTrack? track, Chapter? chapter, bool? playing, Duration? position, Duration? duration, String? currentVerseId, String? error, bool clearError = false}) =>
      AudioState(
        track: track ?? this.track,
        chapter: chapter ?? this.chapter,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        currentVerseId: currentVerseId ?? this.currentVerseId,
        error: clearError ? null : (error ?? this.error),
      );
}

class AudioController extends Notifier<AudioState> {
  final _player = AudioPlayer();
  StreamSubscription? _posSub, _stateSub;
  bool _sessionReady = false;

  @override
  AudioState build() {
    ref.onDispose(() {
      _posSub?.cancel();
      _stateSub?.cancel();
      _player.dispose();
    });
    return const AudioState();
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _sessionReady = true;
  }

  Future<void> playChapter(Chapter ch, {Verse? fromVerse}) async {
    if (ch.tracks.isEmpty) return;
    final track = ch.tracks.first;
    try {
      await _ensureSession();
      if (state.track?.id != track.id) {
        final url = await ref.read(repositoryProvider).audioUrl(track);
        if (url == null) throw StateError('no audio url');
        // ignore: experimental_member_use  (offline replay cache; API stable in practice)
        await _player.setAudioSource(LockCachingAudioSource(Uri.parse(url)));
        state = state.copyWith(track: track, chapter: ch, duration: _player.duration, clearError: true);
        _posSub?.cancel();
        _posSub = _player.positionStream.listen(_onPosition);
        _stateSub?.cancel();
        _stateSub = _player.playerStateStream.listen((s) {
          state = state.copyWith(playing: s.playing && s.processingState != ProcessingState.completed);
        });
      }
      if (fromVerse != null) {
        final seg = fromVerse.audio.where((a) => a.trackId == track.id).firstOrNull;
        if (seg != null) await _player.seek(Duration(milliseconds: seg.startMs));
      }
      await _player.play();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void _onPosition(Duration p) {
    final ch = state.chapter;
    String? vid;
    if (ch != null) {
      final ms = p.inMilliseconds;
      for (final v in ch.verses) {
        if (v.audio.any((a) => a.trackId == state.track?.id && ms >= a.startMs && ms < a.endMs)) {
          vid = v.id;
          break;
        }
      }
    }
    state = state.copyWith(position: p, duration: _player.duration, currentVerseId: vid);
  }

  Future<void> toggle() async => state.playing ? _player.pause() : _player.play();
  Future<void> seek(Duration d) => _player.seek(d);
  Future<void> stop() async {
    await _player.stop();
    state = const AudioState();
  }
}

final audioControllerProvider = NotifierProvider<AudioController, AudioState>(AudioController.new);

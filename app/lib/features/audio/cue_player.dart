import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Plays the short original WAV cues shipped in `assets/audio/`.
/// Recitations still go through [AudioController]; this path never hits
/// Supabase Storage and never autoplays.
class CuePlayer {
  AudioPlayer? _player;

  Future<void> playAsset(String asset, {double volume = 0.45}) async {
    final player = _player ??= AudioPlayer();
    await player.stop();
    await player.setAsset(asset);
    await player.setVolume(volume.clamp(0.0, 1.0));
    await player.play();
  }

  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}

final cuePlayerProvider = Provider<CuePlayer>((ref) {
  final player = CuePlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

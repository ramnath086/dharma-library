import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';

/// Plays the launch bell at most once per process, and only when the user has
/// opted in. Default preference is OFF so the app is not noisy on first run
/// or in widget tests.
class LaunchChime extends ConsumerStatefulWidget {
  const LaunchChime({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LaunchChime> createState() => _LaunchChimeState();
}

class _LaunchChimeState extends ConsumerState<LaunchChime> {
  static bool _playedThisProcess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePlay());
  }

  Future<void> _maybePlay() async {
    if (_playedThisProcess || !mounted) return;
    final s = ref.read(settingsProvider);
    if (!s.devotionalSounds || !s.launchSound) return;
    _playedThisProcess = true;
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setAsset('assets/audio/launch_chime.wav');
      await player.setVolume(s.soundVolume.clamp(0.0, 1.0));
      await player.play();
      await player.playerStateStream.firstWhere((st) => st.processingState == ProcessingState.completed || !st.playing);
    } catch (_) {
      // Missing plugin / asset must never crash launch.
    } finally {
      try {
        await player?.dispose();
      } catch (_) {/* ignore */}
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

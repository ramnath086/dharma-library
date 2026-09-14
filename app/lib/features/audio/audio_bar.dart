import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_controller.dart';

class AudioBar extends ConsumerWidget {
  const AudioBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioControllerProvider);
    final c = ref.read(audioControllerProvider.notifier);
    final total = a.duration?.inMilliseconds ?? 0;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Slider(
            value: total == 0 ? 0 : a.position.inMilliseconds.clamp(0, total).toDouble(),
            max: total == 0 ? 1 : total.toDouble(),
            onChanged: total == 0 ? null : (v) => c.seek(Duration(milliseconds: v.round())),
          ),
          Row(children: [
            const SizedBox(width: 8),
            IconButton(icon: Icon(a.playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36), onPressed: c.toggle),
            Expanded(child: Text(a.track?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('${_fmt(a.position)} / ${_fmt(a.duration ?? Duration.zero)}', style: Theme.of(context).textTheme.labelSmall),
            IconButton(icon: const Icon(Icons.close), onPressed: c.stop),
          ]),
          if (a.error != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(a.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11))),
        ]),
      ),
    );
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

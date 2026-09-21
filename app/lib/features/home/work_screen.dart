import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/async_view.dart';

/// Per-work table of contents. Home is the catalogue of all published works;
/// this screen is one work's chapters.
class WorkScreen extends ConsumerWidget {
  const WorkScreen({super.key, required this.workSlug});
  final String workSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final toc = ref.watch(tocProvider(workSlug));
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: toc.maybeWhen(data: (t) => Text(t.work.titleIast), orElse: () => Text(l.loading))),
      body: AsyncView<Toc>(
        value: toc,
        onRetry: () => ref.invalidate(tocProvider(workSlug)),
        builder: (t) {
          ref.watch(userDataVersionProvider);
          final progress = ref.watch(progressProvider(t.work.id));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(work: t.work),
              const SizedBox(height: 8),
              if (t.work.description != null) Text(t.work.description!, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              progress.maybeWhen(
                data: (p) => _Continue(toc: t, progress: p, workSlug: workSlug),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              for (final section in t.sections) ...[
                if (section.children.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('${t.work.levelLabel(section.level, settings.locale)} ${section.ref} · ${section.titleIast ?? ''}', style: Theme.of(context).textTheme.titleMedium),
                  ),
                for (final ch in section.leaves)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(ch.ref.split('.').last)),
                      title: Text(ch.titleIast ?? ch.ref),
                      subtitle: Text('${t.work.levelLabel(ch.level, settings.locale)} · ${l.verses(ch.verseCount)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/read/$workSlug/chapter/${ch.id}'),
                    ),
                  ),
              ],
              if (t.work.isPilot)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  child: Text(l.endOfPilot, style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.work});
  final Work work;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [AppTheme.deepMaroon, AppTheme.saffron.withAlpha(217)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(work.titleSa, style: AppTheme.scriptStyle('Deva', fontSize: 26, color: Colors.white, weight: FontWeight.w600, height: 1.3)),
        const SizedBox(height: 4),
        Text(work.titleIast, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70)),
        if (work.tradition != null) ...[
          const SizedBox(height: 8),
          Text(work.tradition!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60)),
        ],
      ]),
    );
  }
}

class _Continue extends ConsumerWidget {
  const _Continue({required this.toc, required this.progress, required this.workSlug});
  final Toc toc;
  final ReadingProgress? progress;
  final String workSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final first = toc.chapters.isEmpty ? null : toc.chapters.first;
    final p = progress;
    final sectionId = p?.sectionId ?? first?.id;
    if (sectionId == null) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.play_circle_fill, size: 36),
        title: Text(p == null ? l.startReading : l.continueReading),
        subtitle: Text(p == null ? (first?.titleIast ?? '') : '${l.verse(p.verseRef ?? '')} · ${l.percentRead(p.percent.toStringAsFixed(0))}'),
        onTap: () => context.push('/read/$workSlug/chapter/$sectionId${p?.verseRef != null ? '?v=${p!.verseRef}' : ''}'),
      ),
    );
  }
}

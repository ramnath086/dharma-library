import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/async_view.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final slug = ref.watch(workSlugProvider);
    final toc = ref.watch(tocProvider(slug));
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: AsyncView<Toc>(
        value: toc,
        onRetry: () => ref.invalidate(tocProvider(slug)),
        builder: (t) {
          ref.watch(userDataVersionProvider);
          final progress = ref.watch(progressProvider(t.work.id));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tocProvider(slug)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _WorkHeader(work: t.work, script: settings.script),
                const SizedBox(height: 12),
                progress.maybeWhen(
                  data: (p) => _ContinueCard(toc: t, progress: p),
                  orElse: () => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                for (final canto in t.sections) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('${l.canto(canto.ref)} · ${canto.titleIast ?? ''}', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (final ch in canto.leaves)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(ch.ref.split('.').last)),
                        title: Text(ch.titleIast ?? l.chapter(ch.ref)),
                        subtitle: Text('${l.chapter(ch.ref.split('.').last)} · ${l.verses(ch.verseCount)}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/read/$slug/chapter/${ch.id}'),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Text(l.endOfPilot, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WorkHeader extends StatelessWidget {
  const _WorkHeader({required this.work, required this.script});
  final Work work;
  final String script;
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

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.toc, required this.progress});
  final Toc toc;
  final ReadingProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final slug = ref.watch(workSlugProvider);
    final first = toc.chapters.firstOrNull;
    final p = progress;
    final sectionId = p?.sectionId ?? first?.id;
    if (sectionId == null) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.play_circle_fill, size: 36),
        title: Text(p == null ? l.startReading : l.continueReading),
        subtitle: Text(p == null ? (first?.titleIast ?? '') : '${l.verse(p.verseRef ?? '')} · ${l.percentRead(p.percent.toStringAsFixed(0))}'),
        onTap: () => context.push('/read/$slug/chapter/$sectionId${p?.verseRef != null ? '?v=${p!.verseRef}' : ''}'),
      ),
    );
  }
}

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
                const SizedBox(height: 8),
                _StudyProgressCard(toc: t),
                const SizedBox(height: 8),
                const _QuickActions(),
                const SizedBox(height: 8),
                _RecentReadsStrip(workSlug: slug),
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

/// Reading footprint on this work: verses explored out of the total, with a
/// compact progress bar. Local-only stat (uses reading history).
class _StudyProgressCard extends ConsumerWidget {
  const _StudyProgressCard({required this.toc});
  final Toc toc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final total = toc.chapters.fold<int>(0, (n, c) => n + c.verseCount);
    final read = ref.watch(versesReadCountProvider).value ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.homeVersesRead(read, total), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: total == 0 ? 0 : (read / total).clamp(0.0, 1.0), minHeight: 8),
          ),
        ]),
      ),
    );
  }
}

/// Last five verses read (local history) as compact chips, with a "See all"
/// link to the full reading-history screen.
class _RecentReadsStrip extends ConsumerWidget {
  const _RecentReadsStrip({required this.workSlug});
  final String workSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final rows = ref.watch(readingHistoryProvider).value ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    final recent = rows.where((h) => h['verse_ref'] != null).take(5).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(l.recentlyRead, style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        TextButton(onPressed: () => context.push('/history'), child: Text(l.seeAll)),
      ]),
      SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: recent.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final ref_ = recent[i]['verse_ref'] as String;
            return ActionChip(
              avatar: const Icon(Icons.history, size: 16),
              label: Text('SB $ref_'),
              onPressed: () => context.push('/read/$workSlug/verse/$ref_'),
            );
          },
        ),
      ),
    ]);
  }
}

/// One-tap jumps to the app's other main sections (shell branches).
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      ActionChip(avatar: const Icon(Icons.search, size: 18), label: Text(l.tabSearch), onPressed: () => context.go('/search')),
      ActionChip(avatar: const Icon(Icons.auto_awesome_outlined, size: 18), label: Text(l.tabAsk), onPressed: () => context.go('/ask')),
      ActionChip(avatar: const Icon(Icons.bookmark_outline, size: 18), label: Text(l.tabBookmarks), onPressed: () => context.go('/bookmarks')),
    ]);
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

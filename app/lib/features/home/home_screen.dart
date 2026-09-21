import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/daily/daily.dart';
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
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: AsyncView<List<Toc>>(
        value: catalog,
        onRetry: () => ref.invalidate(catalogProvider),
        builder: (works) {
          ref.watch(userDataVersionProvider);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(catalogProvider);
              ref.invalidate(bundledWorksProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _DailyVerseCard(),
                _LibraryProgressCard(works: works),
                const SizedBox(height: 8),
                const _QuickActions(),
                const _RecentReadsStrip(),
                const SizedBox(height: 8),
                Text(l.publishedWorks, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (works.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(l.libraryEmpty, textAlign: TextAlign.center),
                  ),
                for (final toc in works) _WorkCard(toc: toc),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WorkCard extends ConsumerWidget {
  const _WorkCard({required this.toc});
  final Toc toc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final w = toc.work;
    final chapters = toc.chapters.length;
    final verses = toc.chapters.fold<int>(0, (n, c) => n + c.verseCount);
    final downloaded = ref.watch(downloadedProvider(w.slug)).value ?? false;
    final progress = ref.watch(progressProvider(w.id));
    final lang = switch (w.originalLanguage) {
      'sa' => l.langSa,
      'en' => l.langEn,
      'ml' => l.langMl,
      _ => w.originalLanguage,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          await ref.read(selectedWorkSlugProvider.notifier).select(w.slug);
          ref.invalidate(dailyVerseProvider);
          if (context.mounted) context.push('/library/${w.slug}');
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            label: l.workCoverSemantics(w.titleIast),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.deepMaroon, AppTheme.saffron.withAlpha(217)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.titleSa, style: AppTheme.scriptStyle('Deva', fontSize: 22, color: Colors.white, weight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 4),
                Text(w.titleIast, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70)),
                if (w.tradition != null) ...[
                  const SizedBox(height: 6),
                  Text(w.tradition!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60)),
                ],
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (w.description != null)
                Text(w.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                if (lang != null) Chip(visualDensity: VisualDensity.compact, label: Text(lang)),
                Chip(visualDensity: VisualDensity.compact, label: Text(l.chaptersCount(chapters))),
                Chip(visualDensity: VisualDensity.compact, label: Text(l.verses(verses))),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(downloaded ? Icons.offline_pin : Icons.cloud_outlined, size: 16),
                  label: Text(downloaded ? l.availableOffline : l.onlineOnly),
                ),
                if (w.isPilot) Chip(visualDensity: VisualDensity.compact, label: Text(l.pilotBadge(w.pilotScope ?? ''))),
              ]),
            ]),
          ),
          progress.maybeWhen(
            data: (p) => _ContinueTile(toc: toc, progress: p),
            orElse: () => const SizedBox.shrink(),
          ),
        ]),
      ),
    );
  }
}

class _ContinueTile extends ConsumerWidget {
  const _ContinueTile({required this.toc, required this.progress});
  final Toc toc;
  final ReadingProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final first = toc.chapters.firstOrNull;
    final p = progress;
    final sectionId = p?.sectionId ?? first?.id;
    if (sectionId == null) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.play_circle_fill),
      title: Text(p == null ? l.startReading : l.continueReading),
      subtitle: Text(p == null ? (first?.titleIast ?? '') : '${l.verse(p.verseRef ?? '')} · ${l.percentRead(p.percent.toStringAsFixed(0))}'),
      onTap: () async {
        await ref.read(selectedWorkSlugProvider.notifier).select(toc.work.slug);
        if (context.mounted) {
          context.push('/read/${toc.work.slug}/chapter/$sectionId${p?.verseRef != null ? '?v=${p!.verseRef}' : ''}');
        }
      },
    );
  }
}

class _LibraryProgressCard extends ConsumerWidget {
  const _LibraryProgressCard({required this.works});
  final List<Toc> works;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final total = works.fold<int>(0, (n, t) => n + t.chapters.fold<int>(0, (m, c) => m + c.verseCount));
    final read = ref.watch(versesReadCountProvider).value ?? 0;
    if (total == 0) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.homeVersesRead(read, total), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: (read / total).clamp(0.0, 1.0), minHeight: 8),
          ),
        ]),
      ),
    );
  }
}

class _DailyVerseCard extends ConsumerWidget {
  const _DailyVerseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final slug = ref.watch(workSlugProvider);
    final work = ref.watch(tocProvider(slug)).value?.work;
    final pick = ref.watch(dailyVerseProvider).value;
    if (pick == null) return const SizedBox.shrink();
    final streak = computeStreak(ref.watch(dailyReadsProvider));
    final v = pick.verse;
    final tr = v.renderings.firstWhereOrNull((r) => r.kind == 'translation' && r.languageCode == settings.effectiveTranslationLang) ??
        v.renderings.firstWhereOrNull((r) => r.kind == 'translation') ??
        v.renderings.firstOrNull;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.wb_sunny_outlined),
        title: Text('${l.dailyTitle} · ${work?.shortCode ?? slug} ${v.ref}', style: Theme.of(context).textTheme.labelLarge),
        subtitle: tr == null ? null : Text(tr.body, maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: streak > 0 ? Chip(visualDensity: VisualDensity.compact, label: Text(l.dailyStreak(streak))) : null,
        onTap: () {
          ref.read(dailyReadsProvider.notifier).markToday();
          if (ref.read(analyticsOptInProvider)) unawaited(ref.read(repositoryProvider).logAnalytics('daily_open'));
          context.push('/read/$slug/verse/${v.ref}');
        },
      ),
    );
  }
}

class _RecentReadsStrip extends ConsumerWidget {
  const _RecentReadsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final rows = ref.watch(readingHistoryProvider).value ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    final recent = rows.where((h) => h['verse_ref'] != null).take(5).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    final works = ref.watch(catalogProvider).value ?? const <Toc>[];
    final selected = ref.watch(workSlugProvider);
    String codeFor(String slug) => works.where((t) => t.work.slug == slug).firstOrNull?.work.shortCode ?? slug;
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
            final slug = (recent[i]['work_slug'] as String?) ?? selected;
            return ActionChip(
              avatar: const Icon(Icons.history, size: 16),
              label: Text('${codeFor(slug)} $ref_'),
              onPressed: () => context.push('/read/$slug/verse/$ref_'),
            );
          },
        ),
      ),
    ]);
  }
}

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

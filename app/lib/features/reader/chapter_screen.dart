import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/async_view.dart';
import '../audio/audio_controller.dart';
import '../audio/audio_bar.dart';
import 'attribution_sheet.dart';
import 'layout_sheet.dart';
import 'verse_card.dart';

class ChapterScreen extends ConsumerStatefulWidget {
  const ChapterScreen({super.key, required this.workSlug, required this.sectionId, this.scrollToRef});
  final String workSlug, sectionId;
  final String? scrollToRef;

  @override
  ConsumerState<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends ConsumerState<ChapterScreen> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  Timer? _progressDebounce;
  String? _lastRecordedRef;
  String? _lastFollowVerseId;
  bool _didInitialScroll = false;
  bool _didPrefetch = false;

  @override
  void dispose() {
    _scroll.dispose();
    _progressDebounce?.cancel();
    super.dispose();
  }

  void _scheduleProgress(Chapter ch, Toc toc) {
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 600), () {
      // The first verse whose card top is below the app bar is "current".
      Verse? current;
      for (final v in ch.verses) {
        final ctx = _keys[v.ref]?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y >= 80) {
          current = v;
          break;
        }
        current = v;
      }
      if (current == null || current.ref == _lastRecordedRef) return;
      _lastRecordedRef = current.ref;
      final position = _globalPosition(toc, ch, current);
      final total = toc.chapters.fold<int>(0, (n, c) => n + c.verseCount);
      ref.read(repositoryProvider).recordProgress(workId: toc.work.id, verse: current, sectionId: ch.id, totalVerses: total, position: position);
      ref.read(userDataVersionProvider.notifier).state++;
      ref.invalidate(progressProvider(toc.work.id));
    });
  }

  int _globalPosition(Toc toc, Chapter ch, Verse v) {
    var n = 0;
    for (final c in toc.chapters) {
      if (c.id == ch.id) return n + v.ordinal;
      n += c.verseCount;
    }
    return n + v.ordinal;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final chapter = ref.watch(chapterProvider(widget.sectionId));
    final toc = ref.watch(tocProvider(widget.workSlug));
    final audio = ref.watch(audioControllerProvider);

    // Chant practice: auto-scroll as the recitation advances through verses.
    String? followTo;
    if (audio.followText) followTo = audio.currentVerseId;
    if (followTo != null && followTo != _lastFollowVerseId) {
      _lastFollowVerseId = followTo;
      final ch = chapter.value;
      final v = ch?.verses.where((x) => x.id == followTo).firstOrNull;
      final ctx = v == null ? null : _keys[v.ref]?.currentContext;
      if (ctx != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: .25);
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: chapter.maybeWhen(data: (c) => Text(c.title(settings.locale), maxLines: 1, overflow: TextOverflow.ellipsis), orElse: () => Text(l.loading)),
        actions: [
          chapter.maybeWhen(
            data: (c) => IconButton(icon: const Icon(Icons.tune), tooltip: l.readerLayout, onPressed: () => showLayoutSheet(context, ref, c.editions)),
            orElse: () => const SizedBox.shrink(),
          ),
          chapter.maybeWhen(
            data: (c) => IconButton(icon: const Icon(Icons.info_outline), tooltip: l.attribution, onPressed: () => showAttributionSheet(context, c.editions)),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: AsyncView<Chapter>(
        value: chapter,
        onRetry: () => ref.invalidate(chapterProvider(widget.sectionId)),
        builder: (ch) {
          for (final v in ch.verses) {
            _keys.putIfAbsent(v.ref, GlobalKey.new);
          }
          if (!_didPrefetch) {
            _didPrefetch = true;
            unawaited(ref.read(repositoryProvider).prefetchAround(widget.workSlug, widget.sectionId));
          }
          if (!_didInitialScroll && widget.scrollToRef != null) {
            _didInitialScroll = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = _keys[widget.scrollToRef]?.currentContext;
              if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: .1);
            });
          }
          final t = toc.value;
          final chapters = t?.chapters ?? const <SectionNode>[];
          final idx = chapters.indexWhere((c) => c.id == ch.id);
          final prev = idx > 0 ? chapters[idx - 1] : null;
          final next = idx >= 0 && idx < chapters.length - 1 ? chapters[idx + 1] : null;
          final summary = ch.summary(settings.locale);

          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (t != null && n is ScrollUpdateNotification) _scheduleProgress(ch, t);
              return false;
            },
            child: Column(children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(top: 8, bottom: 96),
                  children: [
                    if (summary != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(summary, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                    if (ch.tracks.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.headphones),
                          label: Text('${l.play} · ${ch.tracks.first.title}'),
                          onPressed: () => ref.read(audioControllerProvider.notifier).playChapter(ch),
                        ),
                      ),
                    for (final v in ch.verses)
                      KeyedSubtree(
                        key: _keys[v.ref],
                        child: VerseCard(
                          verse: v,
                          editions: ch.editions,
                          workSlug: widget.workSlug,
                          workTitle: t?.work.titleIast,
                          highlighted: audio.currentVerseId == v.id || widget.scrollToRef == v.ref,
                          onPlay: ch.tracks.isEmpty ? null : () => ref.read(audioControllerProvider.notifier).playChapter(ch, fromVerse: v),
                        ),
                      ),
                    if (ch.meta['colophon_sa'] != null)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          Text(l.colophon, style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 4),
                          Text(ch.meta['colophon_sa'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                        ]),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        if (prev != null) OutlinedButton.icon(onPressed: () => context.pushReplacement('/read/${widget.workSlug}/chapter/${prev.id}'), icon: const Icon(Icons.chevron_left), label: Text(l.previousChapter)),
                        const Spacer(),
                        if (next != null)
                          FilledButton.icon(onPressed: () => context.pushReplacement('/read/${widget.workSlug}/chapter/${next.id}'), icon: const Icon(Icons.chevron_right), label: Text(l.nextChapter))
                        else
                          Flexible(child: Text((t?.work.isPilot ?? false) ? l.endOfPilot : l.endOfWork, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.end)),
                      ]),
                    ),
                  ],
                ),
              ),
              if (audio.track != null) const AudioBar(),
            ]),
          );
        },
      ),
    );
  }
}

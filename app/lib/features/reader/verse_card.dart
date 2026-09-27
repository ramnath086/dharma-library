import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../audio/cue_player.dart';
import '../../core/theme/app_theme.dart';
import '../../core/translit/translit.dart';
import '../../l10n/generated/app_localizations.dart';
import 'attribution_sheet.dart';

/// Renders one verse according to the user's reader layout:
/// base text (in the chosen script — converted on device if the server has no
/// pre-rendered edition for that script), IAST, translation in the chosen
/// language, optional word meanings. Each rendering shows its rights label.
class VerseCard extends ConsumerWidget {
  const VerseCard({
    super.key,
    required this.verse,
    required this.editions,
    required this.workSlug,
    this.workTitle,
    this.highlighted = false,
    this.compact = false,
    this.onPlay,
  });

  final Verse verse;
  final List<Edition> editions;
  final String workSlug;
  final String? workTitle;
  final bool highlighted;
  final bool compact;
  final VoidCallback? onPlay;

  Edition? _ed(String id) => editions.where((e) => e.id == id).firstOrNull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    ref.watch(userDataVersionProvider);
    final repo = ref.read(repositoryProvider);

    // ---- pick renderings
    final base = verse.byKind('base_text');
    final baseEd = base == null ? null : _ed(base.editionId);
    Rendering? scriptRendering;
    var convertedOnDevice = false;
    if (s.script == 'Deva') {
      scriptRendering = base;
    } else {
      scriptRendering = verse.renderings.where((r) => r.kind == 'transliteration' && r.scriptCode == s.script).firstOrNull;
      if (scriptRendering == null && base != null) convertedOnDevice = true;
    }
    final scriptEd = scriptRendering == null ? null : _ed(scriptRendering.editionId);
    final iast = verse.renderings.where((r) => r.kind == 'transliteration' && r.scriptCode == 'Latn').firstOrNull;
    final iastEd = iast == null ? null : _ed(iast.editionId);
    final lang = s.effectiveTranslationLang;
    final translation = verse.byKind('translation', lang: lang) ?? verse.byKind('translation', lang: 'en');
    final translationEd = translation == null ? null : _ed(translation.editionId);
    final wm = verse.byKind('word_meanings');

    final speakerLine = verse.speaker != null && verse.ordinal > 0 ? verse.speaker!.nameIast : null;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: compact ? 4 : 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: highlighted ? theme.colorScheme.primaryContainer.withAlpha(90) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlighted ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ---- header
        Row(children: [
          InkWell(
            onTap: () => context.push('/read/$workSlug/verse/${verse.ref}'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(verse.ref, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            ),
          ),
          if (verse.kind != 'verse') Chip(label: Text(verse.kind), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
          if (verse.meter != null) Padding(padding: const EdgeInsets.only(left: 6), child: Text(verse.meter!, style: theme.textTheme.labelSmall?.copyWith(fontStyle: FontStyle.italic))),
          const Spacer(),
          if (onPlay != null && verse.audio.isNotEmpty) IconButton(icon: const Icon(Icons.play_arrow), tooltip: l.play, onPressed: onPlay, visualDensity: VisualDensity.compact),
          if (verse.hasEditorialCue && s.devotionalSounds && s.slokaAudioCues)
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined),
              tooltip: l.playCue,
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final asset = verse.cueAsset;
                if (asset == null || asset.isEmpty) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.audioMissing)));
                  return;
                }
                try {
                  await ref.read(cuePlayerProvider).playAsset(asset, volume: s.soundVolume);
                } catch (_) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.audioMissing)));
                }
              },
            ),
          FutureBuilder<bool>(
            future: repo.isBookmarked(verse.id),
            builder: (c, snap) => IconButton(
              icon: Icon(snap.data == true ? Icons.bookmark : Icons.bookmark_outline),
              tooltip: snap.data == true ? l.removeBookmark : l.bookmark,
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await repo.toggleBookmark(verse, editionId: translationEd?.id);
                ref.read(userDataVersionProvider.notifier).state++;
                ref.invalidate(bookmarksProvider);
              },
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final text = _shareText(scriptRendering?.body ?? base?.body, iast?.body, translation?.body, translationEd);
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
              } else if (v == 'share') {
                await Share.share(text);
              } else if (v == 'rights') {
                if (context.mounted) showAttributionSheet(context, [baseEd, iastEd, scriptEd, translationEd].whereType<Edition>().toSet().toList());
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', child: ListTile(leading: const Icon(Icons.copy), title: Text(l.copy), dense: true)),
              PopupMenuItem(value: 'share', child: ListTile(leading: const Icon(Icons.share), title: Text(l.share), dense: true)),
              PopupMenuItem(value: 'rights', child: ListTile(leading: const Icon(Icons.info_outline), title: Text(l.attribution), dense: true)),
            ],
          ),
        ]),
        if (speakerLine != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('— $speakerLine', style: theme.textTheme.labelMedium?.copyWith(fontStyle: FontStyle.italic))),

        // ---- base text in chosen script
        if (s.showBaseText && base != null) ...[
          SelectableText(
            convertedOnDevice ? Translit.devaToScript(base.body, s.script) : (scriptRendering?.body ?? base.body),
            style: AppTheme.scriptStyle(s.script, fontSize: 21 * (compact ? .9 : 1), weight: FontWeight.w500),
            textAlign: TextAlign.start,
          ),
          if (convertedOnDevice || (scriptEd?.isMachine ?? false))
            _Label(icon: Icons.translate, text: l.machineTransliteration + (Translit.isLossy(s.script) ? ' · lossy' : '')),
          const SizedBox(height: 10),
        ],

        // ---- IAST (skip if already shown as chosen script)
        if (s.showTransliteration && iast != null && s.script != 'Latn') ...[
          SelectableText(iast.body, style: theme.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic, height: 1.6)),
          const SizedBox(height: 10),
        ],

        // ---- translation
        // When nothing was published for this verse we say so instead of
        // leaving a silent gap that reads as "not loaded yet". We never
        // substitute or invent a translation.
        if (s.showTranslation) ...[
          if (translation != null) ...[
            SelectableText(translation.body, style: AppTheme.scriptStyle(translation.scriptCode, fontSize: 17, height: 1.6, color: theme.textTheme.bodyLarge?.color)),
            if (translationEd != null) _Label(icon: Icons.verified_outlined, text: _rightsLabel(translationEd, l)),
          ] else
            _Label(icon: Icons.translate_outlined, text: l.translationUnavailable),
          const SizedBox(height: 6),
        ],

        // ---- word meanings (same disclosure rule as translations)
        if (s.showWordMeanings) ...[
          if (wm != null && wm.wordMeanings != null && wm.wordMeanings!.isNotEmpty) ...[
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l.wordMeanings, style: theme.textTheme.titleSmall),
              initiallyExpanded: !compact,
              children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final w in wm.wordMeanings!)
                    Chip(
                      label: RichText(text: TextSpan(style: theme.textTheme.bodySmall, children: [
                        TextSpan(text: '${w['word']} ', style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                        TextSpan(text: '${w['meaning']}'),
                      ])),
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
                const SizedBox(height: 8),
              ],
            ),
          ] else
            _Label(icon: Icons.list_alt, text: l.wordMeaningsUnavailable),
        ],
        if (translation?.notes != null && !compact)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(translation!.notes!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }

  String _rightsLabel(Edition e, AppLocalizations l) {
    final draft = e.title.toLowerCase().contains('draft') || e.title.contains('കരട്');
    return [if (draft) l.draftTranslation, e.license ?? e.rightsStatus, if (e.contributors.isNotEmpty) e.contributors.join(', ')].join(' · ');
  }

  String _shareText(String? base, String? iast, String? tr, Edition? trEd) {
    final b = StringBuffer('${workTitle ?? workSlug} ${verse.ref}\n\n');
    if (base != null) b.writeln('$base\n');
    if (iast != null) b.writeln('$iast\n');
    if (tr != null) b.writeln(tr);
    if (trEd != null) b.writeln('\n— ${trEd.attributionText}');
    b.writeln('\nDharma Library');
    return b.toString();
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Icon(icon, size: 12, color: t.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

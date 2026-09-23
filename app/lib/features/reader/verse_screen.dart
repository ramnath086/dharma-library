import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/async_view.dart';
import 'layout_sheet.dart';
import 'verse_card.dart';

/// Single-verse study view: all renderings, knowledge-graph mentions,
/// cross references, prev/next.
class VerseScreen extends ConsumerWidget {
  const VerseScreen({super.key, required this.workSlug, required this.verseRef});
  final String workSlug, verseRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final detail = ref.watch(verseProvider((work: workSlug, ref: verseRef)));
    final editions = ref.watch(editionsProvider(workSlug));
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.verse(verseRef)),
        actions: [
          editions.maybeWhen(data: (eds) => IconButton(icon: const Icon(Icons.tune), onPressed: () => showLayoutSheet(context, ref, eds)), orElse: () => const SizedBox.shrink()),
        ],
      ),
      body: AsyncView<VerseDetail>(
        value: detail,
        onRetry: () => ref.invalidate(verseProvider((work: workSlug, ref: verseRef))),
        builder: (d) {
          // Editions for the card: derive from renderings if the editions provider is not ready.
          final eds = editions.value ?? d.renderings.map((r) => Edition.fromJson({
                'id': r['edition_id'], 'work_id': '', 'slug': r['edition_slug'] ?? '', 'kind': r['kind'], 'language_code': r['language_code'],
                'script_code': r['script_code'], 'title': r['edition_title'] ?? r['kind'], 'rights_status': 'original',
                'attribution_text': r['attribution_text'] ?? '', 'license': r['license'], 'is_machine': r['is_machine'] ?? false,
              })).toList();
          final sectionId = d.raw['section']?['id'];
          final byKind = <String, List<Map<String, dynamic>>>{};
          for (final m in d.mentions) {
            byKind.putIfAbsent(m['entity_kind'], () => []).add(m);
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              VerseCard(verse: d.verse, editions: eds, workSlug: workSlug, workTitle: ref.watch(tocProvider(workSlug)).value?.work.titleIast),
              // ---- all translations (every language), so a reader can compare
              for (final r in d.renderings.where((r) => r['kind'] == 'translation' && r['language_code'] != settings.effectiveTranslationLang))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['edition_title'] ?? '', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        SelectableText(r['body'] ?? ''),
                      ]),
                    ),
                  ),
                ),
              if (d.mentions.isNotEmpty) ...[
                _SectionTitle(l.mentionedIn),
                for (final kind in const ['person', 'place', 'story', 'topic'])
                  if (byKind[kind] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final m in byKind[kind]!)
                          ActionChip(
                            avatar: Icon(_iconFor(kind), size: 16),
                            label: Text(m['name_iast'] ?? m['slug'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                            tooltip: m['surface_form'],
                            onPressed: m['slug'] == null ? null : () => context.push('/entity/$kind/${m['slug']}'),
                          ),
                      ]),
                    ),
              ],
              if (d.crossReferences.isNotEmpty) ...[
                _SectionTitle(l.crossReferences),
                for (final x in d.crossReferences)
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text('${x['work_slug'] == workSlug ? '' : '${x['work_slug']} '}${x['ref']}  ·  ${x['kind']}'),
                    subtitle: x['note'] == null ? null : Text(x['note']),
                    onTap: () => context.push('/read/${x['work_slug']}/verse/${x['ref']}'),
                  ),
              ],
              if ((d.raw['verse']?['metadata']?['pending_xrefs'] as List?)?.isNotEmpty ?? false) ...[
                _SectionTitle(l.relatedVerses),
                for (final x in d.raw['verse']['metadata']['pending_xrefs'])
                  ListTile(leading: const Icon(Icons.link_off), title: Text('${x['to']}  ·  ${x['kind']}'), subtitle: x['note'] == null ? null : Text(x['note']), enabled: false),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  if (d.prevRef != null) OutlinedButton.icon(onPressed: () => context.pushReplacement('/read/$workSlug/verse/${d.prevRef}'), icon: const Icon(Icons.chevron_left), label: Text(d.prevRef!)),
                  const Spacer(),
                  if (sectionId != null) TextButton(onPressed: () => context.push('/read/$workSlug/chapter/$sectionId?v=$verseRef'), child: Text(l.chapter(d.raw['section']['ref']))),
                  const Spacer(),
                  if (d.nextRef != null) FilledButton.icon(onPressed: () => context.pushReplacement('/read/$workSlug/verse/${d.nextRef}'), icon: const Icon(Icons.chevron_right), label: Text(d.nextRef!)),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) { 'person' => Icons.person_outline, 'place' => Icons.place_outlined, 'story' => Icons.auto_stories_outlined, _ => Icons.tag };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/async_view.dart';

/// Person / place / topic / story page: localized names, description,
/// relations, and every verse that mentions the entity.
class EntityScreen extends ConsumerWidget {
  const EntityScreen({super.key, required this.kind, required this.slug});
  final String kind, slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final data = ref.watch(entityProvider((kind: kind, slug: slug)));
    final workSlug = ref.watch(workSlugProvider);
    return Scaffold(
      appBar: AppBar(title: Text(switch (kind) { 'person' => l.people, 'place' => l.places, 'story' => l.stories, _ => l.topics })),
      body: AsyncView<Map<String, dynamic>>(
        value: data,
        onRetry: () => ref.invalidate(entityProvider((kind: kind, slug: slug))),
        builder: (d) {
          final e = (d['entity'] as Map).cast<String, dynamic>();
          final names = (d['names'] as List? ?? []).cast<Map<String, dynamic>>();
          final localName = names.where((n) => n['language_code'] == settings.locale).map((n) => n['name'] as String).firstOrNull;
          final verses = (d['verses'] as List? ?? []).cast<Map<String, dynamic>>();
          final relOut = (d['relations_out'] as List? ?? []).cast<Map<String, dynamic>>();
          final relIn = (d['relations_in'] as List? ?? []).cast<Map<String, dynamic>>();
          final iast = e['name_iast'] ?? e['title_iast'];
          final sa = e['name_sa'] ?? e['title_sa'];
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (sa != null) Text(sa, style: AppTheme.scriptStyle('Deva', fontSize: 28, weight: FontWeight.w600, height: 1.3)),
            Text(iast ?? slug, style: Theme.of(context).textTheme.headlineSmall),
            if (localName != null && localName != iast) Text(localName, style: AppTheme.scriptStyle(settings.locale == 'ml' ? 'Mlym' : 'Latn', fontSize: 18)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              if (e['kind'] != null) Chip(label: Text(e['kind']), visualDensity: VisualDensity.compact),
              for (final ep in (e['epithets'] as List? ?? e['alt_names'] as List? ?? [])) Chip(label: Text(ep), visualDensity: VisualDensity.compact),
            ]),
            if (e['description'] != null || e['summary'] != null) ...[
              const SizedBox(height: 12),
              Text(e['description'] ?? e['summary'], style: Theme.of(context).textTheme.bodyLarge),
            ],
            if (e['modern_name'] != null) ...[
              const SizedBox(height: 8),
              Row(children: [const Icon(Icons.place_outlined, size: 16), const SizedBox(width: 4), Expanded(child: Text(e['modern_name']))]),
            ],
            if (names.length > 1) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final n in names) if (n['name'] != iast && n['name'] != sa) Chip(label: Text('${n['name']}  ·  ${n['language_code']}'), visualDensity: VisualDensity.compact),
              ]),
            ],
            if (relOut.isNotEmpty || relIn.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l.relations, style: Theme.of(context).textTheme.titleSmall),
              for (final r in relOut) _RelationTile(label: '${r['relation']} →', kind: r['to_kind'], id: r['to_id'], note: r['note']),
              for (final r in relIn) _RelationTile(label: '← ${r['relation']}', kind: r['from_kind'], id: r['from_id'], note: r['note']),
            ],
            const SizedBox(height: 16),
            Text('${l.mentionedIn} (${verses.length})', style: Theme.of(context).textTheme.titleSmall),
            for (final v in verses)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 16, child: Text(v['ref'].toString().split('.').last, style: const TextStyle(fontSize: 12))),
                title: Text('SB ${v['ref']}'),
                subtitle: Text([v['role'], v['surface_form']].whereType<String>().join(' · ')),
                onTap: () => context.push('/read/${v['work_slug'] ?? workSlug}/verse/${v['ref']}'),
              ),
          ]);
        },
      ),
    );
  }
}

class _RelationTile extends ConsumerWidget {
  const _RelationTile({required this.label, required this.kind, required this.id, this.note});
  final String label, kind, id;
  final String? note;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workSlug = ref.watch(workSlugProvider);
    return FutureBuilder<Map<String, dynamic>?>(
      future: ref.read(repositoryProvider).graph(workSlug),
      builder: (c, snap) {
        final g = snap.data;
        Map<String, dynamic>? target;
        if (g != null) {
          final list = switch (kind) { 'person' => g['people'], 'place' => g['places'], 'topic' => g['topics'], 'story' => g['stories'], _ => null } as List?;
          target = list?.cast<Map<String, dynamic>>().where((x) => x['id'] == id).firstOrNull;
        }
        final name = target?['name_iast'] ?? target?['title_iast'] ?? kind;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Text(label, style: Theme.of(c).textTheme.labelMedium),
          title: Text(name),
          subtitle: note == null ? null : Text(note!),
          onTap: target == null || kind == 'work' ? null : () => context.push('/entity/$kind/${target!['slug']}'),
        );
      },
    );
  }
}

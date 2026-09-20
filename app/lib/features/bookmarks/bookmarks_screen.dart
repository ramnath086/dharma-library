import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/async_view.dart';

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    ref.watch(userDataVersionProvider);
    final bookmarks = ref.watch(bookmarksProvider);
    final tagFilter = ref.watch(bookmarkTagFilterProvider);
    final slug = ref.watch(workSlugProvider);
    final user = ref.watch(currentUserProvider);
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tabBookmarks),
        actions: [
          if (repo.hasBackend && user != null) IconButton(icon: const Icon(Icons.sync), onPressed: () async { await repo.syncUserData(); ref.invalidate(bookmarksProvider); }),
        ],
      ),
      body: Column(children: [
        if (repo.hasBackend && user == null)
          MaterialBanner(content: Text(l.signInHint), actions: [TextButton(onPressed: () => context.push('/sign-in'), child: Text(l.signIn))]),
        Expanded(
          child: AsyncView<List<Bookmark>>(
            value: bookmarks,
            builder: (list) {
              final allTags = {for (final b in list) ...b.tags}.toList()..sort();
              final filtered = tagFilter == null ? list : list.where((b) => b.tags.contains(tagFilter)).toList();
              return list.isEmpty
                  ? Center(child: Icon(Icons.bookmark_border, size: 64, color: Theme.of(context).colorScheme.outlineVariant))
                  : Column(children: [
                      if (allTags.isNotEmpty)
                        SizedBox(
                          height: 48,
                          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(label: Text(l.searchFilterAll), selected: tagFilter == null, onSelected: (_) => ref.read(bookmarkTagFilterProvider.notifier).state = null),
                            ),
                            for (final t in allTags)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(label: Text(t), selected: tagFilter == t, onSelected: (_) => ref.read(bookmarkTagFilterProvider.notifier).state = t),
                              ),
                          ]),
                        ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (c, i) {
                            final b = filtered[i];
                            return Dismissible(
                              key: ValueKey(b.id),
                              direction: DismissDirection.endToStart,
                              background: Container(color: Theme.of(c).colorScheme.errorContainer, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_outline)),
                              onDismissed: (_) async {
                                await repo.store.deleteBookmark(b.verseId);
                                repo.syncUserData();
                                ref.read(userDataVersionProvider.notifier).state++;
                                ref.invalidate(bookmarksProvider);
                              },
                              child: ListTile(
                                leading: const Icon(Icons.bookmark),
                                title: Text('SB ${b.verseRef ?? ''}'),
                                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if (b.note != null && b.note!.isNotEmpty) Text(b.note!, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if (b.tags.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Wrap(spacing: 4, runSpacing: 2, children: [for (final t in b.tags) _TagChip(t)]),
                                    ),
                                ]),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit_note),
                                  tooltip: l.addNote,
                                  onPressed: () => _editDetails(c, ref, l, repo, b),
                                ),
                                onTap: b.verseRef == null ? null : () => context.push('/read/$slug/verse/${b.verseRef}'),
                              ),
                            );
                          },
                        ),
                      ),
                    ]);
            },
          ),
        ),
      ]),
    );
  }

  /// Edit a bookmark's note and tags in one dialog; both are synced to the
  /// server by the repository's existing dirty-flag sync.
  Future<void> _editDetails(BuildContext context, WidgetRef ref, AppLocalizations l, dynamic repo, Bookmark b) async {
    final noteCtrl = TextEditingController(text: b.note);
    final tagCtrl = TextEditingController(text: b.tags.join(', '));
    final saved = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.addNote),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: noteCtrl, maxLines: 3, autofocus: true, decoration: InputDecoration(hintText: l.addNote)),
          const SizedBox(height: 8),
          TextField(controller: tagCtrl, decoration: InputDecoration(hintText: l.addTags, prefixIcon: const Icon(Icons.label_outline))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(l.genericCancel)),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(l.genericOk)),
        ],
      ),
    );
    if (saved == true) {
      final tags = tagCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      await repo.updateBookmarkNote(b.verseId, noteCtrl.text, tags: tags);
      ref.invalidate(bookmarksProvider);
    }
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.tag);
  final String tag;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(tag, style: Theme.of(context).textTheme.labelSmall),
      );
}

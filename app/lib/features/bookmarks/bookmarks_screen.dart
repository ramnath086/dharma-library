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
            builder: (list) => list.isEmpty
                ? Center(child: Icon(Icons.bookmark_border, size: 64, color: Theme.of(context).colorScheme.outlineVariant))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final b = list[i];
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
                          subtitle: b.note == null || b.note!.isEmpty ? null : Text(b.note!, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_note),
                            tooltip: l.addNote,
                            onPressed: () async {
                              final ctrl = TextEditingController(text: b.note);
                              final note = await showDialog<String>(
                                context: c,
                                builder: (d) => AlertDialog(
                                  title: Text(l.addNote),
                                  content: TextField(controller: ctrl, maxLines: 4, autofocus: true),
                                  actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('OK'))],
                                ),
                              );
                              if (note != null) {
                                await repo.updateBookmarkNote(b.verseId, note);
                                ref.invalidate(bookmarksProvider);
                              }
                            },
                          ),
                          onTap: b.verseRef == null ? null : () => context.push('/read/$slug/verse/${b.verseRef}'),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

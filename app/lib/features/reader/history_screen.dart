import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/async_view.dart';

/// On-device reading history (verse_reads + verse refs), newest first.
/// Local only; clearing it never touches bookmarks, progress, or the server.
class ReadingHistoryScreen extends ConsumerWidget {
  const ReadingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final history = ref.watch(readingHistoryProvider);
    final slug = ref.watch(workSlugProvider);
    final df = DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_Hm();
    return Scaffold(
      appBar: AppBar(title: Text(l.historyTitle), actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: l.historyClear,
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: Text(l.historyClear),
                content: Text(l.historyClearConfirm),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: Text(l.genericCancel)),
                  FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(l.genericOk)),
                ],
              ),
            );
            if (ok == true) {
              await ref.read(repositoryProvider).store.clearVerseReads();
              ref.read(userDataVersionProvider.notifier).state++;
            }
          },
        ),
      ]),
      body: AsyncView<List<Map<String, dynamic>>>(
        value: history,
        onRetry: () => ref.invalidate(readingHistoryProvider),
        builder: (rows) => rows.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history_toggle_off, size: 48, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 8),
                  Text(l.historyEmpty),
                ]),
              ))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final h = rows[i];
                  final ref_ = h['verse_ref'] as String?;
                  final at = DateTime.tryParse(h['read_at'] as String? ?? '');
                  return ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(ref_ != null ? 'SB $ref_' : l.historyTitle),
                    subtitle: at == null ? null : Text(df.format(at.toLocal())),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: ref_ == null ? null : () => context.push('/read/$slug/verse/$ref_'),
                  );
                },
              ),
      ),
    );
  }
}

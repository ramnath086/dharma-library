import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Past Ask Dharma conversations of the signed-in user. Sessions live only
/// server-side (qa_sessions) — this screen needs a session and a connection.
/// Tapping a conversation shows a read-only preview; "Continue" pops with the
/// session id, which [AskScreen] then loads into the live thread.
class QaHistoryScreen extends ConsumerWidget {
  const QaHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(repositoryProvider);
    ref.watch(authStateProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.askHistory)),
      body: !repo.isSignedIn || !repo.hasBackend
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l.askHistoryHint, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => context.push('/sign-in'), child: Text(l.signIn)),
            ])))
          : FutureBuilder<List<QaSession>>(
              future: repo.qaSessions(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final sessions = snap.data ?? const <QaSession>[];
                if (sessions.isEmpty) {
                  return Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.forum_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(l.askHistoryEmpty),
                      const SizedBox(height: 4),
                      Text(l.askHistoryHint, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ));
                }
                final df = DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_Hm();
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = sessions[i];
                    return ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(s.title?.isNotEmpty == true ? s.title! : l.askHistory, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: s.createdAt == null ? null : Text(df.format(s.createdAt!.toLocal())),
                      onTap: () => _preview(context, ref, s),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _preview(BuildContext context, WidgetRef ref, QaSession s) async {
    final l = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    final continueLabel = l.askContinue;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (sheetContext, scrollCtrl) => Column(children: [
          Expanded(
            child: FutureBuilder<List<QaMessage>>(
              future: repo.qaMessages(s.id),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final msgs = snap.data ?? const <QaMessage>[];
                if (msgs.isEmpty) return Center(child: Text(l.askHistoryEmpty));
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    return Align(
                      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
                        decoration: BoxDecoration(
                          color: m.isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(m.content, maxLines: m.isUser ? 6 : 12, overflow: TextOverflow.ellipsis),
                          if (m.citations.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(m.citations.map((e) => 'SB ${e.ref}').join(' · '), style: Theme.of(context).textTheme.bodySmall),
                            ),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(s.id),
                icon: const Icon(Icons.play_arrow),
                label: Text(continueLabel),
              ),
            ),
          ),
        ]),
      ),
    );
    if (chosen != null && context.mounted) context.pop(chosen);
  }
}

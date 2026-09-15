import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

class _Msg {
  _Msg.user(this.text) : answer = null, isUser = true;
  _Msg.bot(this.answer) : text = answer!.answer, isUser = false;
  final String text;
  final QaAnswer? answer;
  final bool isUser;
}

/// Grounded Q&A: every answer comes from the `ask` edge function, which
/// retrieves verses first and instructs the model to cite only those. The UI
/// renders citations as tappable chips that open the verse.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});
  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _ctrl = TextEditingController();
  final _msgs = <_Msg>[];
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() { _msgs.add(_Msg.user(q)); _busy = true; _error = null; _ctrl.clear(); });
    try {
      final a = await ref.read(repositoryProvider).ask(q, language: ref.read(settingsProvider).locale, workSlug: ref.read(workSlugProvider));
      setState(() => _msgs.add(_Msg.bot(a)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(repositoryProvider);
    final online = ref.watch(isOnlineProvider);
    final slug = ref.watch(workSlugProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.askTitle)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(l.askDisclaimer, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length + (_busy ? 1 : 0),
            itemBuilder: (c, i) {
              if (i == _msgs.length) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
              final m = _msgs[i];
              return Align(
                alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(c).width * .85),
                  decoration: BoxDecoration(
                    color: m.isUser ? Theme.of(c).colorScheme.primaryContainer : Theme.of(c).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: m.isUser
                      ? Text(m.text)
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          MarkdownBody(data: m.text.isEmpty ? l.askNoCitations : m.text),
                          if (m.answer!.citations.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              for (final cit in m.answer!.citations)
                                ActionChip(
                                  avatar: const Icon(Icons.format_quote, size: 14),
                                  label: Text('SB ${cit.ref}'),
                                  tooltip: cit.quote,
                                  onPressed: () => context.push('/read/${cit.workSlug ?? slug}/verse/${cit.ref}'),
                                ),
                            ]),
                          ],
                          if (!m.answer!.grounded) Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.askNoCitations, style: Theme.of(c).textTheme.bodySmall)),
                        ]),
                ),
              );
            },
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: !repo.hasBackend || !online
                ? Text(l.askOffline, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)
                : Row(children: [
                    Expanded(child: TextField(controller: _ctrl, decoration: InputDecoration(hintText: l.askHint, border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)), onSubmitted: (_) => _send(), textInputAction: TextInputAction.send, minLines: 1, maxLines: 4)),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
                  ]),
          ),
        ),
      ]),
    );
  }
}

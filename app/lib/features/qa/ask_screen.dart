import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/models.dart';
import '../../core/db/repository.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// One bubble in the thread. Built from a live [QaAnswer], or from a stored
/// [QaMessage] when a past conversation is opened from history.
class _Msg {
  _Msg.user(this.text) : isUser = true;
  _Msg.bot(QaAnswer a)
      : isUser = false,
        text = a.answer,
        citations = a.citations,
        grounded = a.grounded,
        messageId = a.messageId;
  _Msg.stored(QaMessage m)
      : isUser = m.isUser,
        text = m.content,
        citations = m.citations,
        grounded = m.grounded ?? true,
        messageId = m.id,
        feedback = m.feedback;

  final bool isUser;
  final String text;
  List<Citation> citations = const [];
  bool grounded = true;
  String? messageId;
  int? feedback;
}

/// Grounded Q&A ("Ask Dharma"): every answer comes from the `ask` edge
/// function, which retrieves verses first and instructs the model to cite
/// only those. The UI renders citations as tappable chips that open the
/// verse, keeps conversation continuity for signed-in users (the session is
/// created server-side on the first question), lets raters mark answers
/// helpful or not, and opens past conversations from `/ask/history`.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});
  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _ctrl = TextEditingController();
  final _msgs = <_Msg>[];
  String? _sessionId;
  bool _busy = false;
  String? _error;
  Future<List<String>>? _suggested;

  @override
  void initState() {
    super.initState();
    // Loaded once per screen entry; cheap (one app_config row) and not locale-
    // critical — a locale change mid-chat shouldn't reshuffle starters.
    _suggested = _loadSuggested();
  }

  Future<List<String>> _loadSuggested() =>
      ref.read(repositoryProvider).askSuggestedQuestions(ref.read(settingsProvider).locale);

  Future<void> _send() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() { _msgs.add(_Msg.user(q)); _busy = true; _error = null; _ctrl.clear(); });
    try {
      final a = await ref.read(repositoryProvider)
          .ask(q, language: ref.read(settingsProvider).locale, workSlug: ref.read(workSlugProvider), sessionId: _sessionId);
      _sessionId ??= a.sessionId; // adopt the conversation created server-side
      setState(() => _msgs.add(_Msg.bot(a)));
    } on QaLimitException catch (_) {
      setState(() => _error = AppLocalizations.of(context).askCapReached);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _newChat() async {
    if (_busy) return;
    setState(() { _msgs.clear(); _sessionId = null; _error = null; });
  }

  /// Pick a conversation from history and load its messages into the thread.
  Future<void> _openHistory() async {
    final sid = await context.push<String>('/ask/history');
    if (!mounted || sid == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final msgs = await ref.read(repositoryProvider).qaMessages(sid);
      setState(() {
        _sessionId = sid;
        _msgs
          ..clear()
          ..addAll(msgs.map(_Msg.stored));
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _rate(_Msg m, int value) async {
    final id = m.messageId;
    if (id == null) return;
    setState(() => m.feedback = value);
    try {
      await ref.read(repositoryProvider).submitQaFeedback(id, value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).askFeedbackThanks),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      setState(() { m.feedback = null; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(repositoryProvider);
    final online = ref.watch(isOnlineProvider);
    final slug = ref.watch(workSlugProvider);
    ref.watch(authStateProvider); // refresh sign-in-gated affordances on auth change
    final canAsk = repo.hasBackend && online;
    return Scaffold(
      appBar: AppBar(title: Text(l.askTitle), actions: [
        if (_sessionId != null || _msgs.isNotEmpty)
          IconButton(icon: const Icon(Icons.add_comment_outlined), tooltip: l.askNewChat, onPressed: _busy ? null : _newChat),
        if (repo.isSignedIn)
          IconButton(icon: const Icon(Icons.history), tooltip: l.askHistory, onPressed: _openHistory),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(l.askDisclaimer, style: Theme.of(context).textTheme.bodySmall)),
        if (!repo.isSignedIn && repo.hasBackend)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.askFeedbackSignInHint, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: _msgs.isEmpty && !_busy
              ? _Starters(l: l, suggested: _suggested, onPick: canAsk ? _pickSuggestion : null)
              : ListView.builder(
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
                                if (m.citations.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 6, runSpacing: 4, children: [
                                    for (final cit in m.citations)
                                      ActionChip(
                                        avatar: const Icon(Icons.format_quote, size: 14),
                                        label: Text('SB ${cit.ref}'),
                                        tooltip: cit.quote,
                                        onPressed: () => c.push('/read/${cit.workSlug ?? slug}/verse/${cit.ref}'),
                                      ),
                                  ]),
                                ],
                                if (!m.grounded || (m.messageId != null && repo.isSignedIn))
                                Row(children: [
                                  if (!m.grounded)
                                    Expanded(child: Text(l.askNoCitations, style: Theme.of(c).textTheme.bodySmall))
                                  else
                                    const Spacer(),
                                  if (m.messageId != null && repo.isSignedIn) ...[
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: l.askHelpful,
                                      icon: Icon(m.feedback == 1 ? Icons.thumb_up : Icons.thumb_up_outlined, size: 16,
                                          color: m.feedback == 1 ? Theme.of(c).colorScheme.primary : null),
                                      onPressed: () => _rate(m, 1),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: l.askNotHelpful,
                                      icon: Icon(m.feedback == -1 ? Icons.thumb_down : Icons.thumb_down_outlined, size: 16,
                                          color: m.feedback == -1 ? Theme.of(c).colorScheme.primary : null),
                                      onPressed: () => _rate(m, -1),
                                    ),
                                  ],
                                ]),
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
            child: !canAsk
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

  void _pickSuggestion(String q) {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
  }
}

/// Empty-thread state: a compact list of question starters from
/// app_config['ask.suggested_questions']. Disabled offline.
class _Starters extends StatelessWidget {
  const _Starters({required this.l, required this.suggested, required this.onPick});
  final AppLocalizations l;
  final Future<List<String>>? suggested;
  final void Function(String)? onPick;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: suggested,
      builder: (context, snap) {
        final items = snap.data ?? const <String>[];
        if (snap.hasError || items.isEmpty) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Icon(Icons.spa_outlined, size: 48, color: Theme.of(context).colorScheme.outline)));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.askSuggested, style: Theme.of(context).textTheme.titleSmall)),
            for (final q in items)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.help_outline, size: 20),
                  title: Text(q),
                  onTap: onPick == null ? null : () => onPick!(q),
                  enabled: onPick != null,
                ),
              ),
          ],
        );
      },
    );
  }
}

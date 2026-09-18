import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});
  final String? initialQuery;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _recentKey = 'recentSearches';

  late final _ctrl = TextEditingController(text: widget.initialQuery ?? '');
  Timer? _debounce;
  List<SearchHit> _hits = [];
  List<EntityHit> _entities = [];
  List<String> _recent = [];
  bool _loading = false;
  String? _lang; // null = all languages

  @override
  void initState() {
    super.initState();
    _recent = [...ref.read(prefsProvider).getStringList(_recentKey) ?? const <String>[]];
    if ((widget.initialQuery ?? '').isNotEmpty) _run(widget.initialQuery!);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  /// Keep the last eight successful searches (queries that found something);
  /// most recent first, no duplicates. Persisted device-wide in prefs.
  void _remember(String q) {
    setState(() => _recent = [q, ..._recent.where((e) => e != q)].take(8).toList());
    ref.read(prefsProvider).setStringList(_recentKey, _recent);
  }

  void _clearRecent() {
    setState(() => _recent = []);
    ref.read(prefsProvider).remove(_recentKey);
  }

  Future<void> _run(String q) async {
    q = q.trim();
    if (q.length < 2) {
      setState(() { _hits = []; _entities = []; });
      return;
    }
    setState(() => _loading = true);
    final repo = ref.read(repositoryProvider);
    final results = await Future.wait([
      repo.search(q, workSlug: ref.read(workSlugProvider), language: _lang),
      repo.searchEntities(q),
    ]);
    if (!mounted) return;
    setState(() {
      _hits = results[0] as List<SearchHit>;
      _entities = results[1] as List<EntityHit>;
      _loading = false;
    });
    if (_hits.isNotEmpty || _entities.isNotEmpty) _remember(q);
    if (mounted && ref.read(analyticsOptInProvider)) {
      unawaited(ref.read(repositoryProvider).logAnalytics(
            'search',
            {'hits': _hits.length + _entities.length, 'offline': !ref.read(isOnlineProvider)},
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final slug = ref.watch(workSlugProvider);
    // collapse hits by verse so one verse shows once with its best snippet
    final byVerse = <String, List<SearchHit>>{};
    for (final h in _hits) {
      byVerse.putIfAbsent(h.ref, () => []).add(h);
    }
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: widget.initialQuery == null,
          decoration: InputDecoration(hintText: l.searchHint, border: InputBorder.none, suffixIcon: _ctrl.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { _ctrl.clear(); _run(''); })),
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _run,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              for (final e in [(null, l.searchFilterAll), ('sa', 'संस्कृतम्'), ('en', 'English'), ('ml', 'മലയാളം')])
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: ChoiceChip(label: Text(e.$2), selected: _lang == e.$1, onSelected: (_) { setState(() => _lang = e.$1); _run(_ctrl.text); }),
                ),
            ]),
          ),
        ),
      ),
      body: _loading
          ? const LinearProgressIndicator()
          : _ctrl.text.trim().length < 2
              ? (_recent.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(l.searchTip, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)))
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      Row(children: [
                        Text(l.searchRecent, style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.clear_all), tooltip: l.searchClearRecent, onPressed: _clearRecent),
                      ]),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final q in _recent)
                          InputChip(
                            avatar: const Icon(Icons.history, size: 16),
                            label: Text(q),
                            onPressed: () { _ctrl.text = q; _run(q); },
                          ),
                      ]),
                      const SizedBox(height: 24),
                      Text(l.searchTip, style: Theme.of(context).textTheme.bodySmall),
                    ]))
              : (_hits.isEmpty && _entities.isEmpty)
                  ? Center(child: Text(l.searchNoResults(_ctrl.text)))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        if (_entities.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                            child: Wrap(spacing: 8, runSpacing: 4, children: [
                              for (final e in _entities)
                                ActionChip(
                                  avatar: Icon(switch (e.kind) { 'person' => Icons.person_outline, 'place' => Icons.place_outlined, 'story' => Icons.auto_stories_outlined, _ => Icons.tag }, size: 16),
                                  label: Text(e.matchedName == e.nameIast ? e.nameIast : '${e.matchedName} · ${e.nameIast}'),
                                  onPressed: () => context.push('/entity/${e.kind}/${e.slug}'),
                                ),
                            ]),
                          ),
                        for (final entry in byVerse.entries)
                          _HitTile(ref_: entry.key, hits: entry.value, onTap: () => context.push('/read/$slug/verse/${entry.key}')),
                      ],
                    ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.ref_, required this.hits, required this.onTap});
  final String ref_;
  final List<SearchHit> hits;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final best = hits.first;
    final t = Theme.of(context);
    return ListTile(
      onTap: onTap,
      isThreeLine: true,
      leading: CircleAvatar(radius: 22, child: Text(ref_.split('.').last)),
      title: Text('${best.workSlug == 'bhagavata-purana' ? 'SB' : best.workSlug} $ref_', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Snippet(best.snippet, best.scriptCode),
        Text(hits.map((h) => h.editionTitle).toSet().join(' · '), style: t.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _Snippet extends StatelessWidget {
  const _Snippet(this.text, this.script);
  final String text, script;
  @override
  Widget build(BuildContext context) {
    // server marks matches with « »
    final parts = text.split(RegExp('[«»]'));
    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      spans.add(TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold, backgroundColor: Color(0x33FFC107)) : null));
    }
    return RichText(maxLines: 3, overflow: TextOverflow.ellipsis, text: TextSpan(style: AppTheme.scriptStyle(script, fontSize: 15, height: 1.4, color: Theme.of(context).textTheme.bodyMedium?.color), children: spans));
  }
}

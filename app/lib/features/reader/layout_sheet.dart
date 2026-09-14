import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/models.dart';
import '../../core/providers.dart';
import '../../core/translit/translit.dart';
import '../../l10n/generated/app_localizations.dart';

/// Reader layout: toggles + script + translation language.
void showLayoutSheet(BuildContext context, WidgetRef ref, List<Edition> editions) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(builder: (c, ref, __) {
      final l = AppLocalizations.of(c);
      final s = ref.watch(settingsProvider);
      final n = ref.read(settingsProvider.notifier);
      final translationLangs = editions.where((e) => e.isTranslation).map((e) => e.languageCode).toSet().toList()..sort();
      final scriptNames = {for (final e in editions) e.scriptCode: e};
      return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), shrinkWrap: true, children: [
        Text(l.readerLayout, style: Theme.of(c).textTheme.titleLarge),
        Text(l.readerLayoutHint, style: Theme.of(c).textTheme.bodySmall),
        const SizedBox(height: 8),
        SwitchListTile(title: Text(l.sanskritText), value: s.showBaseText, onChanged: (v) => n.update((x) => x.copyWith(showBaseText: v))),
        SwitchListTile(title: Text(l.transliteration), subtitle: const Text('IAST'), value: s.showTransliteration, onChanged: (v) => n.update((x) => x.copyWith(showTransliteration: v))),
        SwitchListTile(title: Text(l.translation), value: s.showTranslation, onChanged: (v) => n.update((x) => x.copyWith(showTranslation: v))),
        SwitchListTile(title: Text(l.wordMeanings), value: s.showWordMeanings, onChanged: (v) => n.update((x) => x.copyWith(showWordMeanings: v))),
        const Divider(),
        ListTile(title: Text(l.script), subtitle: Text(_scriptLabel(s.script))),
        Wrap(spacing: 8, children: [
          for (final sc in Translit.supportedScripts)
            ChoiceChip(
              label: Text(_scriptLabel(sc)),
              selected: s.script == sc,
              onSelected: (_) => n.update((x) => x.copyWith(script: sc)),
              avatar: scriptNames.containsKey(sc) ? null : const Icon(Icons.smart_toy_outlined, size: 14),
            ),
        ]),
        const SizedBox(height: 12),
        ListTile(title: Text('${l.translation} · ${l.language}')),
        Wrap(spacing: 8, children: [
          for (final lang in translationLangs)
            ChoiceChip(label: Text(_langLabel(lang)), selected: s.effectiveTranslationLang == lang, onSelected: (_) => n.update((x) => x.copyWith(translationLang: lang))),
        ]),
        const SizedBox(height: 12),
        ListTile(title: Text(l.fontSize)),
        Slider(value: s.fontScale, min: .8, max: 1.6, divisions: 8, label: '${(s.fontScale * 100).round()}%', onChanged: (v) => n.update((x) => x.copyWith(fontScale: v))),
      ]);
    }),
  );
}

String _scriptLabel(String code) => switch (code) {
      'Deva' => 'देवनागरी',
      'Latn' => 'IAST',
      'Mlym' => 'മലയാളം',
      'Knda' => 'ಕನ್ನಡ',
      'Telu' => 'తెలుగు',
      'Beng' => 'বাংলা',
      'Gujr' => 'ગુજરાતી',
      'Guru' => 'ਗੁਰਮੁਖੀ',
      'Orya' => 'ଓଡ଼ିଆ',
      'Taml' => 'தமிழ்',
      _ => code,
    };

String _langLabel(String code) => switch (code) { 'en' => 'English', 'ml' => 'മലയാളം', 'hi' => 'हिन्दी', 'sa' => 'संस्कृतम्', _ => code };

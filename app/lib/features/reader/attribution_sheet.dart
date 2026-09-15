import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db/models.dart';
import '../../l10n/generated/app_localizations.dart';

/// Shows source + rights for the editions currently on screen. Rights are
/// mandatory in the data model, so this sheet can always be populated.
void showAttributionSheet(BuildContext context, List<Edition> editions) {
  final l = AppLocalizations.of(context);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      builder: (c, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(l.attribution, style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final e in editions) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, style: Theme.of(c).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(e.attributionText),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    Chip(avatar: const Icon(Icons.gavel, size: 16), label: Text('${l.license}: ${e.license ?? e.rightsStatus}'), visualDensity: VisualDensity.compact),
                    if (e.isMachine) Chip(avatar: const Icon(Icons.smart_toy_outlined, size: 16), label: Text(l.machineTransliteration), visualDensity: VisualDensity.compact),
                    Chip(label: Text('${e.languageNameEn ?? e.languageCode} · ${e.scriptCode}'), visualDensity: VisualDensity.compact),
                  ]),
                  if (e.sourceTitle != null) ...[
                    const SizedBox(height: 8),
                    Text('${l.source}: ${e.sourceTitle}', style: Theme.of(c).textTheme.bodySmall),
                  ],
                  if (e.sourceUrl != null || e.licenseUrl != null)
                    Row(children: [
                      if (e.sourceUrl != null) TextButton.icon(onPressed: () => launchUrl(Uri.parse(e.sourceUrl!), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new, size: 16), label: Text(l.source)),
                      if (e.licenseUrl != null) TextButton.icon(onPressed: () => launchUrl(Uri.parse(e.licenseUrl!), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new, size: 16), label: Text(l.license)),
                    ]),
                ]),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

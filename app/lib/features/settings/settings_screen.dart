import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final repo = ref.watch(repositoryProvider);
    final user = ref.watch(currentUserProvider);
    final role = ref.watch(userRoleProvider).value ?? 'reader';
    final slug = ref.watch(workSlugProvider);
    final downloaded = ref.watch(downloadedProvider(slug));

    return Scaffold(
      appBar: AppBar(title: Text(l.tabSettings)),
      body: ListView(children: [
        // ---- account
        if (repo.hasBackend)
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(user == null ? l.signIn : (user.email ?? user.id)),
            subtitle: user == null ? Text(l.signInHint) : Text(role),
            trailing: user == null ? const Icon(Icons.chevron_right) : TextButton(onPressed: () async { await repo.client!.auth.signOut(); await repo.store.clearUserData(); ref.read(userDataVersionProvider.notifier).state++; }, child: Text(l.signOut)),
            onTap: user == null ? () => context.push('/sign-in') : null,
          ),
        if (role == 'editor' || role == 'admin')
          ListTile(leading: const Icon(Icons.admin_panel_settings_outlined), title: Text(l.adminCms), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/admin')),
        const Divider(),

        // ---- language & appearance
        ListTile(title: Text(l.uiLanguage)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ml', label: Text('മലയാളം'))],
            selected: {s.locale},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(locale: v.first, clearTranslationLang: true)),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(title: Text(l.theme)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'system', label: Text(l.themeSystem)),
              ButtonSegment(value: 'light', label: Text(l.themeLight)),
              ButtonSegment(value: 'sepia', label: Text(l.themeSepia)),
              ButtonSegment(value: 'dark', label: Text(l.themeDark)),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(themeMode: v.first)),
          ),
        ),
        ListTile(title: Text(l.fontSize), subtitle: Slider(value: s.fontScale, min: .8, max: 1.6, divisions: 8, label: '${(s.fontScale * 100).round()}%', onChanged: (v) => n.update((x) => x.copyWith(fontScale: v)))),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: Text(l.dailyReminder),
          subtitle: Text(l.dailyReminderHint),
          value: ref.watch(dailyReminderProvider),
          onChanged: (v) async {
            ref.read(dailyReminderProvider.notifier).state = v;
            await ref.read(prefsProvider).setBool('dailyReminder', v);
          },
        ),
        const Divider(),

        // ---- offline
        downloaded.when(
          data: (isDl) => Column(children: [
            ListTile(
              leading: Icon(isDl ? Icons.offline_pin : Icons.download_for_offline_outlined),
              title: Text(isDl ? l.downloaded : l.downloadForOffline),
              subtitle: FutureBuilder<int>(future: repo.store.sizeBytes(), builder: (_, sn) => Text(l.storageUsed(((sn.data ?? 0) / 1e6).toStringAsFixed(1)))),
              trailing: isDl
                  ? TextButton(onPressed: () async { await repo.removeDownload(slug); ref.invalidate(downloadedProvider(slug)); }, child: Text(l.removeDownload))
                  : FilledButton.tonal(onPressed: () async {
                      await repo.downloadWork(slug);
                      ref.invalidate(downloadedProvider(slug));
                      if (ref.read(analyticsOptInProvider)) unawaited(repo.logAnalytics('offline_download'));
                    }, child: Text(l.downloadForOffline)),
            ),
            if (isDl)
              FutureBuilder<Map<String, dynamic>?>(
                future: repo.bundleMeta(slug),
                builder: (_, sn) {
                  final at = (sn.data?['imported_at'] as String?)?.substring(0, 10);
                  return at == null
                      ? const SizedBox.shrink()
                      : ListTile(dense: true, leading: const Icon(Icons.inventory_2_outlined), title: Text(l.bundleImported(at)));
                },
              ),
          ]),
          loading: () => const ListTile(title: LinearProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const Divider(),

        // ---- privacy
        ListTile(title: Text(l.privacyTitle)),
        SwitchListTile(
          secondary: const Icon(Icons.query_stats),
          title: Text(l.analyticsOptIn),
          subtitle: Text(l.analyticsOptInHint),
          value: ref.watch(analyticsOptInProvider),
          onChanged: (v) async {
            ref.read(analyticsOptInProvider.notifier).state = v;
            await ref.read(prefsProvider).setBool('analyticsOptIn', v);
          },
        ),
        ListTile(
          leading: const Icon(Icons.troubleshoot),
          title: Text(l.diagnosticsTitle),
          subtitle: Text(l.diagnosticsHint),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDiagnostics(context, ref, l),
        ),
        const Divider(),

        // ---- about
        AboutListTile(
          icon: const Icon(Icons.info_outline),
          applicationName: l.appTitle,
          applicationVersion: '0.1.0',
          aboutBoxChildren: [Text(l.aboutText)],
          child: Text(l.about),
        ),
      ]),
    );
  }

  /// On-device diagnostics: view, copy, or clear the local error log.
  Future<void> _showDiagnostics(BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final repo = ref.read(repositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.diagnosticsTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<String>>(
            future: repo.store.errorLog(),
            builder: (_, sn) {
              final log = sn.data ?? const <String>[];
              if (log.isEmpty) return Text(l.diagnosticsEmpty);
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(shrinkWrap: true, children: [
                  for (final e in log) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(e, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                ]),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () async { await repo.store.clearErrorLog(); if (d.mounted) Navigator.pop(d); }, child: Text(l.diagnosticsClear)),
          TextButton(
            onPressed: () async {
              final log = await repo.store.errorLog();
              await Clipboard.setData(ClipboardData(text: log.join('\n')));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.diagnosticsCopied)));
            },
            child: Text(l.diagnosticsCopy),
          ),
          FilledButton(onPressed: () => Navigator.pop(d), child: Text(l.genericOk)),
        ],
      ),
    );
  }
}

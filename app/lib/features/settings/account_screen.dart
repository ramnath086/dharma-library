import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_actions.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late final TextEditingController _name;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(profileProvider).value;
    final role = profile?['role'] as String? ?? ref.watch(userRoleProvider).value ?? 'reader';
    final existing = profile?['display_name'] as String?;
    if (_name.text.isEmpty && (existing ?? '').isNotEmpty) {
      _name.text = existing!;
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.accountTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l.accountHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(l.publicReadingAvailable, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline),
            title: Text(l.signedInAs),
            subtitle: Text(user?.email ?? user?.id ?? '—'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: Text(l.profileRole),
            subtitle: Text(role),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: l.displayName, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _saving ? null : () async {
              final client = ref.read(supabaseProvider);
              final uid = user?.id;
              if (client == null || uid == null) return;
              setState(() => _saving = true);
              try {
                await client.from('profiles').update({'display_name': _name.text.trim()}).eq('id', uid);
                ref.invalidate(profileProvider);
                if (mounted) setState(() => _status = l.saved);
              } catch (_) {
                if (mounted) setState(() => _status = l.errorGeneric);
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
            child: Text(l.saveDisplayName),
          ),
          if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
          const Divider(height: 32),
          FilledButton(
            onPressed: () async {
              await ref.read(authActionsProvider).signOut?.call();
              await ref.read(repositoryProvider).store.clearUserData();
              ref.read(userDataVersionProvider.notifier).state++;
              ref.invalidate(profileProvider);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(l.signOut),
          ),
        ],
      ),
    );
  }
}

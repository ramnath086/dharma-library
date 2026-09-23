import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Landing for `dharmalibrary://auth-callback`. supabase_flutter recovers the
/// PKCE session from the deep link; we wait for [currentUserProvider] then
/// sync user data. Reading still works if this never completes.
class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key});
  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 12), () {
      if (mounted) context.go('/');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _finishIfSignedIn());
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  Future<void> _finishIfSignedIn() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    await ref.read(repositoryProvider).syncUserData();
    ref.read(userDataVersionProvider.notifier).state++;
    ref.invalidate(profileProvider);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen(currentUserProvider, (prev, next) {
      if (next != null) unawaited(_finishIfSignedIn());
    });
    return Scaffold(
      appBar: AppBar(title: Text(l.authCallbackTitle)),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l.restoringSession),
          const SizedBox(height: 24),
          TextButton(onPressed: () => context.go('/'), child: Text(l.continueWithoutAccount)),
        ]),
      ),
    );
  }
}

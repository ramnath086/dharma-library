import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Passwordless email (magic link / OTP) sign-in. OAuth providers can be
/// enabled in supabase/config.toml and added here with signInWithOAuth.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;

  Future<void> _send() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(supabaseProvider)!.auth.signInWithOtp(email: _email.text.trim(), emailRedirectTo: AppConfig.authRedirect);
      setState(() => _sent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(supabaseProvider)!.auth.verifyOTP(type: OtpType.email, email: _email.text.trim(), token: _otp.text.trim());
      await ref.read(repositoryProvider).syncUserData();
      ref.read(userDataVersionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.signIn)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.signInHint),
          const SizedBox(height: 16),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: InputDecoration(labelText: l.email, border: const OutlineInputBorder()), enabled: !_sent),
          const SizedBox(height: 12),
          if (!_sent) FilledButton(onPressed: _busy ? null : _send, child: Text(l.sendMagicLink)),
          if (_sent) ...[
            Text(l.magicLinkSent),
            const SizedBox(height: 12),
            TextField(controller: _otp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Code (6 digits)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _verify, child: const Text('Verify')),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_actions.dart';
import '../../core/auth/auth_logic.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Passwordless email (magic link / 6-digit OTP). OAuth can be added later
/// via supabase/config.toml; reading is never gated on this screen.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  bool _sent = false, _busy = false;
  String? _errorKind;
  String? _errorRaw;
  DateTime? _resendAt;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  String? _mapError(AppLocalizations l, String? kind, String? raw) {
    return switch (kind) {
      'empty' => l.signInEmailEmpty,
      'invalid' => l.signInEmailInvalid,
      'expired' => l.signInExpired,
      'network' => l.signInNetworkError,
      'rate' => l.signInRateLimited,
      'disabled' => l.signInNeedsBackend,
      'code' => l.signInInvalidCode,
      'generic' => raw ?? l.errorGeneric,
      _ => raw,
    };
  }

  Future<void> _send() async {
    final kind = AuthLogic.emailError(_email.text);
    if (kind != null) {
      setState(() { _errorKind = kind; _errorRaw = null; });
      return;
    }
    final actions = ref.read(authActionsProvider);
    if (!actions.available) {
      setState(() { _errorKind = 'disabled'; _errorRaw = null; });
      return;
    }
    setState(() { _busy = true; _errorKind = null; _errorRaw = null; });
    try {
      await actions.sendOtp!(_email.text.trim(), AppConfig.authRedirect);
      if (!mounted) return;
      setState(() { _sent = true; _resendAt = DateTime.now().add(const Duration(seconds: 45)); });
    } catch (e) {
      setState(() { _errorKind = AuthLogic.classifyError(e); _errorRaw = e.toString(); });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final actions = ref.read(authActionsProvider);
    if (!actions.available) return;
    setState(() { _busy = true; _errorKind = null; _errorRaw = null; });
    try {
      await actions.verifyOtp!(_email.text.trim(), _otp.text.trim());
      await ref.read(repositoryProvider).syncUserData();
      ref.read(userDataVersionProvider.notifier).state++;
      ref.invalidate(profileProvider);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      setState(() { _errorKind = AuthLogic.classifyError(e); _errorRaw = e.toString(); });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canResend => _resendAt == null || DateTime.now().isAfter(_resendAt!);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final actions = ref.watch(authActionsProvider);
    final err = _mapError(l, _errorKind, _errorRaw);
    return Scaffold(
      appBar: AppBar(title: Text(l.signIn)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l.signInHint),
          const SizedBox(height: 8),
          Text(l.publicReadingAvailable, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(l.sessionPersists, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          if (!actions.available)
            Text(l.signInNeedsBackend, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: l.email, border: const OutlineInputBorder()),
              enabled: !_sent && !_busy,
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: 12),
            if (!_sent)
              FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(_busy ? l.sendingLink : l.sendMagicLink),
              ),
            if (_sent) ...[
              Text(l.magicLinkSent),
              const SizedBox(height: 12),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                decoration: InputDecoration(labelText: l.otpCodeLabel, border: const OutlineInputBorder()),
                enabled: !_busy,
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _verify,
                child: Text(_busy ? l.verifyingCode : l.verifyCode),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: (!_busy && _canResend) ? _send : null,
                child: Text(l.resendCode),
              ),
            ],
          ],
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 24),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.continueWithoutAccount)),
        ],
      ),
    );
  }
}

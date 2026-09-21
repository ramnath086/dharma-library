import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers.dart';

/// Injectable passwordless auth so Sign-in can be widget-tested without a
/// live Supabase project. Production wires this to [SupabaseClient.auth].
class AuthActions {
  const AuthActions({this.sendOtp, this.verifyOtp, this.signOut});

  final Future<void> Function(String email, String redirectTo)? sendOtp;
  final Future<void> Function(String email, String token)? verifyOtp;
  final Future<void> Function()? signOut;

  bool get available => sendOtp != null && verifyOtp != null;
}

final authActionsProvider = Provider<AuthActions>((ref) {
  final c = ref.watch(supabaseProvider);
  if (c == null) return const AuthActions();
  return AuthActions(
    sendOtp: (email, redirect) => c.auth.signInWithOtp(
      email: email,
      emailRedirectTo: redirect,
      shouldCreateUser: true,
    ),
    verifyOtp: (email, token) => c.auth.verifyOTP(
      type: OtpType.email,
      email: email,
      token: token,
    ),
    signOut: () => c.auth.signOut(),
  );
});

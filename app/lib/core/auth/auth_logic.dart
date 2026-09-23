/// Pure helpers for passwordless email auth. Kept free of Supabase so widget
/// and unit tests can exercise validation without a backend.
class AuthLogic {
  AuthLogic._();

  static final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Returns a stable error *kind* (`empty`, `invalid`) or null when the
  /// address is usable. The UI maps kinds to localised copy.
  static String? emailError(String email) {
    final t = email.trim();
    if (t.isEmpty) return 'empty';
    if (!emailPattern.hasMatch(t)) return 'invalid';
    return null;
  }

  static bool isEmail(String email) => emailError(email) == null;

  /// Collapse AuthException / network noise into a small set of kinds.
  static String classifyError(Object error) {
    final m = error.toString().toLowerCase();
    if (m.contains('otp_expired') || (m.contains('expired') && m.contains('otp'))) return 'expired';
    if (m.contains('otp_disabled')) return 'disabled';
    if (m.contains('rate') || m.contains('too many')) return 'rate';
    if (m.contains('invalid') && (m.contains('otp') || m.contains('token') || m.contains('code'))) {
      return 'code';
    }
    if (m.contains('network') || m.contains('socket') || m.contains('failed host') || m.contains('clientexception') || m.contains('timed out') || m.contains('timeout')) {
      return 'network';
    }
    return 'generic';
  }
}

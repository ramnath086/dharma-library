/// Build-time configuration.
///
/// Public Supabase values are injected with `--dart-define` (or
/// `--dart-define-from-file=env.json`) so no project keys live in git:
///
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// The anon key is a *public* key gated by RLS; the service-role key must never
/// be embedded in the app.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const defaultWorkSlug = String.fromEnvironment('DEFAULT_WORK', defaultValue: 'bhagavata-purana');
  static const authRedirect = 'dharmalibrary://auth-callback';

  /// When no Supabase project is configured the app runs in "bundle mode":
  /// content comes from the offline bundle shipped in assets/bundles/ and
  /// user data stays on-device. This keeps the app usable for reviewers and
  /// for CI screenshot tests without credentials.
  static bool get hasBackend => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

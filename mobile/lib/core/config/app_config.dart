/// Public, client-safe Supabase configuration — the same project the web
/// app talks to (see `.env.local` on the web side / `env.json` here).
/// Never put the service-role key here; only the anon key, which is safe
/// for a client because every table it touches is protected by RLS.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Used only as the redirect target for the password-reset email link —
  /// the web app already has a working `/reset-password` page, so mobile
  /// hands that step off to a browser rather than duplicating deep-link
  /// handling for it. Optional: when unset, Supabase falls back to the
  /// project's configured Site URL.
  static const String webAppUrl = String.fromEnvironment('WEB_APP_URL');

  /// Master switch for Inventory Management. While false the Profile menu entries are hidden and every /inventory
  /// route bounces to Home; the module's code is untouched, so turning it back on is changing this to true.
  static const bool inventoryEnabled = false;

  /// Shows a "Send test crash" button in Profile, to prove Crashlytics reports reach the Firebase console. Off unless the build is
  /// made with --dart-define=CRASH_TEST=true, so the button can never appear in the Play Store build.
  static const bool crashTestEnabled = bool.fromEnvironment('CRASH_TEST');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
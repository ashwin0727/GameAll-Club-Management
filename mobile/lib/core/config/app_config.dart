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

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
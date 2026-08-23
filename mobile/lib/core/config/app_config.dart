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

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
/// Compile-time environment values, injected via `--dart-define` at build
/// time. Per plan section 17: secrets never live inside the Flutter
/// codebase or get committed — these two are the Supabase *anon* key
/// (safe for client exposure by design, protected by RLS) and project
/// URL, not the service-role key. The service-role key belongs only in
/// the Compute Service backend, never here.
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

/// Compile-time environment values, injected via `--dart-define` at build
/// time. Per plan section 17: secrets never live inside the Flutter
/// codebase or get committed — these two are the Supabase *anon* key
/// (safe for client exposure by design, protected by RLS) and project
/// URL, not the service-role key. The service-role key belongs only in
/// the Compute Service backend, never here.
///
/// The anon key + URL below are intentionally public — they are the
/// standard Supabase client-side identifiers, protected by Row Level
/// Security (RLS), not by secrecy. They are equivalent to a public
/// API key and are safe to ship in client apps.
///
/// [cloudRunUrl] points to the Google Cloud Run FPL login service.
/// It is empty by default (falls back to manual Team ID entry on web)
/// and must be set at build time for the automated web login path to
/// be active. The value is the Cloud Run service URL returned by
/// `gcloud run deploy`, e.g.:
///   --dart-define=CLOUD_RUN_URL=https://fpl-login-xxxx-ew.a.run.app
///
/// Keeping it empty in development is intentional — the Team ID
/// fallback works without any server setup.
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://psgqhiqcxnupzbbunydx.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzZ3FoaXFjeG51cHpiYnVueWR4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0OTA3NjUsImV4cCI6MjEwNDA2Njc2NX0.DFjI1ou3kJgbgGB5gZmq4lrgyE_46XsfR8wUcuYZxKQ',
  );

  /// Google Cloud Run FPL login service URL.
  /// Empty = Cloud Run not configured → web falls back to manual Team ID.
  /// Set via: --dart-define=CLOUD_RUN_URL=https://fpl-login-xxxx-ew.a.run.app
  static const cloudRunUrl = String.fromEnvironment(
    'CLOUD_RUN_URL',
    defaultValue: '',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// True when the Cloud Run FPL login service URL has been provided.
  /// Controls whether web uses automated email+password login or falls
  /// back to manual Team ID entry.
  static bool get hasCloudRun => cloudRunUrl.isNotEmpty;
}

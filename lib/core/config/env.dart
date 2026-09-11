/// Compile-time environment values, injected via `--dart-define` at build
/// time.
///
/// Public client-side values:
/// - SUPABASE_URL
/// - SUPABASE_ANON_KEY
///
/// These are the Supabase project URL and publishable/anon key used by
/// Flutter. They are protected by Supabase RLS and are safe to expose in
/// the client application.
///
/// The FPL login service is a separate Supabase Edge Function hosted in
/// the FPL authentication project. It receives the FPL credentials over
/// HTTPS, authenticates against FPL, and returns the team information.
///
/// IMPORTANT:
/// - Never put SUPABASE_SERVICE_ROLE_KEY here.
/// - Never put an FPL password in this file.
/// - Never put any backend secret in Flutter code.
library;

class Env {
  Env._();

  // ── SquadIQ Supabase staging project ─────────────────────────────────

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wlhjcgvxlyvlhiecdbkh.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_OnySMS35xhG0IuqVtFL7Xg_SCNFaRwc',
  );

  // ── FPL login service ────────────────────────────────────────────────
  //
  // FastAPI backend running on Railway with outbound internet access.
  //
  // Flutter Web calls this endpoint directly over HTTPS.
  // The backend handles the server-side FPL login and returns the
  // FPL team information.

  static const fplLoginUrl = String.fromEnvironment(
    'FPL_LOGIN_URL',
    defaultValue:
        'https://security-first-fpl-production.up.railway.app/fpl/login',
  );

  // ── Configuration status ─────────────────────────────────────────────

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasFplLogin => fplLoginUrl.isNotEmpty;
}

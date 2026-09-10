import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/config/env.dart';
import '../../../core/error/result.dart';

/// Handles FPL account login and automatic team ID extraction.
///
/// ## Platform routing
///
/// **Native (mobile/desktop):**
/// POSTs directly to FPL's login endpoint, reads the `pl_profile` cookie,
/// calls `/api/me/`, extracts the team ID, wipes the cookie immediately.
/// The password never leaves the device after FPL confirms it.
///
/// **Web — Cloud Run path (when [Env.hasCloudRun] is true):**
/// Browsers cannot POST cross-origin with cookies (CORS + SameSite).
/// Supabase Edge Functions cannot reach FPL because Cloudflare datacenter
/// IPs are blocked at DNS level by FPL. The request is therefore forwarded
/// to a Google Cloud Run service which runs on Google IPs (not blocked).
/// The Flutter app attaches the user's Supabase JWT so Cloud Run can
/// verify identity before proxying to FPL. The password travels over
/// HTTPS and is discarded server-side after a single FPL call.
///
/// **Web — Team ID fallback (when [Env.hasCloudRun] is false):**
/// Cloud Run URL not configured → returns [AppFailureType.cloudRunNotConfigured]
/// so [LinkFplAccountScreen] can display the manual Team ID form.
/// This is the expected state in local development.
///
/// ## What is stored
/// - FPL password: NEVER stored anywhere.
/// - FPL session cookie: used once, then discarded. Briefly written to
///   [FlutterSecureStorage] on native only as a safety net in case the
///   app is killed mid-request; wiped unconditionally after `/me/`.
/// - FPL team ID: only item persisted (public integer in Supabase).
class FplAuthService {
  // ── FPL endpoints ──────────────────────────────────────────────────
  static const _fplLoginUrl = 'https://users.premierleague.com/accounts/login/';
  static const _fplMeUrl = 'https://fantasy.premierleague.com/api/me/';
  static const _cookieKey = 'fpl_session_cookie';

  final FlutterSecureStorage _secureStorage;

  FplAuthService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ── Public API ──────────────────────────────────────────────────────

  /// Returns the FPL team ID for the given credentials.
  ///
  /// - On native: calls FPL directly.
  /// - On web + Cloud Run configured: calls Cloud Run proxy.
  /// - On web + Cloud Run NOT configured: returns
  ///   [AppFailureType.cloudRunNotConfigured] so the caller can show
  ///   the manual Team ID form instead.
  Future<Result<int>> fetchTeamId({
    required String email,
    required String password,
  }) async {
    if (!kIsWeb) {
      return _fetchTeamIdNative(email: email, password: password);
    }

    if (!Env.hasCloudRun) {
      // Signal to the UI that Cloud Run isn't set up yet.
      // LinkFplAccountScreen uses this to show the Team ID fallback.
      return Result.err(const AppFailure(
        AppFailureType.cloudRunNotConfigured,
        'Cloud Run not configured',
      ));
    }

    return _fetchTeamIdViaCloudRun(email: email, password: password);
  }

  // ── Web path: Google Cloud Run proxy ───────────────────────────────

  Future<Result<int>> _fetchTeamIdViaCloudRun({
    required String email,
    required String password,
  }) async {
    // Attach the user's Supabase JWT so Cloud Run can verify identity.
    // The JWT is already in memory — we never ask the user for it.
    final session = sb.Supabase.instance.client.auth.currentSession;
    if (session == null) {
      return Result.err(const AppFailure(
        AppFailureType.unknown,
        'Not signed in. Please sign in to SquadIQ first.',
      ));
    }

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/json',
          // JWT — verified server-side by Cloud Run via Supabase JWKS
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ));

      final response = await dio.post(
        Env.cloudRunUrl,
        data: {'email': email, 'password': password},
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Result.err(const AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Unexpected response from server. Please try again.',
        ));
      }

      final raw = data['team_id'];
      final teamId = raw is int ? raw : (raw is num ? raw.toInt() : null);
      if (teamId == null) {
        return Result.err(const AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Could not read team ID. Please try again.',
        ));
      }

      return Result.ok(teamId);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final serverMsg = e.response?.data is Map
          ? (e.response!.data as Map)['error'] as String?
          : null;

      if (status == 401) {
        return Result.err(AppFailure(
          AppFailureType.unknown,
          serverMsg ?? 'FPL login failed. Check your email and password.',
        ));
      }
      if (status == 404) {
        return Result.err(AppFailure(
          AppFailureType.notFound,
          serverMsg ??
              'No FPL team found. Create one at fantasy.premierleague.com.',
        ));
      }
      if (status == 429) {
        return Result.err(AppFailure(
          AppFailureType.rateLimited,
          serverMsg ?? 'Too many attempts. Please wait 1 hour and try again.',
        ));
      }
      return Result.err(AppFailure(
        AppFailureType.network,
        serverMsg ?? 'Network error. Check your connection and try again.',
        cause: e,
      ));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  // ── Native path: direct to FPL ─────────────────────────────────────

  Future<Result<int>> _fetchTeamIdNative({
    required String email,
    required String password,
  }) async {
    try {
      // Step 1: POST credentials to FPL, capture session cookie
      final loginDio = Dio(BaseOptions(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': 'https://fantasy.premierleague.com/',
          'Origin': 'https://fantasy.premierleague.com',
        },
      ));

      final loginResponse = await loginDio.post(
        _fplLoginUrl,
        data: {
          'login': email,
          'password': password,
          'app': 'plfpl-web',
          'redirect_uri': 'https://fantasy.premierleague.com/',
        },
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final rawCookies =
          loginResponse.headers['set-cookie'] ?? const <String>[];
      final plProfile = _extractPlProfileCookie(rawCookies);

      if (plProfile == null) {
        return Result.err(const AppFailure(
          AppFailureType.unknown,
          'FPL login failed. Check your email and password.',
        ));
      }

      // Store temporarily — wiped unconditionally after /me/ call
      await _secureStorage.write(key: _cookieKey, value: plProfile);

      // Step 2: Call /me/ to get the team ID
      final meDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Cookie': plProfile,
          'Referer': 'https://fantasy.premierleague.com/',
        },
      ));

      final meResponse = await meDio.get(_fplMeUrl);
      final meData = meResponse.data;

      // Step 3: Wipe cookie — never persisted beyond this point
      await _secureStorage.delete(key: _cookieKey);

      if (meData is! Map<String, dynamic>) {
        return Result.err(const AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Unexpected response from FPL. Please try again.',
        ));
      }

      final entry = meData['entry'] as Map<String, dynamic>?;
      if (entry == null) {
        return Result.err(const AppFailure(
          AppFailureType.notFound,
          'No FPL team found for this account.\n'
          'Create a team at fantasy.premierleague.com first.',
        ));
      }

      final teamId = entry['id'] as int?;
      if (teamId == null) {
        return Result.err(const AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Could not read team ID from FPL. Please try again.',
        ));
      }

      return Result.ok(teamId);
    } on DioException catch (e) {
      await _secureStorage.delete(key: _cookieKey);
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return Result.err(const AppFailure(
          AppFailureType.unknown,
          'Incorrect email or password. Please try again.',
        ));
      }
      return Result.err(AppFailure(
        AppFailureType.network,
        'Network error — check your connection and try again.',
        cause: e,
      ));
    } catch (e) {
      await _secureStorage.delete(key: _cookieKey);
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  String? _extractPlProfileCookie(List<String> rawCookies) {
    for (final raw in rawCookies) {
      for (final part in raw.split(';')) {
        final trimmed = part.trim();
        if (trimmed.startsWith('pl_profile=')) return trimmed;
      }
    }
    return null;
  }
}

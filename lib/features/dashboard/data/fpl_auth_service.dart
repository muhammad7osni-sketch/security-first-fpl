import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/env.dart';
import '../../../core/error/result.dart';

/// Handles FPL account login and automatic team ID extraction.
///
/// On **mobile/desktop**: POSTs directly to FPL's login endpoint, reads
/// the pl_profile cookie, calls /me/, extracts the team ID, then wipes
/// the cookie immediately.
///
/// On **web**: The browser cannot make cross-origin POSTs with cookies to
/// FPL (CORS + SameSite restrictions). Instead, the request is routed
/// through a Supabase Edge Function (`fpl-login`) that runs server-side
/// and is not subject to browser restrictions. The Edge Function returns
/// only the team ID — the password and session cookie never leave FPL's
/// servers.
///
/// In both cases:
/// - The FPL password is NEVER stored anywhere by SquadIQ.
/// - Only the public integer team ID is persisted (in Supabase).
class FplAuthService {
  // Native (mobile/desktop) endpoints
  static const _fplLoginUrl = 'https://users.premierleague.com/accounts/login/';
  static const _fplMeUrl = 'https://fantasy.premierleague.com/api/me/';

  static const _cookieKey = 'fpl_session_cookie';

  final FlutterSecureStorage _secureStorage;

  FplAuthService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Returns the Supabase Edge Function URL for FPL login (web only).
  static String get _edgeFunctionUrl =>
      '${Env.supabaseUrl}/functions/v1/fpl-login';

  /// Logs in to FPL with [email] and [password] and returns the team ID.
  ///
  /// Routes through the Edge Function on web, directly to FPL on native.
  /// The password is never stored or logged anywhere.
  Future<Result<int>> fetchTeamId({
    required String email,
    required String password,
  }) async {
    if (kIsWeb) {
      return _fetchTeamIdViaEdgeFunction(email: email, password: password);
    }
    return _fetchTeamIdNative(email: email, password: password);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Web path: via Supabase Edge Function
  // ─────────────────────────────────────────────────────────────────────

  Future<Result<int>> _fetchTeamIdViaEdgeFunction({
    required String email,
    required String password,
  }) async {
    if (!Env.isConfigured) {
      return Result.err(const AppFailure(
        AppFailureType.unknown,
        'Missing Supabase config. Run with --dart-define=SUPABASE_URL=...',
      ));
    }

    try {
      final dio = Dio(BaseOptions(
        headers: {
          'Content-Type': 'application/json',
          'apikey': Env.supabaseAnonKey,
          'Authorization': 'Bearer ${Env.supabaseAnonKey}',
        },
      ));

      final response = await dio.post(
        _edgeFunctionUrl,
        data: {'email': email, 'password': password},
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Result.err(const AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Unexpected response from server. Please try again.',
        ));
      }

      final teamId = data['team_id'] as int?;
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
      return Result.err(AppFailure(
        AppFailureType.network,
        serverMsg ?? 'Network error. Check your connection and try again.',
        cause: e,
      ));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Native path: direct to FPL
  // ─────────────────────────────────────────────────────────────────────

  Future<Result<int>> _fetchTeamIdNative({
    required String email,
    required String password,
  }) async {
    try {
      // Step 1: Login and capture the session cookie
      final loginDio = Dio(BaseOptions(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
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
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
        ),
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

      // Store temporarily for the /me/ call
      await _secureStorage.write(key: _cookieKey, value: plProfile);

      // Step 2: Call /me/ to get the team ID
      final meDio = Dio(BaseOptions(
        headers: {
          'Cookie': plProfile,
          'Referer': 'https://fantasy.premierleague.com/',
        },
      ));

      final meResponse = await meDio.get(_fplMeUrl);
      final meData = meResponse.data;

      // Step 3: Wipe the cookie immediately
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

  // ─────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────

  String? _extractPlProfileCookie(List<String> rawCookies) {
    for (final raw in rawCookies) {
      final parts = raw.split(';');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.startsWith('pl_profile=')) {
          return trimmed;
        }
      }
    }
    return null;
  }
}

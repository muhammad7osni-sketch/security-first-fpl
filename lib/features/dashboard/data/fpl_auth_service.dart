import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/env.dart';
import '../../../core/error/result.dart';

/// Authenticates against FPL and extracts the user's team ID.
///
/// The FPL password is sent only over HTTPS and is never stored or logged.
/// The FPL session cookie is used only during the native flow and is then
/// deleted immediately.
class FplAuthService {
  static const _fplLoginUrl =
      'https://users.premierleague.com/accounts/login/';

  static const _fplMeUrl =
      'https://fantasy.premierleague.com/api/me/';

  static const _cookieKey = 'fpl_session_cookie';

  final FlutterSecureStorage _secureStorage;

  FplAuthService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Returns the FPL team ID for the supplied credentials.
  ///
  /// Web:
  ///   Calls the separate Supabase Edge Function.
  ///
  /// Native:
  ///   Calls FPL directly and temporarily uses the session cookie.
  Future<Result<int>> fetchTeamId({
    required String email,
    required String password,
  }) async {
    if (kIsWeb) {
      return _fetchTeamIdViaFplLogin(
        email: email,
        password: password,
      );
    }

    return _fetchTeamIdNative(
      email: email,
      password: password,
    );
  }

  // ── Web: Supabase Edge Function ─────────────────────────────────────

  Future<Result<int>> _fetchTeamIdViaFplLogin({
    required String email,
    required String password,
  }) async {
    if (!Env.hasFplLogin) {
      return Result.err(const AppFailure(
        AppFailureType.cloudRunNotConfigured,
        'FPL login service is not configured.',
      ));
    }

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {
          'Content-Type': 'application/json',
        },
      ));

      final response = await dio.post(
        Env.fplLoginUrl,
        data: {
          'email': email.trim(),
          'password': password,
        },
      );

      final data = response.data;

      if (data is! Map) {
        return Result.err(const AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Unexpected response from FPL login service.',
        ));
      }

      final rawTeamId = data['team_id'];
      final teamId = rawTeamId is int
          ? rawTeamId
          : rawTeamId is num
              ? rawTeamId.toInt()
              : null;

      if (teamId == null || teamId <= 0) {
        return Result.err(const AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Could not read your FPL team ID.',
        ));
      }

      return Result.ok(teamId);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final responseData = e.response?.data;

      final serverMessage = responseData is Map
          ? responseData['error']?.toString()
          : null;

      if (status == 401) {
        return Result.err(AppFailure(
          AppFailureType.unknown,
          serverMessage ?? 'Incorrect FPL email or password.',
        ));
      }

      if (status == 404) {
        return Result.err(AppFailure(
          AppFailureType.notFound,
          serverMessage ??
              'No FPL team was found for this account.',
        ));
      }

      if (status == 429) {
        return Result.err(AppFailure(
          AppFailureType.rateLimited,
          serverMessage ??
              'Too many login attempts. Please try again later.',
        ));
      }

      return Result.err(AppFailure(
        AppFailureType.network,
        serverMessage ??
            'Could not connect to the FPL login service.',
        cause: e,
      ));
    } catch (e) {
      return Result.err(AppFailure(
        AppFailureType.unknown,
        'FPL login failed. Please try again.',
        cause: e,
      ));
    }
  }

  // ── Native: direct FPL login ────────────────────────────────────────

  Future<Result<int>> _fetchTeamIdNative({
    required String email,
    required String password,
  }) async {
    try {
      final loginDio = Dio(BaseOptions(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': 'https://fantasy.premierleague.com/',
          'Origin': 'https://fantasy.premierleague.com',
        },
      ));

      final loginResponse = await loginDio.post(
        _fplLoginUrl,
        data: {
          'login': email.trim(),
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
          'Incorrect FPL email or password.',
        ));
      }

      await _secureStorage.write(
        key: _cookieKey,
        value: plProfile,
      );

      try {
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

        if (meData is! Map) {
          return Result.err(const AppFailure(
            AppFailureType.unexpectedResponseShape,
            'Unexpected response from FPL.',
          ));
        }

        final entry = meData['entry'];

        if (entry is! Map) {
          return Result.err(const AppFailure(
            AppFailureType.notFound,
            'No FPL team was found for this account.',
          ));
        }

        final rawTeamId = entry['id'];
        final teamId = rawTeamId is int
            ? rawTeamId
            : rawTeamId is num
                ? rawTeamId.toInt()
                : null;

        if (teamId == null || teamId <= 0) {
          return Result.err(const AppFailure(
            AppFailureType.unexpectedResponseShape,
            'Could not read your FPL team ID.',
          ));
        }

        return Result.ok(teamId);
      } finally {
        await _secureStorage.delete(key: _cookieKey);
      }
    } on DioException catch (e) {
      await _secureStorage.delete(key: _cookieKey);

      final status = e.response?.statusCode;

      if (status == 401 || status == 403) {
        return Result.err(const AppFailure(
          AppFailureType.unknown,
          'Incorrect FPL email or password.',
        ));
      }

      return Result.err(AppFailure(
        AppFailureType.network,
        'Could not connect to FPL.',
        cause: e,
      ));
    } catch (e) {
      await _secureStorage.delete(key: _cookieKey);

      return Result.err(AppFailure(
        AppFailureType.unknown,
        'FPL login failed. Please try again.',
        cause: e,
      ));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  String? _extractPlProfileCookie(List<String> rawCookies) {
    for (final raw in rawCookies) {
      for (final part in raw.split(';')) {
        final trimmed = part.trim();

        if (trimmed.startsWith('pl_profile=')) {
          return trimmed;
        }
      }
    }

    return null;
  }
}
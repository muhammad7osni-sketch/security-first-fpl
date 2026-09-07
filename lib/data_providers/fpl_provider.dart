import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/config/env.dart';
import '../core/error/result.dart';
import '../core/network/dio_client.dart';
import 'cache/ttl_cache.dart';
import 'fantasy_data_provider.dart';
import 'models/club.dart';
import 'models/fixture.dart';
import 'models/gameweek.dart';
import 'models/manager_entry.dart';
import 'models/manager_search_result.dart';
import 'models/player.dart';
import 'models/player_history_entry.dart';

/// Read-only adapter over FPL's public (unofficial, unauthenticated)
/// endpoints under fantasy.premierleague.com/api.
///
/// IMPORTANT — read plan section 0 before touching this file:
/// - These endpoints are not contractually supported by FPL. Reliability
///   is historically good but not guaranteed. This adapter must never
///   throw the whole app into an error state on a single failed call —
///   it always falls back to the last cached snapshot when one exists
///   (`CacheTtlPolicy` + `TtlCache.readStaleAllowed`).
/// - This adapter is READ-ONLY. There is intentionally no method here
///   that submits transfers, sets a captain, or plays a chip — see
///   `FantasyDataProvider`'s doc comment.
/// - Do not present this integration to users as an official FPL
///   partnership; it is not one.
///
/// PLATFORM ROUTING — read before changing `_resolveBaseUrl()`:
/// Flutter Web calls to fantasy.premierleague.com fail with a CORS
/// error — that's the *browser* enforcing same-origin policy on FPL's
/// response, not something fixable from the client side, and not a bug
/// in this adapter. Native platforms (Android/iOS/desktop) are not
/// subject to CORS at all, so they call FPL directly.
///
/// The fix for web is a small server-side proxy — the `fpl-api`
/// Supabase Edge Function (supabase/functions/fpl-api/index.ts) — which
/// forwards the request to FPL and attaches the CORS headers browsers
/// require. `_resolveBaseUrl()` below is the ONLY place that decides
/// which base URL to use, and it decides once, at construction — no
/// path in this class should silently fall back to any other host at
/// request time.
///
/// Do NOT reintroduce a public third-party CORS proxy (e.g.
/// allorigins.win or similar) here. That was tried and rejected: it
/// routes every user's FPL data through an uncontrolled third party
/// with no reliability or privacy guarantees, and FPL can block that
/// proxy's IP for everyone at once. The Edge Function is the only
/// sanctioned fix for the web CORS problem.
class FplProvider implements FantasyDataProvider {
  static const _fplDirectBaseUrl = 'https://fantasy.premierleague.com/api';

  final Dio _dio;
  final TtlCache<Map<String, dynamic>> _rawCache = TtlCache();

  FplProvider({Dio? dio})
      : _dio = dio ??
            DioClientFactory.build(
              baseUrl: _resolveBaseUrl(),
              // User-Agent is a forbidden header on web (browser blocks it).
              // On native it helps FPL edge nodes identify the client.
              defaultHeaders:
                  kIsWeb ? {} : {'User-Agent': 'SquadIQ/0.1 (+read-only)'},
            ) {
    // On web, the baseUrl points to the Supabase Edge Function which
    // expects the FPL path as a `?path=` query parameter, not a URL
    // segment. This interceptor rewrites every request transparently
    // so every call-site keeps using plain paths like `/bootstrap-static/`.
    if (kIsWeb) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final originalPath = options.path;
          options.path = '';
          options.queryParameters = {
            ...options.queryParameters,
            'path': originalPath,
          };
          handler.next(options);
        },
      ));
    }
  }

  /// Web -> routed through the `fpl-api` Edge Function (CORS-safe).
  /// Everything else -> straight to FPL, no intermediary.
  static String _resolveBaseUrl() {
    if (kIsWeb) {
      assert(
        Env.isConfigured,
        'SUPABASE_URL/SUPABASE_ANON_KEY must be set via --dart-define '
        'for Flutter Web builds — FPL calls are routed through the '
        'fpl-api Edge Function on web and have no direct fallback.',
      );
      return '${Env.supabaseUrl}/functions/v1/fpl-api';
    }
    return _fplDirectBaseUrl;
  }

  Future<Result<Map<String, dynamic>>> _getJson(
    String path, {
    required String cacheKey,
    Duration ttl = CacheTtlPolicy.normal,
  }) async {
    if (_rawCache.isFresh(cacheKey)) {
      return Result.ok(_rawCache.read(cacheKey)!);
    }

    try {
      final response = await _dio.get(path);
      if (response.data is! Map<String, dynamic>) {
        final stale = _rawCache.readStaleAllowed(cacheKey);
        if (stale != null) {
          return Result.ok(stale);
        }
        return Result.err(AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Unexpected response shape from $path',
        ));
      }
      final data = response.data as Map<String, dynamic>;
      _rawCache.write(cacheKey, data, ttl);
      return Result.ok(data);
    } on DioException catch (e) {
      final stale = _rawCache.readStaleAllowed(cacheKey);
      if (stale != null) {
        // Section 21 fallback: serve last-known-good data rather than an
        // error, but tag it so upstream (dashboard banner, AI context
        // builder) can say "data may be a few minutes old" instead of
        // presenting it as live.
        return Result.err(AppFailure(
          AppFailureType.servedStaleCache,
          'FPL endpoint unreachable, serving cached snapshot',
          cause: e,
        ));
      }
      return Result.err(_mapDioException(e, path));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  AppFailure _mapDioException(DioException e, String path) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AppFailure(AppFailureType.timeout, 'Timeout calling $path');
    }
    if (status == 404) {
      return AppFailure(AppFailureType.notFound, 'Not found: $path');
    }
    if (status == 429) {
      return AppFailure(AppFailureType.rateLimited, 'Rate limited: $path');
    }
    return AppFailure(
      AppFailureType.network,
      'Network error calling $path: ${e.message}',
      cause: e,
    );
  }

  /// `bootstrap-static` is FPL's single largest payload: all players, all
  /// clubs, and all gameweeks in one call. Fetched once and sliced three
  /// ways below rather than hit three times, per section 6's "don't
  /// blow up the context / rate limit" principle (same logic applies to
  /// plain HTTP quota, not just LLM context).
  Future<Result<Map<String, dynamic>>> _bootstrap() =>
      _getJson('/bootstrap-static/', cacheKey: 'bootstrap');

  @override
  Future<Result<List<Club>>> getClubs() async {
    final res = await _bootstrap();
    return res.when(
      ok: (json) {
        final list = (json['teams'] as List)
            .cast<Map<String, dynamic>>()
            .map(Club.fromFplJson)
            .toList();
        return Result.ok(list);
      },
      err: Result.err,
    );
  }

  @override
  Future<Result<List<Player>>> getPlayers() async {
    final res = await _bootstrap();
    return res.when(
      ok: (json) {
        final list = (json['elements'] as List)
            .cast<Map<String, dynamic>>()
            .map(Player.fromFplJson)
            .toList();
        return Result.ok(list);
      },
      err: Result.err,
    );
  }

  @override
  Future<Result<List<Gameweek>>> getGameweeks() async {
    final res = await _bootstrap();
    return res.when(
      ok: (json) {
        final list = (json['events'] as List)
            .cast<Map<String, dynamic>>()
            .map(Gameweek.fromFplJson)
            .toList();
        return Result.ok(list);
      },
      err: Result.err,
    );
  }

  @override
  Future<Result<List<Fixture>>> getFixtures({int? gameweekId}) async {
    // Fixtures are cached under their own key (much smaller payload,
    // updates more often than the bootstrap blob near deadlines).
    final path =
        gameweekId != null ? '/fixtures/?event=$gameweekId' : '/fixtures/';

    try {
      // Note: fixtures return a JSON *list*, not an object, so this skips
      // the shared `_getJson`/`_rawCache` helper (typed for Map results)
      // rather than force-casting. A list-aware cache wrapper is a
      // reasonable Phase 1 follow-up if fixture calls become frequent.
      final response = await _dio.get(path);
      if (response.data is! List) {
        return Result.err(AppFailure(
          AppFailureType.unexpectedResponseShape,
          'Unexpected response shape from $path',
        ));
      }
      final list = (response.data as List)
          .cast<Map<String, dynamic>>()
          .map(Fixture.fromFplJson)
          .toList();
      return Result.ok(list);
    } on DioException catch (e) {
      return Result.err(_mapDioException(e, path));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  @override
  Future<Result<ManagerEntry>> getManagerEntry(int managerId) async {
    final res = await _getJson(
      '/entry/$managerId/',
      cacheKey: 'entry_$managerId',
      ttl: const Duration(minutes: 10),
    );
    return res.when(
      ok: (json) => Result.ok(ManagerEntry.fromFplJson(json)),
      err: Result.err,
    );
  }

  @override
  Future<Result<List<SquadPick>>> getManagerPicks({
    required int managerId,
    required int gameweekId,
  }) async {
    final res = await _getJson(
      '/entry/$managerId/event/$gameweekId/picks/',
      cacheKey: 'picks_${managerId}_$gameweekId',
      ttl: CacheTtlPolicy.normal,
    );
    return res.when(
      ok: (json) {
        final picks = (json['picks'] as List)
            .cast<Map<String, dynamic>>()
            .map(SquadPick.fromFplJson)
            .toList();
        return Result.ok(picks);
      },
      err: Result.err,
    );
  }

  @override
  Future<Result<List<PlayerHistoryEntry>>> getPlayerHistory(
      int playerId) async {
    final res = await _getJson(
      '/element-summary/$playerId/',
      cacheKey: 'history_$playerId',
      ttl: const Duration(hours: 1),
    );
    return res.when(
      ok: (json) {
        final history = (json['history'] as List?) ?? [];
        final list = history
            .cast<Map<String, dynamic>>()
            .map(PlayerHistoryEntry.fromFplJson)
            .toList();
        return Result.ok(list);
      },
      err: Result.err,
    );
  }

  @override
  Future<Result<List<FplManagerSearchResult>>> searchManagers(
      String query) async {
    if (query.trim().isEmpty) return Result.ok([]);
    try {
      final response = await _dio.get(
        '/search/',
        queryParameters: {'text': query, 'page_size': 10},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Result.ok([]);
      }
      final results = (data['results'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(FplManagerSearchResult.fromFplJson)
          .toList();
      return Result.ok(results);
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.network, e.toString()));
    }
  }
}

import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

/// Builds a preconfigured [Dio] instance per data source.
///
/// Kept intentionally separate from any single provider so that swapping
/// FPL / API-Football / RotoWire adapters (plan section 6, "Adapter
/// pattern from day one") never touches shared networking concerns like
/// timeouts, retries, and headers.
class DioClientFactory {
  DioClientFactory._();

  static Dio build({
    required String baseUrl,
    Map<String, String> defaultHeaders = const {},
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 10),
    int maxRetries = 2,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: {
          'Accept': 'application/json',
          ...defaultHeaders,
        },
      ),
    );

    dio.interceptors.add(_RetryInterceptor(dio: dio, maxRetries: maxRetries));
    return dio;
  }
}

/// Retries idempotent GET requests on transient failures (timeouts, 429,
/// 5xx) with exponential backoff + jitter.
///
/// This matters most for the FPL public endpoints layer: per section 6/21
/// of the plan, that source has no contractual reliability guarantee, so
/// adapters must absorb brief blips instead of surfacing them as
/// user-facing errors immediately.
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Random _random = Random();

  _RetryInterceptor({required this.dio, required this.maxRetries});

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final attempt = (options.extra['retry_attempt'] as int?) ?? 0;

    final isRetryable = options.method.toUpperCase() == 'GET' &&
        attempt < maxRetries &&
        _isTransient(err);

    if (!isRetryable) {
      return handler.next(err);
    }

    final backoff = Duration(
      milliseconds: (300 * pow(2, attempt)).toInt() + _random.nextInt(200),
    );
    await Future.delayed(backoff);

    try {
      final retryOptions = options.copyWith(
        extra: {...options.extra, 'retry_attempt': attempt + 1},
      );
      final response = await dio.fetch(retryOptions);
      return handler.resolve(response);
    } catch (_) {
      return handler.next(err);
    }
  }

  bool _isTransient(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = err.response?.statusCode;
    return status == 429 || (status != null && status >= 500);
  }
}

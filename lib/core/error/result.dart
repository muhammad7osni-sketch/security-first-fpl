/// Simple Result/Either type used across the domain layer.
///
/// Per the plan (section 8): errors are surfaced explicitly instead of
/// thrown across layers, and per section 4's AI guardrails, a failed or
/// partial data fetch must be reported as "data unavailable" rather than
/// silently guessed at by any caller (including the AI orchestrator).
sealed class Result<T> {
  const Result();

  factory Result.ok(T value) = Ok<T>;
  factory Result.err(AppFailure failure) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  R when<R>({
    required R Function(T value) ok,
    required R Function(AppFailure failure) err,
  }) {
    final self = this;
    if (self is Ok<T>) return ok(self.value);
    if (self is Err<T>) return err(self.failure);
    throw StateError('Unreachable');
  }
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final AppFailure failure;
  const Err(this.failure);
}

/// Typed failures so the UI / AI context builder can distinguish
/// "endpoint unreachable" from "endpoint shape changed" from "stale cache
/// served" — this distinction matters directly for the risk in plan
/// section 21 ("FPL may change/kill the public endpoint without notice").
enum AppFailureType {
  network,
  timeout,
  unexpectedResponseShape,
  notFound,
  rateLimited,
  servedStaleCache,
  unknown,
}

/// Convenience accessors so call sites don't need pattern matching for
/// simple "bail out on error" flows.
extension ResultConvenience<T> on Result<T> {
  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;

  AppFailure? get failureOrNull => this is Err<T> ? (this as Err<T>).failure : null;
}

class AppFailure {
  final AppFailureType type;
  final String message;
  final Object? cause;

  const AppFailure(this.type, this.message, {this.cause});

  @override
  String toString() => 'AppFailure(${type.name}): $message';
}

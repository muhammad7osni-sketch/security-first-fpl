/// Minimal in-memory TTL cache.
///
/// This is a stand-in for the Redis cache layer in the target
/// architecture (plan section 7). It keeps the same interface
/// (`read`/`write`/`isStale`) so swapping in a Redis-backed
/// implementation later is a one-file change, not a rewrite of every
/// adapter that calls it.
class TtlCache<T> {
  final Map<String, _Entry<T>> _store = {};

  T? read(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) return null;
    return entry.value;
  }

  /// Returns the cached value even if expired — used for the fallback
  /// path in plan section 21 ("لو الـ Endpoint اتغيّر أو وقف، النظام
  /// يعتمد على آخر نسخة Cached"): serve stale data rather than nothing,
  /// while callers surface `AppFailureType.servedStaleCache` upstream.
  T? readStaleAllowed(String key) => _store[key]?.value;

  bool has(String key) => _store.containsKey(key);

  bool isFresh(String key) {
    final entry = _store[key];
    if (entry == null) return false;
    return DateTime.now().isBefore(entry.expiresAt);
  }

  void write(String key, T value, Duration ttl) {
    _store[key] = _Entry(value, DateTime.now().add(ttl));
  }

  void invalidate(String key) => _store.remove(key);
}

class _Entry<T> {
  final T value;
  final DateTime expiresAt;
  _Entry(this.value, this.expiresAt);
}

/// TTL policy per plan section 6: 15–30 min normally, tightened to ~1 min
/// close to a gameweek deadline (handled by callers choosing which TTL to
/// pass, based on `Gameweek.timeUntilDeadline`).
class CacheTtlPolicy {
  static const normal = Duration(minutes: 20);
  static const nearDeadline = Duration(minutes: 1);
  static const deadlineWindow = Duration(hours: 2);

  static Duration forTimeUntilDeadline(Duration? untilDeadline) {
    if (untilDeadline == null) return normal;
    if (untilDeadline <= deadlineWindow && untilDeadline > Duration.zero) {
      return nearDeadline;
    }
    return normal;
  }
}

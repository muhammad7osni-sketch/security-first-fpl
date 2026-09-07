import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/result.dart';
import '../../../data_providers/fantasy_data_provider.dart';
import '../domain/app_user.dart';

/// Wraps Supabase Auth + the app's own `users` table.
///
/// Two identities are kept deliberately separate, matching the schema:
/// `auth.users` (Supabase's own auth record — email/password or OAuth)
/// vs. our `users` row (app profile + `fpl_manager_id`). This repository
/// is the only place that bridges the two.
class AuthRepository {
  final sb.SupabaseClient _client;
  final FantasyDataProvider _fantasyDataProvider;

  AuthRepository(this._client, this._fantasyDataProvider);

  Stream<sb.AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  sb.User? get currentAuthUser => _client.auth.currentUser;

  Future<Result<sb.AuthResponse>> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response =
          await _client.auth.signUp(email: email, password: password);
      final authUser = response.user;
      if (authUser != null) {
        await _ensureAppUserRow(authUserId: authUser.id, email: email);
      }
      return Result.ok(response);
    } on sb.AuthException catch (e) {
      return Result.err(
          AppFailure(AppFailureType.unknown, e.message, cause: e));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  Future<Result<sb.AuthResponse>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth
          .signInWithPassword(email: email, password: password);
      return Result.ok(response);
    } on sb.AuthException catch (e) {
      return Result.err(
          AppFailure(AppFailureType.unknown, e.message, cause: e));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Creates the corresponding `users` row on first sign-up. Idempotent:
  /// relies on `auth_user_id` uniqueness, so a retried call is a no-op.
  Future<void> _ensureAppUserRow({
    required String authUserId,
    required String email,
  }) async {
    final existing = await _client
        .from('users')
        .select()
        .eq('auth_user_id', authUserId)
        .maybeSingle();

    if (existing != null) return;

    await _client.from('users').insert({
      'auth_user_id': authUserId,
      'email': email,
    });
  }

  Future<Result<AppUser>> getCurrentAppUser() async {
    final authUser = currentAuthUser;
    if (authUser == null) {
      return Result.err(
        const AppFailure(AppFailureType.unknown, 'Not signed in'),
      );
    }
    try {
      // Ensure the row exists first (idempotent on re-login).
      await _ensureAppUserRow(
        authUserId: authUser.id,
        email: authUser.email ?? '',
      );

      final row = await _client
          .from('users')
          .select()
          .eq('auth_user_id', authUser.id)
          .maybeSingle();

      if (row == null) {
        return Result.err(const AppFailure(
          AppFailureType.unknown,
          'User row not found after insert — try signing in again.',
        ));
      }
      return Result.ok(AppUser.fromSupabaseRow(row));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  /// Links a public FPL manager ID to the current app user, after
  /// verifying it actually resolves to a real manager via the read-only
  /// FPL adapter. This is the *only* connection this app ever makes to a
  /// user's official FPL account — a public numeric ID, no login, no
  /// password, no session cookie (plan section 0).
  Future<Result<AppUser>> linkFplManagerId(int fplManagerId) async {
    final lookup = await _fantasyDataProvider.getManagerEntry(fplManagerId);

    AppFailure? lookupFailure;
    lookup.when(ok: (_) {}, err: (f) => lookupFailure = f);
    if (lookupFailure != null) {
      final failure = lookupFailure!;
      return Result.err(AppFailure(
        failure.type,
        'Could not verify FPL manager ID $fplManagerId: ${failure.message}',
        cause: failure.cause,
      ));
    }

    final authUser = currentAuthUser;
    if (authUser == null) {
      return Result.err(
        const AppFailure(AppFailureType.unknown, 'Not signed in'),
      );
    }

    try {
      final row = await _client
          .from('users')
          .update({'fpl_manager_id': fplManagerId})
          .eq('auth_user_id', authUser.id)
          .select()
          .maybeSingle();

      if (row == null) {
        return Result.err(const AppFailure(
          AppFailureType.unknown,
          'Failed to update user — row not found.',
        ));
      }
      return Result.ok(AppUser.fromSupabaseRow(row));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }
}

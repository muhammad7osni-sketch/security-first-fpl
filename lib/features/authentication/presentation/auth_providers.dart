import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/providers.dart';
import '../data/auth_repository.dart';

final supabaseClientProvider = Provider<sb.SupabaseClient>((ref) {
  return sb.Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(fantasyDataProviderProvider),
  );
});

/// Emits whenever Supabase's auth state changes (sign in/out, token
/// refresh). Screens watch this instead of polling `currentAuthUser`.
final authStateChangesProvider = StreamProvider<sb.AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// The app's own `users` row for whoever is currently signed in — null
/// while signed out. Re-fetches whenever auth state changes.
final currentAppUserProvider = FutureProvider((ref) async {
  final authState = ref.watch(authStateChangesProvider).valueOrNull;
  final repo = ref.watch(authRepositoryProvider);
  if (authState?.session == null && repo.currentAuthUser == null) {
    return null;
  }
  final result = await repo.getCurrentAppUser();
  return result.when(ok: (user) => user, err: (_) => null);
});

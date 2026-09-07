import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../data/dashboard_repository.dart';
import '../data/fantasy_team_sync_service.dart';
import '../data/fpl_auth_service.dart';
import '../domain/dashboard_data.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(fantasyDataProviderProvider));
});

/// Provides the [FplAuthService] that handles FPL email/password login
/// and automatic team ID extraction (same approach as FFM).
final fplAuthServiceProvider = Provider<FplAuthService>((ref) {
  return FplAuthService();
});

/// Loads the dashboard for whichever FPL manager ID the signed-in user
/// has linked. Resolves to `null` (not an error) when no account is
/// linked yet, so the screen can show a "link your FPL account" prompt
/// instead of an error state.
final dashboardDataProvider = FutureProvider<DashboardData?>((ref) async {
  final appUser = await ref.watch(currentAppUserProvider.future);
  if (appUser == null || appUser.fplManagerId == null) {
    return null;
  }

  final repo = ref.watch(dashboardRepositoryProvider);
  final result = await repo.load(fplManagerId: appUser.fplManagerId!);

  return result.when(
    ok: (data) => data,
    err: (failure) => throw failure,
  );
});

final fantasyTeamSyncServiceProvider = Provider<FantasyTeamSyncService>((ref) {
  return FantasyTeamSyncService(ref.watch(supabaseClientProvider));
});

/// Upserts the current squad snapshot into `fantasy_teams` and returns
/// its row id, giving other features (Emergency Coach's audit log) a
/// real foreign key to write against. Resolves to `null` on failure or
/// when there's nothing to sync yet — callers that use this for
/// best-effort logging should treat `null` as "skip, don't block."
final fantasyTeamIdProvider = FutureProvider<String?>((ref) async {
  final appUser = await ref.watch(currentAppUserProvider.future);
  final data = await ref.watch(dashboardDataProvider.future);
  if (appUser == null || data == null) return null;

  final service = ref.watch(fantasyTeamSyncServiceProvider);
  final result = await service.syncTeam(appUserId: appUser.id, data: data);
  return result.when(ok: (id) => id, err: (_) => null);
});

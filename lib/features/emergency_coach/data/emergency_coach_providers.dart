import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../authentication/presentation/auth_providers.dart';
import '../../dashboard/presentation/dashboard_controller.dart';
import '../../statistics_engine/data/statistics_providers.dart';
import 'emergency_coach_repository.dart';
import '../domain/models/coach_models.dart';

final emergencyCoachRepositoryProvider =
    Provider<EmergencyCoachRepository>((ref) {
  sb.SupabaseClient? client;
  try {
    client = ref.watch(supabaseClientProvider);
  } catch (_) {
    client = null; // Supabase not configured (e.g. running without env vars)
  }
  return EmergencyCoachRepository(
    ref.watch(statisticsRepositoryProvider),
    client: client,
  );
});

/// Recomputes whenever the dashboard's squad data changes, so the coach
/// is never looking at a stale squad snapshot (plan section 11's single
/// source of truth rule).
final emergencyCoachPlanProvider =
    FutureProvider<EmergencyCoachPlan?>((ref) async {
  final dashboard = await ref.watch(dashboardDataProvider.future);
  if (dashboard == null) return null;

  final repo = ref.watch(emergencyCoachRepositoryProvider);
  final result = await repo.generatePlan(dashboard);

  final plan = result.when(ok: (plan) => plan, err: (failure) => throw failure);

  // Best-effort audit log (plan section 13) - never blocks the UI and
  // never turns into a user-facing error if it fails, since the plan
  // itself already rendered successfully by this point.
  if (!plan.isAllClear) {
    ref.read(fantasyTeamIdProvider.future).then((teamId) {
      if (teamId == null) return;
      repo.recordEvent(
        plan: plan,
        fantasyTeamId: teamId,
        gameweekId: dashboard.currentGameweek.id,
      );
    }).catchError((_) {
      // Best-effort audit log only - a failure here must never surface
      // as a user-facing error for a plan that already rendered fine.
    });
  }

  return plan;
});

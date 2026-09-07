import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../dashboard/presentation/dashboard_controller.dart';
import '../domain/models/engine_outputs.dart';
import 'statistics_repository.dart';

final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return StatisticsRepository(ref.watch(fantasyDataProviderProvider));
});

/// Scores the current starting XI shown on the dashboard. Depends on
/// [dashboardDataProvider] rather than re-fetching the squad itself, so
/// there is exactly one place that decides "what is the user's current
/// squad" (plan section 11 treats the Statistics Engine as a consumer of
/// facts, never a second source of truth for them).
final startingXiScoreProvider =
    FutureProvider<(List<PlayerScoreCard>, TeamScoreCard)?>((ref) async {
  final dashboard = await ref.watch(dashboardDataProvider.future);
  if (dashboard == null) return null;

  final startingIds = dashboard.squad
      .where((p) => p.isStarting)
      .map((p) => p.player.id)
      .toList();
  if (startingIds.isEmpty) return null;

  final repo = ref.watch(statisticsRepositoryProvider);
  final result = await repo.scoreStartingXi(startingIds);

  return result.when(ok: (v) => v, err: (failure) => throw failure);
});

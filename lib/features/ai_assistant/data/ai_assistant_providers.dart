import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_providers.dart';
import '../../dashboard/presentation/dashboard_controller.dart';
import '../../emergency_coach/data/emergency_coach_providers.dart';
import '../../statistics_engine/data/statistics_providers.dart';
import '../domain/ai_context_builder.dart';
import 'ai_assistant_repository.dart';

final aiAssistantRepositoryProvider = Provider<AiAssistantRepository>((ref) {
  return AiAssistantRepository(ref.watch(supabaseClientProvider));
});

const _contextBuilder = AiContextBuilder();

/// Rebuilds the full context packet from current provider state every
/// time it's read - never cached across a conversation - so the AI
/// layer is always grounded in the latest squad/scores, per plan section
/// 11's single-source-of-truth rule.
final aiContextProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final dashboard = await ref.watch(dashboardDataProvider.future);
  if (dashboard == null) return null;

  final scorePair = await ref.watch(startingXiScoreProvider.future);
  final plan = await ref.watch(emergencyCoachPlanProvider.future);

  return _contextBuilder.build(
    dashboard: dashboard,
    playerScores: scorePair?.$1 ?? const [],
    teamScoreCard: scorePair?.$2,
    coachPlan: plan,
  );
});

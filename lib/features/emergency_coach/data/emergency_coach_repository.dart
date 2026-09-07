import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/result.dart';
import '../../dashboard/domain/dashboard_data.dart';
import '../../statistics_engine/data/statistics_repository.dart';
import '../../statistics_engine/domain/models/engine_outputs.dart';
import '../domain/emergency_coach_engine.dart';
import '../domain/models/coach_models.dart';

/// Combines a loaded [DashboardData] (already fetched by
/// `DashboardRepository`) with full-squad Statistics Engine scores, then
/// runs the deterministic [EmergencyCoachEngine]. Deliberately does not
/// re-fetch the squad itself — plan section 11 treats "what is the
/// user's current squad" as a single source of truth owned by the
/// dashboard/data layer, not something each feature re-derives.
class EmergencyCoachRepository {
  final StatisticsRepository _statisticsRepository;
  final EmergencyCoachEngine _engine;
  final sb.SupabaseClient? _client;

  EmergencyCoachRepository(
    this._statisticsRepository, {
    EmergencyCoachEngine engine = const EmergencyCoachEngine(),
    sb.SupabaseClient? client,
  })  : _engine = engine,
        _client = client;

  Future<Result<EmergencyCoachPlan>> generatePlan(DashboardData data) async {
    final allIds = data.squad.map((p) => p.player.id).toList();

    final scoresResult = await _statisticsRepository.scorePlayerIds(allIds);
    final scores = scoresResult.valueOrNull;
    // Missing score data degrades to availability-only checks (handled
    // inside the engine's replacement-picking fallback) rather than
    // failing the whole coach output - a blank plan when there's an
    // injured starter to flag would be worse than a partial one.
    final scoreCards = <int, PlayerScoreCard>{
      for (final c in (scores ?? <PlayerScoreCard>[])) c.playerId: c,
    };

    final plan =
        _engine.generatePlan(squad: data.squad, scoreCards: scoreCards);
    return Result.ok(plan);
  }

  /// Persists the plan to `emergency_coach_events` for audit (plan
  /// section 13). Requires a `fantasy_teams.id` — silently skipped (with
  /// the failure surfaced to the caller, not swallowed) when the team
  /// row doesn't exist yet. `fantasy_teams` population is a pending item
  /// noted in the project README; wire this up once that lands.
  Future<Result<bool>> recordEvent({
    required EmergencyCoachPlan plan,
    required String fantasyTeamId,
    required int gameweekId,
  }) async {
    final client = _client;
    if (client == null) {
      return Result.err(const AppFailure(
        AppFailureType.unknown,
        'No Supabase client configured for audit logging',
      ));
    }

    try {
      await client.from('emergency_coach_events').insert({
        'team_id': fantasyTeamId,
        'gameweek_id': gameweekId,
        'detected_issues_json': plan.issues
            .map((i) => {
                  'type': i.type.name,
                  'player_id': i.playerId,
                  'player_name': i.playerName,
                  'severity': i.severity.name,
                  'description': i.description,
                })
            .toList(),
        'proposed_plan_json': plan.actions
            .map((a) => {
                  'type': a.type.name,
                  'description': a.description,
                  'affected_player_ids': a.affectedPlayerIds,
                })
            .toList(),
      });
      return Result.ok(true);
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }
}

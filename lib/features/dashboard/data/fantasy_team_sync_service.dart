import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/result.dart';
import '../domain/dashboard_data.dart';

/// Upserts the currently-loaded squad into `fantasy_teams`
/// (schema.sql) so other features — notably
/// `EmergencyCoachRepository.recordEvent()` — have a real
/// `fantasy_teams.id` to attach audit rows to (plan section 13).
///
/// This is a cache write, not a new source of truth: FPL's own data
/// (fetched fresh via [FantasyDataProvider] on every dashboard load)
/// remains authoritative. `fantasy_teams.current_squad_snapshot` exists
/// so the rest of the schema (transfers, recommendations,
/// emergency_coach_events) has a stable foreign key to point at, and as
/// a first step toward the offline cache called out in plan section 8 —
/// it is not read back to render the dashboard today.
class FantasyTeamSyncService {
  final sb.SupabaseClient _client;

  FantasyTeamSyncService(this._client);

  Future<Result<String>> syncTeam({
    required String appUserId,
    required DashboardData data,
  }) async {
    try {
      final snapshot = {
        'gameweek_id': data.currentGameweek.id,
        'picks': data.squad
            .map((p) => {
                  'player_id': p.player.id,
                  'is_starting': p.isStarting,
                  'is_captain': p.isCaptain,
                })
            .toList(),
      };

      final row = await _client
          .from('fantasy_teams')
          .upsert(
            {
              'user_id': appUserId,
              'budget_tenths': data.manager.bankTenths.round(),
              'current_squad_snapshot': snapshot,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'user_id',
          )
          .select('id')
          .single();

      return Result.ok(row['id'] as String);
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }
}

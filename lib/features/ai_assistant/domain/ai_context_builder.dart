import '../../dashboard/domain/dashboard_data.dart';
import '../../emergency_coach/domain/models/coach_models.dart';
import '../../statistics_engine/domain/models/engine_outputs.dart';

/// Builds the exact JSON packet sent to the AI layer.
///
/// This is the enforcement point for plan section 11's core rule: the AI
/// model never sees raw FPL data and is never asked to compute a rating,
/// a captain score, or a risk level itself. It only ever receives
/// numbers this app has already computed deterministically (Statistics
/// Engine, Emergency Coach) plus their stated reasons — its job is
/// narrowly to explain and answer questions *about* this packet, in
/// natural language, and to say "I don't have that" for anything not in
/// it (plan section 4).
///
/// Kept as a pure function (no I/O) so it's trivially testable and so a
/// prompt-injection attempt inside FPL data (a player's `news` text, for
/// instance) can't reach the model with anything except plain string
/// values inside a clearly-labeled JSON field — never as instructions.
class AiContextBuilder {
  const AiContextBuilder();

  Map<String, dynamic> build({
    required DashboardData dashboard,
    List<PlayerScoreCard> playerScores = const [],
    TeamScoreCard? teamScoreCard,
    EmergencyCoachPlan? coachPlan,
  }) {
    return {
      'gameweek': {
        'current': dashboard.currentGameweek.number,
        'deadline_in_hours':
            dashboard.deadlineGameweek.timeUntilDeadline().inHours,
      },
      'manager': {
        'team_name': dashboard.manager.teamName,
        'overall_points': dashboard.manager.overallPoints,
        'overall_rank': dashboard.manager.overallRank,
      },
      'squad': dashboard.squad
          .map((p) => {
                'player_id': p.player.id,
                'name': p.player.webName,
                'position': p.player.position.name,
                'is_starting': p.isStarting,
                'is_captain': p.isCaptain,
                'availability_status': p.player.status,
                'availability_note': p.player.news,
                'has_fixture_this_gw': p.nextFixture != null,
                if (_scoreFor(playerScores, p.player.id) != null)
                  'scores': _scoreFor(playerScores, p.player.id),
              })
          .toList(),
      if (teamScoreCard != null)
        'team_rating': {
          'value': teamScoreCard.rating,
          'stance': teamScoreCard.stance.name,
          'reasons': teamScoreCard.reasons,
        },
      if (coachPlan != null)
        'emergency_coach': {
          'issues': coachPlan.issues
              .map((i) => {
                    'type': i.type.name,
                    'player_name': i.playerName,
                    'severity': i.severity.name,
                    'description': i.description,
                  })
              .toList(),
          'suggested_actions': coachPlan.actions
              .map((a) => {
                    'type': a.type.name,
                    'description': a.description,
                  })
              .toList(),
        },
    };
  }

  Map<String, dynamic>? _scoreFor(List<PlayerScoreCard> scores, int playerId) {
    for (final s in scores) {
      if (s.playerId == playerId) {
        return {
          'rating': s.rating.value,
          'rating_reasons': s.rating.reasons,
          'rotation_risk': s.rotationRisk.value,
          'expected_points': s.expectedPoints,
          'captain_score': s.captainScore,
          'is_differential': s.isDifferential,
          'confidence': s.confidence,
        };
      }
    }
    return null;
  }
}

import '../../dashboard/domain/dashboard_data.dart';
import '../../statistics_engine/domain/models/engine_outputs.dart';
import 'models/coach_models.dart';

/// Deterministic Emergency Coach - plan section 3.
///
/// Same hard rule as StatisticsEngine: pure function of its inputs, no
/// AI calls, no network I/O. It reads Statistics Engine score cards and
/// raw squad facts and produces CoachIssues / CoachActions. The AI
/// Reasoning Layer (section 11) is only ever a renderer on top of this
/// output - it explains "why", it does not decide "whether".
class EmergencyCoachEngine {
  const EmergencyCoachEngine();

  /// [squad] must include the FULL 15, not just the starting XI - bench
  /// players are the candidate replacements. [scoreCards] should cover
  /// every player in [squad] (missing entries are treated as "no score
  /// available" and skipped for replacement ranking, never guessed at).
  EmergencyCoachPlan generatePlan({
    required List<DashboardSquadPlayer> squad,
    required Map<int, PlayerScoreCard> scoreCards,
    DateTime? now,
  }) {
    final issues = <CoachIssue>[];
    final actions = <CoachAction>[];

    final starters = squad.where((p) => p.isStarting).toList();
    final bench = squad.where((p) => !p.isStarting).toList();

    _detectAvailabilityIssues(starters, bench, issues, actions);
    _detectBlankFixtures(starters, bench, issues, actions);
    _detectCaptaincyIssues(starters, scoreCards, issues, actions);
    _detectBenchStrongerThanStarter(starters, bench, scoreCards, issues, actions);

    return EmergencyCoachPlan(
      issues: issues,
      actions: actions,
      generatedAt: now ?? DateTime.now().toUtc(),
    );
  }

  void _detectAvailabilityIssues(
    List<DashboardSquadPlayer> starters,
    List<DashboardSquadPlayer> bench,
    List<CoachIssue> issues,
    List<CoachAction> actions,
  ) {
    for (final starter in starters) {
      if (!starter.isAvailabilityRisk) continue;

      final CoachIssueType type;
      final CoachIssueSeverity severity;
      switch (starter.player.status) {
        case 'i':
          type = CoachIssueType.injured;
          severity = CoachIssueSeverity.critical;
          break;
        case 's':
          type = CoachIssueType.suspended;
          severity = CoachIssueSeverity.critical;
          break;
        case 'u':
          type = CoachIssueType.unavailable;
          severity = CoachIssueSeverity.critical;
          break;
        case 'd':
          type = CoachIssueType.doubtful;
          severity = CoachIssueSeverity.warning;
          break;
        default:
          type = CoachIssueType.doubtful;
          severity = CoachIssueSeverity.info;
      }

      issues.add(CoachIssue(
        type: type,
        playerId: starter.player.id,
        playerName: starter.player.webName,
        severity: severity,
        description: starter.player.news ??
            '${starter.player.webName} is flagged ${starter.player.status} by FPL',
      ));

      // Only critical flags (not "doubtful") get an automatic bench
      // suggestion - a doubtful player might still play, and the plan
      // shouldn't suggest benching someone on a 75% chance without the
      // user seeing the confidence context first (surfaced in the UI,
      // not decided away here).
      if (severity == CoachIssueSeverity.critical) {
        final replacement = _bestReplacement(starter, bench, const {});
        if (replacement != null) {
          actions.add(CoachAction(
            type: CoachActionType.promoteFromBench,
            description:
                'Move ${replacement.player.webName} into the starting XI for '
                '${starter.player.webName} (unavailable)',
            affectedPlayerIds: [starter.player.id, replacement.player.id],
          ));
        }
      }
    }
  }

  void _detectBlankFixtures(
    List<DashboardSquadPlayer> starters,
    List<DashboardSquadPlayer> bench,
    List<CoachIssue> issues,
    List<CoachAction> actions,
  ) {
    for (final starter in starters) {
      if (starter.nextFixture != null) continue;
      if (starter.isAvailabilityRisk) continue; // already covered above

      issues.add(CoachIssue(
        type: CoachIssueType.blankFixture,
        playerId: starter.player.id,
        playerName: starter.player.webName,
        severity: CoachIssueSeverity.warning,
        description: '${starter.player.webName} has no fixture this gameweek',
      ));

      final replacement = _bestReplacement(
        starter,
        bench,
        const {},
        requireFixture: true,
      );
      if (replacement != null) {
        actions.add(CoachAction(
          type: CoachActionType.promoteFromBench,
          description:
              'Consider ${replacement.player.webName} instead of '
              '${starter.player.webName}, who has a blank gameweek',
          affectedPlayerIds: [starter.player.id, replacement.player.id],
        ));
      }
    }
  }

  void _detectCaptaincyIssues(
    List<DashboardSquadPlayer> starters,
    Map<int, PlayerScoreCard> scoreCards,
    List<CoachIssue> issues,
    List<CoachAction> actions,
  ) {
    final captainEntries = starters.where((p) => p.isCaptain).toList();
    if (captainEntries.isEmpty) return;
    final captain = captainEntries.first;
    final captainCard = scoreCards[captain.player.id];
    if (captainCard == null) return;

    if (captain.isAvailabilityRisk) {
      issues.add(CoachIssue(
        type: CoachIssueType.suboptimalCaptain,
        playerId: captain.player.id,
        playerName: captain.player.webName,
        severity: CoachIssueSeverity.critical,
        description:
            'Your captain, ${captain.player.webName}, is flagged '
            '${captain.player.status} - a blank captaincy would cost the '
            'whole doubled score',
      ));
    }

    // Find a clearly-better captaincy option among other starters: more
    // than 20% higher captain score, and themselves fully available.
    DashboardSquadPlayer? better;
    double bestScore = captainCard.captainScore;
    for (final candidate in starters) {
      if (candidate.player.id == captain.player.id) continue;
      if (candidate.isAvailabilityRisk) continue;
      final card = scoreCards[candidate.player.id];
      if (card == null) continue;
      if (card.captainScore > bestScore * 1.2) {
        bestScore = card.captainScore;
        better = candidate;
      }
    }

    if (better != null) {
      issues.add(CoachIssue(
        type: CoachIssueType.suboptimalCaptain,
        playerId: captain.player.id,
        playerName: captain.player.webName,
        severity: CoachIssueSeverity.info,
        description:
            '${better.player.webName} projects a notably higher captain '
            'score than ${captain.player.webName} this gameweek',
      ));
      actions.add(CoachAction(
        type: CoachActionType.swapCaptain,
        description:
            'Consider captaining ${better.player.webName} instead of '
            '${captain.player.webName}',
        affectedPlayerIds: [captain.player.id, better.player.id],
      ));
    }
  }

  void _detectBenchStrongerThanStarter(
    List<DashboardSquadPlayer> starters,
    List<DashboardSquadPlayer> bench,
    Map<int, PlayerScoreCard> scoreCards,
    List<CoachIssue> issues,
    List<CoachAction> actions,
  ) {
    for (final starter in starters) {
      if (starter.isAvailabilityRisk) continue; // already covered
      final starterCard = scoreCards[starter.player.id];
      if (starterCard == null) continue;

      final replacement = _bestReplacement(
        starter,
        bench,
        scoreCards,
        minimumRatingMargin: 15,
      );
      if (replacement == null) continue;

      issues.add(CoachIssue(
        type: CoachIssueType.benchOutperformsStarter,
        playerId: starter.player.id,
        playerName: starter.player.webName,
        severity: CoachIssueSeverity.info,
        description:
            '${replacement.player.webName} on your bench rates notably '
            'higher than starting ${starter.player.webName} this gameweek',
      ));
      actions.add(CoachAction(
        type: CoachActionType.promoteFromBench,
        description:
            'Consider starting ${replacement.player.webName} over '
            '${starter.player.webName}',
        affectedPlayerIds: [starter.player.id, replacement.player.id],
      ));
    }
  }

  /// Picks the best same-position bench replacement for [starter],
  /// preferring (in order): actually available, has a fixture (when
  /// [requireFixture]), and highest Player Rating. Returns null when no
  /// bench player qualifies - the caller should not fabricate a
  /// suggestion when there's genuinely no good option (plan section 4's
  /// "say when there isn't enough data" applies to the coach's own
  /// output too).
  DashboardSquadPlayer? _bestReplacement(
    DashboardSquadPlayer starter,
    List<DashboardSquadPlayer> bench,
    Map<int, PlayerScoreCard> scoreCards, {
    bool requireFixture = false,
    double minimumRatingMargin = 0,
  }) {
    final candidates = bench.where((b) {
      if (b.player.position != starter.player.position) return false;
      if (b.isAvailabilityRisk) return false;
      if (requireFixture && b.nextFixture == null) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) return null;

    if (scoreCards.isEmpty) {
      // No score data available (e.g. an availability-driven emergency
      // swap where scores weren't computed yet) - fall back to FPL's
      // own `form` as the only deterministic tiebreaker available.
      candidates.sort((a, b) => b.player.form.compareTo(a.player.form));
      return candidates.first;
    }

    DashboardSquadPlayer? best;
    double bestRating = -1;
    for (final candidate in candidates) {
      final card = scoreCards[candidate.player.id];
      if (card == null) continue;
      if (card.rating.value > bestRating) {
        bestRating = card.rating.value;
        best = candidate;
      }
    }

    if (best == null) return null;

    final starterCard = scoreCards[starter.player.id];
    if (starterCard != null &&
        bestRating < starterCard.rating.value + minimumRatingMargin) {
      return null;
    }

    return best;
  }
}

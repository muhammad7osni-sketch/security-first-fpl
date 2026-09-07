import 'package:flutter_test/flutter_test.dart';
import 'package:squadiq/data_providers/models/club.dart';
import 'package:squadiq/data_providers/models/fixture.dart';
import 'package:squadiq/data_providers/models/player.dart';
import 'package:squadiq/features/dashboard/domain/dashboard_data.dart';
import 'package:squadiq/features/emergency_coach/domain/emergency_coach_engine.dart';
import 'package:squadiq/features/emergency_coach/domain/models/coach_models.dart';
import 'package:squadiq/features/statistics_engine/domain/models/engine_outputs.dart';

const _club = Club(id: 1, name: 'Test FC', shortName: 'TFC');

Player _player({
  required int id,
  required String name,
  PlayerPosition position = PlayerPosition.midfielder,
  String status = 'a',
  double form = 5,
}) {
  return Player(
    id: id,
    webName: name,
    firstName: name,
    secondName: '',
    clubId: _club.id,
    position: position,
    nowCostTenths: 70,
    selectedByPercent: 15,
    form: form,
    minutesLastGw: 90,
    totalPoints: 40,
    status: status,
  );
}

DashboardSquadPlayer _squadPlayer({
  required int id,
  required String name,
  bool isStarting = true,
  bool isCaptain = false,
  PlayerPosition position = PlayerPosition.midfielder,
  String status = 'a',
  double form = 5,
  Fixture? nextFixture,
}) {
  return DashboardSquadPlayer(
    player: _player(
        id: id, name: name, position: position, status: status, form: form),
    club: _club,
    isStarting: isStarting,
    isCaptain: isCaptain,
    isViceCaptain: false,
    nextFixture: nextFixture,
  );
}

PlayerScoreCard _card(int id, {double rating = 50, double captainScore = 5}) {
  return PlayerScoreCard(
    playerId: id,
    rating: ScoredMetric(rating, const ['test']),
    rotationRisk: const ScoredMetric(10, ['test']),
    expectedPoints: 4,
    captainScore: captainScore,
    isDifferential: false,
    confidence: 70,
  );
}

final _fixture = Fixture(
  id: 1,
  gameweekId: 1,
  homeClubId: _club.id,
  awayClubId: 99,
  homeDifficulty: 3,
  awayDifficulty: 3,
  kickoffTime: null,
  finished: false,
);

void main() {
  const engine = EmergencyCoachEngine();

  test('a clean squad with no issues produces an all-clear plan', () {
    final squad = [
      _squadPlayer(
          id: 1, name: 'Starter A', nextFixture: _fixture, isCaptain: true),
      _squadPlayer(id: 2, name: 'Starter B', nextFixture: _fixture),
      _squadPlayer(
          id: 3, name: 'Bench A', isStarting: false, nextFixture: _fixture),
    ];
    final scores = {
      1: _card(1, rating: 60, captainScore: 8),
      2: _card(2, rating: 55, captainScore: 6),
      3: _card(3, rating: 40, captainScore: 4),
    };

    final plan = engine.generatePlan(squad: squad, scoreCards: scores);

    expect(plan.isAllClear, isTrue);
  });

  test(
      'an injured starter with an available same-position bench player '
      'produces a critical issue and a promote action', () {
    final squad = [
      _squadPlayer(
          id: 1,
          name: 'Injured Striker',
          position: PlayerPosition.forward,
          status: 'i'),
      _squadPlayer(
          id: 2,
          name: 'Bench Striker',
          position: PlayerPosition.forward,
          isStarting: false),
    ];

    final plan = engine.generatePlan(squad: squad, scoreCards: const {});

    expect(plan.hasCriticalIssues, isTrue);
    expect(plan.issues.single.type, CoachIssueType.injured);
    expect(plan.actions, isNotEmpty);
    expect(plan.actions.single.type, CoachActionType.promoteFromBench);
    expect(plan.actions.single.affectedPlayerIds, containsAll([1, 2]));
  });

  test(
      'a doubtful starter is flagged as a warning, not critical, and '
      'does not get an automatic bench suggestion', () {
    final squad = [
      _squadPlayer(id: 1, name: 'Doubtful Player', status: 'd'),
      _squadPlayer(id: 2, name: 'Bench Player', isStarting: false),
    ];

    final plan = engine.generatePlan(squad: squad, scoreCards: const {});

    expect(plan.issues.single.severity, CoachIssueSeverity.warning);
    expect(plan.actions, isEmpty);
  });

  test('a suspended/injured captain is flagged critical', () {
    final squad = [
      _squadPlayer(id: 1, name: 'Captain', status: 's', isCaptain: true),
      _squadPlayer(id: 2, name: 'Other Starter'),
    ];
    final scores = {1: _card(1, captainScore: 8), 2: _card(2, captainScore: 6)};

    final plan = engine.generatePlan(squad: squad, scoreCards: scores);

    expect(
      plan.issues.any((i) =>
          i.type == CoachIssueType.suboptimalCaptain &&
          i.severity == CoachIssueSeverity.critical),
      isTrue,
    );
  });

  test('a much higher captain score elsewhere suggests a captaincy swap', () {
    final squad = [
      _squadPlayer(id: 1, name: 'Weak Captain', isCaptain: true),
      _squadPlayer(id: 2, name: 'Strong Alternative'),
    ];
    final scores = {
      1: _card(1, captainScore: 4),
      2: _card(2, captainScore: 10), // > 20% higher than 4
    };

    final plan = engine.generatePlan(squad: squad, scoreCards: scores);

    expect(
      plan.actions.any((a) => a.type == CoachActionType.swapCaptain),
      isTrue,
    );
  });

  test('a similar captain score elsewhere does not suggest a swap', () {
    final squad = [
      _squadPlayer(id: 1, name: 'Captain', isCaptain: true),
      _squadPlayer(id: 2, name: 'Similar Alternative'),
    ];
    final scores = {
      1: _card(1, captainScore: 8),
      2: _card(2, captainScore: 8.5), // well within 20%
    };

    final plan = engine.generatePlan(squad: squad, scoreCards: scores);

    expect(
      plan.actions.any((a) => a.type == CoachActionType.swapCaptain),
      isFalse,
    );
  });

  test(
      'a starter with a blank fixture and a bench alternative with a '
      'fixture is flagged', () {
    final squad = [
      _squadPlayer(id: 1, name: 'Blank GW Player', nextFixture: null),
      _squadPlayer(
          id: 2,
          name: 'Bench With Fixture',
          isStarting: false,
          nextFixture: _fixture),
    ];

    final plan = engine.generatePlan(squad: squad, scoreCards: const {});

    expect(
      plan.issues.any((i) => i.type == CoachIssueType.blankFixture),
      isTrue,
    );
    expect(
      plan.actions.any((a) => a.type == CoachActionType.promoteFromBench),
      isTrue,
    );
  });

  test(
      'a bench player rating far above a starter in the same position is '
      'flagged, but a marginal difference is not', () {
    final squadBig = [
      _squadPlayer(id: 1, name: 'Weak Starter', nextFixture: _fixture),
      _squadPlayer(
          id: 2,
          name: 'Strong Bench',
          isStarting: false,
          nextFixture: _fixture),
    ];
    final bigGapScores = {
      1: _card(1, rating: 30),
      2: _card(2, rating: 60), // 30-point gap, well above the 15 margin
    };

    final planBigGap =
        engine.generatePlan(squad: squadBig, scoreCards: bigGapScores);
    expect(
      planBigGap.issues
          .any((i) => i.type == CoachIssueType.benchOutperformsStarter),
      isTrue,
    );

    final smallGapScores = {
      1: _card(1, rating: 50),
      2: _card(2, rating: 55), // only 5-point gap
    };
    final planSmallGap =
        engine.generatePlan(squad: squadBig, scoreCards: smallGapScores);
    expect(
      planSmallGap.issues
          .any((i) => i.type == CoachIssueType.benchOutperformsStarter),
      isFalse,
    );
  });

  test(
      'no bench player in the same position never produces a fabricated '
      'suggestion', () {
    final squad = [
      _squadPlayer(
          id: 1,
          name: 'Injured Keeper',
          position: PlayerPosition.goalkeeper,
          status: 'i'),
      _squadPlayer(
          id: 2,
          name: 'Bench Midfielder',
          position: PlayerPosition.midfielder,
          isStarting: false),
    ];

    final plan = engine.generatePlan(squad: squad, scoreCards: const {});

    expect(plan.issues, isNotEmpty); // the injury itself is still flagged
    expect(plan.actions, isEmpty); // but no replacement is fabricated
  });
}

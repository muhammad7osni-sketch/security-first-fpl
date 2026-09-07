import 'package:flutter_test/flutter_test.dart';
import 'package:squadiq/data_providers/models/club.dart';
import 'package:squadiq/data_providers/models/gameweek.dart';
import 'package:squadiq/data_providers/models/manager_entry.dart';
import 'package:squadiq/data_providers/models/player.dart';
import 'package:squadiq/features/ai_assistant/domain/ai_context_builder.dart';
import 'package:squadiq/features/dashboard/domain/dashboard_data.dart';
import 'package:squadiq/features/emergency_coach/domain/models/coach_models.dart';
import 'package:squadiq/features/statistics_engine/domain/models/engine_outputs.dart';

const _club = Club(id: 1, name: 'Test FC', shortName: 'TFC');

Player _player(int id, String name, {String status = 'a', String? news}) {
  return Player(
    id: id,
    webName: name,
    firstName: name,
    secondName: '',
    clubId: 1,
    position: PlayerPosition.midfielder,
    nowCostTenths: 70,
    selectedByPercent: 10,
    form: 5,
    minutesLastGw: 90,
    totalPoints: 30,
    status: status,
    news: news,
  );
}

DashboardData _dashboard() {
  final gw = Gameweek(
    id: 5,
    number: 5,
    deadlineTime: DateTime.now().toUtc().add(const Duration(hours: 10)),
    isCurrent: true,
    isNext: false,
    finished: false,
  );
  const manager = ManagerEntry(
    id: 1,
    managerName: 'Test Manager',
    teamName: 'Test Team',
    overallPoints: 100,
    overallRank: 500,
    bankTenths: 5,
    teamValueTenths: 1000,
  );
  final squad = [
    DashboardSquadPlayer(
      player: _player(1, 'Starter One'),
      club: _club,
      isStarting: true,
      isCaptain: true,
      isViceCaptain: false,
      nextFixture: null,
    ),
  ];
  return DashboardData(
    currentGameweek: gw,
    nextGameweek: null,
    manager: manager,
    squad: squad,
  );
}

void main() {
  const builder = AiContextBuilder();

  test('context includes gameweek, manager, and squad facts', () {
    final context = builder.build(dashboard: _dashboard());

    expect(context['gameweek'], isNotNull);
    expect(context['manager']['team_name'], 'Test Team');
    expect((context['squad'] as List).length, 1);
    expect((context['squad'] as List).first['name'], 'Starter One');
  });

  test(
      'player score data is only attached when a matching score card '
      'exists - never fabricated for missing players', () {
    final context =
        builder.build(dashboard: _dashboard(), playerScores: const []);

    final squadJson = (context['squad'] as List).first as Map;
    expect(squadJson.containsKey('scores'), isFalse);
  });

  test('a matching score card attaches its exact values, unmodified', () {
    const card = PlayerScoreCard(
      playerId: 1,
      rating: ScoredMetric(72.5, ['good form']),
      rotationRisk: ScoredMetric(10, ['steady minutes']),
      expectedPoints: 5.4,
      captainScore: 10.8,
      isDifferential: false,
      confidence: 80,
    );

    final context = builder.build(
      dashboard: _dashboard(),
      playerScores: [card],
    );

    final squadJson = (context['squad'] as List).first as Map;
    expect(squadJson['scores']['rating'], 72.5);
    expect(squadJson['scores']['confidence'], 80);
  });

  test('emergency coach issues are passed through verbatim when present', () {
    final plan = EmergencyCoachPlan(
      issues: const [
        CoachIssue(
          type: CoachIssueType.injured,
          playerId: 1,
          playerName: 'Starter One',
          severity: CoachIssueSeverity.critical,
          description: 'Out for 4 weeks',
        ),
      ],
      actions: const [],
      generatedAt: DateTime.now(),
    );

    final context = builder.build(dashboard: _dashboard(), coachPlan: plan);

    expect(context['emergency_coach'], isNotNull);
    expect((context['emergency_coach']['issues'] as List).single['severity'],
        'critical');
  });

  test('no emergency coach section is included when no plan is given', () {
    final context = builder.build(dashboard: _dashboard());
    expect(context.containsKey('emergency_coach'), isFalse);
  });
}

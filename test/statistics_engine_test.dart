import 'package:flutter_test/flutter_test.dart';
import 'package:squadiq/data_providers/models/player.dart';
import 'package:squadiq/features/statistics_engine/domain/models/engine_inputs.dart';
import 'package:squadiq/features/statistics_engine/domain/statistics_engine.dart';

Player _player({
  int id = 1,
  PlayerPosition position = PlayerPosition.midfielder,
  String status = 'a',
  double selectedByPercent = 20,
  double form = 5,
  int minutesLastGw = 90,
}) {
  return Player(
    id: id,
    webName: 'Test Player $id',
    firstName: 'Test',
    secondName: 'Player',
    clubId: 1,
    position: position,
    nowCostTenths: 80,
    selectedByPercent: selectedByPercent,
    form: form,
    minutesLastGw: minutesLastGw,
    totalPoints: 50,
    status: status,
  );
}

void main() {
  const engine = StatisticsEngine();

  group('calculatePlayerRating', () {
    test('a nailed, in-form player with easy fixtures rates higher than '
        'a rotation-risk player in poor form', () {
      final strong = PlayerEngineInput(
        player: _player(id: 1, form: 8, selectedByPercent: 35),
        form: 8,
        recentMinutes: [90, 90, 88, 90, 90],
        upcomingFixtureDifficulty: [2, 2, 3],
        xgi90: 0.6,
        positionalCompetitorCount: 0,
      );

      final weak = PlayerEngineInput(
        player: _player(id: 2, form: 1.5, selectedByPercent: 3),
        form: 1.5,
        recentMinutes: [90, 0, 20, 0, 45],
        upcomingFixtureDifficulty: [5, 4, 5],
        xgi90: 0.05,
        positionalCompetitorCount: 2,
      );

      final strongRating = engine.calculatePlayerRating(strong);
      final weakRating = engine.calculatePlayerRating(weak);

      expect(strongRating.value, greaterThan(weakRating.value));
    });

    test('rating stays within 0-100 bounds even for extreme inputs', () {
      final extreme = PlayerEngineInput(
        player: _player(form: 20, selectedByPercent: 100),
        form: 20,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [1, 1, 1],
        xgi90: 5.0,
        positionalCompetitorCount: 0,
      );

      final rating = engine.calculatePlayerRating(extreme);
      expect(rating.value, inInclusiveRange(0, 100));
    });

    test('reasons list explains the rating (plan section 4 requirement)', () {
      final input = PlayerEngineInput(
        player: _player(),
        form: 5,
        recentMinutes: [90, 85, 90],
        upcomingFixtureDifficulty: [2, 3],
        xgi90: 0.3,
        positionalCompetitorCount: 0,
      );

      final rating = engine.calculatePlayerRating(input);
      expect(rating.reasons, isNotEmpty);
      expect(rating.reasons.any((r) => r.contains('Form')), isTrue);
    });
  });

  group('calculateRotationRisk', () {
    test('an injured/suspended flag dominates the risk score', () {
      final injured = PlayerEngineInput(
        player: _player(status: 'i'),
        form: 8, // even great form shouldn't mask an injury flag
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [2],
        positionalCompetitorCount: 0,
      );

      final risk = engine.calculateRotationRisk(injured);
      expect(risk.value, greaterThanOrEqualTo(90));
    });

    test('steady 90-minute players score low rotation risk', () {
      final steady = PlayerEngineInput(
        player: _player(),
        form: 5,
        recentMinutes: [90, 90, 90, 90],
        upcomingFixtureDifficulty: [3],
        positionalCompetitorCount: 0,
      );

      final risk = engine.calculateRotationRisk(steady);
      expect(risk.value, lessThan(30));
    });

    test('volatile minutes (in and out of the XI) raise risk', () {
      final volatile = PlayerEngineInput(
        player: _player(),
        form: 5,
        recentMinutes: [90, 0, 90, 0],
        upcomingFixtureDifficulty: [3],
        positionalCompetitorCount: 0,
      );
      final steady = PlayerEngineInput(
        player: _player(id: 2),
        form: 5,
        recentMinutes: [90, 90, 90, 90],
        upcomingFixtureDifficulty: [3],
        positionalCompetitorCount: 0,
      );

      final volatileRisk = engine.calculateRotationRisk(volatile);
      final steadyRisk = engine.calculateRotationRisk(steady);

      expect(volatileRisk.value, greaterThan(steadyRisk.value));
    });
  });

  group('calculateExpectedPoints', () {
    test('a forward with strong xGI outscores a defender with none, all '
        'else equal', () {
      final forward = PlayerEngineInput(
        player: _player(position: PlayerPosition.forward),
        form: 6,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [3],
        xgi90: 0.7,
        positionalCompetitorCount: 0,
      );
      final defender = PlayerEngineInput(
        player: _player(position: PlayerPosition.defender),
        form: 6,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [3],
        xgi90: 0.0,
        positionalCompetitorCount: 0,
      );

      final forwardXp = engine.calculateExpectedPoints(forward);
      final defenderXp = engine.calculateExpectedPoints(defender);

      expect(forwardXp, greaterThan(defenderXp));
    });

    test('a player with zero recent minutes has near-zero expected points',
        () {
      final benched = PlayerEngineInput(
        player: _player(),
        form: 8,
        recentMinutes: [0, 0, 0],
        upcomingFixtureDifficulty: [1],
        xgi90: 0.8,
        positionalCompetitorCount: 0,
      );

      expect(engine.calculateExpectedPoints(benched), lessThan(0.5));
    });

    test('easier upcoming fixtures raise expected points for the same '
        'player profile', () {
      final base = PlayerEngineInput(
        player: _player(),
        form: 6,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [5, 5],
        xgi90: 0.4,
        positionalCompetitorCount: 0,
      );
      final easier = PlayerEngineInput(
        player: _player(id: 2),
        form: 6,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [1, 1],
        xgi90: 0.4,
        positionalCompetitorCount: 0,
      );

      expect(
        engine.calculateExpectedPoints(easier),
        greaterThan(engine.calculateExpectedPoints(base)),
      );
    });
  });

  group('calculateCaptainScore', () {
    test('captain score roughly doubles expected points for a nailed '
        'starter with a neutral fixture', () {
      final input = PlayerEngineInput(
        player: _player(),
        form: 6,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [3],
        xgi90: 0.4,
        positionalCompetitorCount: 0,
      );

      final xp = engine.calculateExpectedPoints(input);
      final captainScore = engine.calculateCaptainScore(input);

      expect(captainScore, closeTo(xp * 2, xp * 0.05));
    });

    test('an easier fixture produces a higher captain score than a harder '
        'one, all else equal', () {
      final easy = PlayerEngineInput(
        player: _player(),
        form: 6,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [1],
        xgi90: 0.4,
        positionalCompetitorCount: 0,
      );
      final hard = PlayerEngineInput(
        player: _player(id: 2),
        form: 6,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [5],
        xgi90: 0.4,
        positionalCompetitorCount: 0,
      );

      expect(
        engine.calculateCaptainScore(easy),
        greaterThan(engine.calculateCaptainScore(hard)),
      );
    });
  });

  group('calculateTransferScore', () {
    test('a points hit reduces the transfer score by exactly 4', () {
      final out = PlayerEngineInput(
        player: _player(id: 1),
        form: 3,
        recentMinutes: [60, 60],
        upcomingFixtureDifficulty: [3, 3],
        xgi90: 0.2,
        positionalCompetitorCount: 0,
      );
      final incoming = PlayerEngineInput(
        player: _player(id: 2),
        form: 3,
        recentMinutes: [60, 60],
        upcomingFixtureDifficulty: [3, 3],
        xgi90: 0.2,
        positionalCompetitorCount: 0,
      );

      final free = engine.calculateTransferScore(
        playerOut: out,
        playerIn: incoming,
        gameweekHorizon: 2,
        isPointsHit: false,
      );
      final hit = engine.calculateTransferScore(
        playerOut: out,
        playerIn: incoming,
        gameweekHorizon: 2,
        isPointsHit: true,
      );

      expect(free - hit, closeTo(4.0, 0.001));
    });

    test('bringing in a clearly better player over the out-player scores '
        'positive', () {
      final out = PlayerEngineInput(
        player: _player(id: 1, form: 1),
        form: 1,
        recentMinutes: [10, 0, 20],
        upcomingFixtureDifficulty: [4, 4],
        xgi90: 0.05,
        positionalCompetitorCount: 2,
      );
      final incoming = PlayerEngineInput(
        player: _player(id: 2, form: 8),
        form: 8,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [2, 2],
        xgi90: 0.7,
        positionalCompetitorCount: 0,
      );

      final score = engine.calculateTransferScore(
        playerOut: out,
        playerIn: incoming,
        gameweekHorizon: 3,
        isPointsHit: false,
      );

      expect(score, greaterThan(0));
    });
  });

  group('isDifferential', () {
    test('low ownership + high rating flags as differential', () {
      final input = PlayerEngineInput(
        player: _player(selectedByPercent: 4),
        form: 7,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [2, 2],
        xgi90: 0.6,
        positionalCompetitorCount: 0,
      );
      final rating = engine.calculatePlayerRating(input);

      expect(engine.isDifferential(input, rating), isTrue);
    });

    test('high ownership does not flag as differential even with a great '
        'rating', () {
      final input = PlayerEngineInput(
        player: _player(selectedByPercent: 55),
        form: 7,
        recentMinutes: [90, 90, 90],
        upcomingFixtureDifficulty: [2, 2],
        xgi90: 0.6,
        positionalCompetitorCount: 0,
      );
      final rating = engine.calculatePlayerRating(input);

      expect(engine.isDifferential(input, rating), isFalse);
    });
  });

  group('buildTeamScoreCard', () {
    test('empty starting XI returns a safe default rather than throwing',
        () {
      final team = engine.buildTeamScoreCard([]);
      expect(team.rating, 0);
      expect(team.reasons, isNotEmpty);
    });
  });
}

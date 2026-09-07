import 'dart:math';

import '../../../data_providers/models/player.dart';
import 'models/engine_inputs.dart';
import 'models/engine_outputs.dart';

/// Deterministic, pure Statistics Engine — plan sections 10 and 11.
///
/// Hard rule enforced by construction, not just convention: every method
/// here is a pure function of its inputs. No network calls, no random
/// numbers, no clock reads beyond what's passed in. This is what lets
/// the AI Reasoning Layer (section 11) treat these numbers as ground
/// truth it explains but never overrides — and it's what makes this
/// class trivially unit-testable (section 8: "Unit tests للـ Statistics
/// Engine أولوية قصوى").
///
/// Weights and formulas below are the deliberately-simple v1 from
/// section 10 ("Weighted Scoring Models بسيطة في البداية"). They are
/// meant to be replaced by trained models later (section 10's own note)
/// — treat every magic number here as a tunable constant, not a fact.
class StatisticsEngine {
  const StatisticsEngine();

  // ---- Tunable weights (plan section 10) ----------------------------
  static const _wForm = 0.25;
  static const _wFixtureEase = 0.20;
  static const _wXgi = 0.20;
  static const _wMinutes = 0.20;
  static const _wOwnership = 0.05;
  static const _wRotationRiskPenalty = 0.10;

  /// Reference caps used to normalize raw stats onto a 0–100 scale.
  /// These are approximations of "very good" values in the Premier
  /// League context, not hard limits — a player can still exceed them,
  /// the sub-score just saturates at 100.
  static const _formCap = 8.0; // FPL form points/match
  static const _xgi90Cap = 0.9; // combined xG+xA per 90

  // ---------------------------------------------------------------
  // Player Rating (0-100)
  // ---------------------------------------------------------------
  ScoredMetric calculatePlayerRating(PlayerEngineInput input) {
    final reasons = <String>[];

    final formScore = _normalize(input.form, _formCap);
    reasons.add('Form ${input.form.toStringAsFixed(1)}/match');

    final fixtureEaseScore = _fixtureEaseScore(input.upcomingFixtureDifficulty);
    if (input.upcomingFixtureDifficulty.isNotEmpty) {
      final avg =
          _average(input.upcomingFixtureDifficulty.map((d) => d.toDouble()));
      reasons.add('Avg fixture difficulty ${avg.toStringAsFixed(1)}/5 next '
          '${input.upcomingFixtureDifficulty.length} GWs');
    } else {
      reasons.add('No upcoming fixture in window');
    }

    final xgiValue = input.xgi90 ?? _xgiProxyFromForm(input);
    final xgiScore = _normalize(xgiValue, _xgi90Cap);
    reasons.add(input.xgi90 != null
        ? 'xGI ${xgiValue.toStringAsFixed(2)}/90'
        : 'xGI unavailable, using form-based proxy');

    final minutesScore = _minutesExpectationScore(input.recentMinutes);
    reasons.add(
        'Avg ${_average(input.recentMinutes.map((m) => m.toDouble())).toStringAsFixed(0)} '
        'mins/game recently');

    final ownershipScore = min(input.player.selectedByPercent, 100.0);

    final rotationRisk = calculateRotationRisk(input);
    reasons.add('Rotation risk ${rotationRisk.value.toStringAsFixed(0)}/100');

    final rating = (formScore * _wForm) +
        (fixtureEaseScore * _wFixtureEase) +
        (xgiScore * _wXgi) +
        (minutesScore * _wMinutes) +
        (ownershipScore * _wOwnership) -
        (rotationRisk.value * _wRotationRiskPenalty);

    return ScoredMetric(rating.clamp(0, 100), reasons);
  }

  // ---------------------------------------------------------------
  // Rotation Risk (0-100, higher = riskier)
  // ---------------------------------------------------------------
  ScoredMetric calculateRotationRisk(PlayerEngineInput input) {
    final reasons = <String>[];

    // Minutes volatility: stdev of recent minutes relative to a full
    // 90 — a player alternating between 90 and 0 is riskier than one
    // steadily on 60-70.
    final minutes = input.recentMinutes.map((m) => m.toDouble()).toList();
    final volatility = minutes.length < 2 ? 0.0 : _stdev(minutes) / 90.0 * 100;
    reasons.add(
        'Minutes volatility ${volatility.clamp(0, 100).toStringAsFixed(0)}/100');

    // Availability flag dominates when present — a doubtful/injured tag
    // from FPL itself is a stronger signal than minutes history alone.
    final statusRisk = switch (input.player.status) {
      'i' => 90.0,
      's' => 90.0,
      'd' => 60.0,
      'u' => 100.0,
      _ => 0.0,
    };
    if (statusRisk > 0) {
      reasons.add('FPL status flag: ${input.player.status}');
    }

    final competitionRisk = min(input.positionalCompetitorCount * 15.0, 60.0);
    if (input.positionalCompetitorCount > 0) {
      reasons
          .add('${input.positionalCompetitorCount} competitor(s) for the spot');
    }

    final risk = [volatility, statusRisk, competitionRisk].reduce(max);
    return ScoredMetric(risk.clamp(0, 100), reasons);
  }

  // ---------------------------------------------------------------
  // Expected Points (raw FPL points, per-position model)
  // ---------------------------------------------------------------
  double calculateExpectedPoints(PlayerEngineInput input,
      {int fixtureIndex = 0}) {
    final minutesProb = _minutesExpectationScore(input.recentMinutes) / 100.0;

    final difficulty = fixtureIndex < input.upcomingFixtureDifficulty.length
        ? input.upcomingFixtureDifficulty[fixtureIndex]
        : 3; // neutral assumption for blank/unknown fixtures

    // Clean sheet probability is a crude inverse of fixture difficulty —
    // a real model would use club-level attack/defense strength
    // (available once API-Football's lineup/strength data is wired up,
    // plan section 6). This is the v1 placeholder the plan expects to
    // evolve (section 10's closing note).
    final cleanSheetProb = (1 - (difficulty - 1) / 4).clamp(0.05, 0.75);

    final xgi = input.xgi90 ?? _xgiProxyFromForm(input);

    const appearancePoints = 2.0;

    final (goalPoints, cleanSheetBonus) = switch (input.player.position) {
      PlayerPosition.goalkeeper => (6.0, 4.0),
      PlayerPosition.defender => (6.0, 4.0),
      PlayerPosition.midfielder => (5.0, 1.0),
      PlayerPosition.forward => (4.0, 0.0),
      PlayerPosition.unknown => (4.0, 0.0),
    };

    // Rough split: assume ~65% of combined xGI value converts to "goal
    // equivalent" scoring points, remainder scored at assist rate — a
    // simplification acknowledged in the class doc comment above.
    final attackingPoints = xgi * ((goalPoints * 0.65) + (3.0 * 0.35));

    final expected = minutesProb *
        (appearancePoints +
            attackingPoints +
            (cleanSheetBonus * cleanSheetProb));

    return double.parse(expected.toStringAsFixed(2));
  }

  // ---------------------------------------------------------------
  // Captain Score
  // ---------------------------------------------------------------
  double calculateCaptainScore(PlayerEngineInput input) {
    final baseExpected = calculateExpectedPoints(input);
    final minutesProb = _minutesExpectationScore(input.recentMinutes) / 100.0;

    final difficulty = input.upcomingFixtureDifficulty.isNotEmpty
        ? input.upcomingFixtureDifficulty.first
        : 3;
    // Easier fixture -> multiplier above 1; harder -> below 1. Centered
    // on difficulty 3 (neutral).
    final fixtureFactor = 1 + ((3 - difficulty) * 0.1);

    return double.parse(
      (baseExpected * 2 * fixtureFactor * minutesProb).toStringAsFixed(2),
    );
  }

  // ---------------------------------------------------------------
  // Transfer Score
  // ---------------------------------------------------------------
  /// Positive = worth making the transfer over [gameweekHorizon] GWs;
  /// negative = not worth it. `priceSwingTenths` is the expected price
  /// change of the incoming player over the horizon (tenths of a
  /// million, FPL's own unit) — a modest reward for players likely to
  /// rise in value, per section 10.
  double calculateTransferScore({
    required PlayerEngineInput playerOut,
    required PlayerEngineInput playerIn,
    required int gameweekHorizon,
    required bool isPointsHit,
    int priceSwingTenths = 0,
  }) {
    double outTotal = 0;
    double inTotal = 0;
    for (var i = 0; i < gameweekHorizon; i++) {
      outTotal += calculateExpectedPoints(playerOut, fixtureIndex: i);
      inTotal += calculateExpectedPoints(playerIn, fixtureIndex: i);
    }

    final pointsHitPenalty = isPointsHit ? 4.0 : 0.0;
    final priceSwingBonus =
        priceSwingTenths / 10.0; // tenths -> £m, 1pt per £1m rise assumption

    return double.parse(
      (inTotal - outTotal - pointsHitPenalty + priceSwingBonus)
          .toStringAsFixed(2),
    );
  }

  // ---------------------------------------------------------------
  // Differential Score
  // ---------------------------------------------------------------
  /// Per plan section 10: ownership below [ownershipThreshold]% AND
  /// Player Rating above [ratingThreshold] flags a player as a
  /// differential.
  bool isDifferential(
    PlayerEngineInput input,
    ScoredMetric rating, {
    double ownershipThreshold = 10.0,
    double ratingThreshold = 60.0,
  }) {
    return input.player.selectedByPercent < ownershipThreshold &&
        rating.value > ratingThreshold;
  }

  // ---------------------------------------------------------------
  // Confidence Score (plan section 4)
  // ---------------------------------------------------------------
  /// High when the underlying sub-scores agree with each other (all
  /// pointing the same direction); low when they conflict — e.g. great
  /// form but high rotation risk pulls confidence down even if the raw
  /// rating still looks decent.
  double calculateConfidence({
    required double formScore,
    required double fixtureEaseScore,
    required double xgiScore,
    required double minutesScore,
    required double rotationRisk,
  }) {
    final signals = [
      formScore,
      fixtureEaseScore,
      xgiScore,
      minutesScore,
      100 - rotationRisk
    ];
    final mean = _average(signals);
    final spread = _stdev(signals);
    // High mean + low spread (signals agree, and agree favorably) -> high
    // confidence. Spread is penalized directly; a very low mean caps
    // confidence even with perfect agreement (five signals agreeing
    // that a player is bad is not "high confidence to buy him").
    final confidence = (mean - spread).clamp(0, 100);
    return double.parse(confidence.toStringAsFixed(1));
  }

  // ---------------------------------------------------------------
  // Full per-player score card (convenience wrapper)
  // ---------------------------------------------------------------
  PlayerScoreCard buildScoreCard(PlayerEngineInput input) {
    final rating = calculatePlayerRating(input);
    final rotationRisk = calculateRotationRisk(input);
    final expectedPoints = calculateExpectedPoints(input);
    final captainScore = calculateCaptainScore(input);
    final differential = isDifferential(input, rating);

    final confidence = calculateConfidence(
      formScore: _normalize(input.form, _formCap),
      fixtureEaseScore: _fixtureEaseScore(input.upcomingFixtureDifficulty),
      xgiScore: _normalize(input.xgi90 ?? _xgiProxyFromForm(input), _xgi90Cap),
      minutesScore: _minutesExpectationScore(input.recentMinutes),
      rotationRisk: rotationRisk.value,
    );

    return PlayerScoreCard(
      playerId: input.player.id,
      rating: rating,
      rotationRisk: rotationRisk,
      expectedPoints: expectedPoints,
      captainScore: captainScore,
      isDifferential: differential,
      confidence: confidence,
    );
  }

  // ---------------------------------------------------------------
  // Team Rating + Gameweek Strategy (plan section 10)
  // ---------------------------------------------------------------
  TeamScoreCard buildTeamScoreCard(List<PlayerScoreCard> startingXi) {
    if (startingXi.isEmpty) {
      return const TeamScoreCard(
        rating: 0,
        stance: GameweekStance.balanced,
        reasons: ['No starting XI data available'],
      );
    }

    final avgRating = _average(startingXi.map((p) => p.rating.value));
    final highRiskCount =
        startingXi.where((p) => p.rotationRisk.value > 60).length;
    final differentialCount = startingXi.where((p) => p.isDifferential).length;

    final reasons = <String>[
      'Avg starting XI rating ${avgRating.toStringAsFixed(0)}/100',
    ];

    GameweekStance stance;
    if (highRiskCount >= 2) {
      stance = GameweekStance.defensive;
      reasons.add('$highRiskCount players with elevated rotation risk');
    } else if (differentialCount >= 2) {
      stance = GameweekStance.differentialOpportunity;
      reasons.add('$differentialCount low-ownership players rating well');
    } else if (avgRating >= 65) {
      stance = GameweekStance.attacking;
    } else {
      stance = GameweekStance.balanced;
    }

    return TeamScoreCard(rating: avgRating, stance: stance, reasons: reasons);
  }

  // ---------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------
  double _normalize(double value, double cap) =>
      (min(value / cap * 100, 100).clamp(0, 100)).toDouble();

  double _fixtureEaseScore(List<int> difficulties) {
    if (difficulties.isEmpty) return 50; // neutral when unknown
    final avg = _average(difficulties.map((d) => d.toDouble()));
    return ((5 - avg) / 4 * 100).clamp(0, 100);
  }

  double _minutesExpectationScore(List<int> recentMinutes) {
    if (recentMinutes.isEmpty) return 0;
    final avg = _average(recentMinutes.map((m) => m.toDouble()));
    return (avg / 90 * 100).clamp(0, 100);
  }

  /// Used only when no licensed xG source is configured (plan section
  /// 6): approximates attacking threat from `form` alone. Deliberately
  /// conservative (halved) since form conflates defensive contributions
  /// (clean sheets, appearance points) with attacking output.
  double _xgiProxyFromForm(PlayerEngineInput input) {
    if (input.player.position == PlayerPosition.goalkeeper ||
        input.player.position == PlayerPosition.defender) {
      return 0.1; // defenders/keepers rarely carry meaningful xGI
    }
    return (input.form / _formCap * _xgi90Cap * 0.5).clamp(0, _xgi90Cap);
  }

  double _average(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _stdev(List<double> values) {
    if (values.length < 2) return 0;
    final mean = _average(values);
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    return sqrt(variance);
  }
}

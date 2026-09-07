/// A single computed score (0–100 unless noted) plus the short,
/// human-readable reasons behind it. Every AI-facing output in plan
/// section 4 is required to carry reasons and a confidence score derived
/// from the engine, not a model's opinion — this class is that contract.
class ScoredMetric {
  final double value;
  final List<String> reasons;

  const ScoredMetric(this.value, this.reasons);

  @override
  String toString() =>
      '${value.toStringAsFixed(1)} (${reasons.join('; ')})';
}

/// Full set of section-10 metrics for one player, for one evaluation
/// window (a specific gameweek + fixture horizon).
class PlayerScoreCard {
  final int playerId;

  final ScoredMetric rating; // 0-100
  final ScoredMetric rotationRisk; // 0-100, higher = riskier
  final double expectedPoints; // raw FPL points, not 0-100
  final double captainScore; // raw FPL points, not 0-100
  final bool isDifferential;

  /// 0-100, computed from agreement between the underlying sub-scores
  /// (plan section 4: "اتفاق عدة مؤشرات مع بعض = ثقة أعلى"). This is
  /// what any AI explanation must attach to a recommendation — the AI
  /// layer never invents its own confidence number.
  final double confidence;

  const PlayerScoreCard({
    required this.playerId,
    required this.rating,
    required this.rotationRisk,
    required this.expectedPoints,
    required this.captainScore,
    required this.isDifferential,
    required this.confidence,
  });
}

/// Aggregate rating for a full starting XI (plan section 10: "Team
/// Rating"), plus a short strategy hint. The strategy text here is a
/// deterministic label, not LLM prose — the AI layer turns this into
/// natural language, it doesn't generate the label itself (section 11).
class TeamScoreCard {
  final double rating; // 0-100
  final GameweekStance stance;
  final List<String> reasons;

  const TeamScoreCard({
    required this.rating,
    required this.stance,
    required this.reasons,
  });
}

enum GameweekStance { attacking, balanced, defensive, differentialOpportunity }

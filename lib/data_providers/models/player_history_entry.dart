/// One gameweek's record for a single player, from FPL's
/// `element-summary/{id}/` `history` array. This is the only place
/// per-gameweek minutes/xG/xA come from in the current adapter — used by
/// the Statistics Engine to build [PlayerEngineInput] (rotation risk
/// needs a minutes trend, not just the latest match).
class PlayerHistoryEntry {
  final int gameweekId;
  final int minutes;

  /// Present on recent FPL seasons' element-summary payload; null on
  /// older data or if FPL removes the field again (unofficial endpoint,
  /// plan section 6's reliability caveat applies here specifically).
  final double? expectedGoals;
  final double? expectedAssists;

  const PlayerHistoryEntry({
    required this.gameweekId,
    required this.minutes,
    this.expectedGoals,
    this.expectedAssists,
  });

  factory PlayerHistoryEntry.fromFplJson(Map<String, dynamic> json) {
    return PlayerHistoryEntry(
      gameweekId: json['round'] as int,
      minutes: json['minutes'] as int? ?? 0,
      expectedGoals: double.tryParse(json['expected_goals']?.toString() ?? ''),
      expectedAssists:
          double.tryParse(json['expected_assists']?.toString() ?? ''),
    );
  }
}

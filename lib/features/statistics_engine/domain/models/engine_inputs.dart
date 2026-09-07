import '../../../../data_providers/models/player.dart';

/// Everything the deterministic engine needs about one player to compute
/// every score in plan section 10. Deliberately a flat bag of *facts*
/// (form, minutes, fixture difficulty) — never a partially-computed
/// score — so the engine itself is the only place scoring logic lives
/// (plan section 11's "فصل الـ AI عن الـ Statistics Engine" applies
/// just as strictly to keeping scoring logic out of the data layer).
class PlayerEngineInput {
  final Player player;

  /// FPL's own `form` field: average points per match over recent
  /// gameweeks. Typically 0–12ish in practice, occasionally higher.
  final double form;

  /// Minutes played in each of the last few gameweeks, most recent last.
  /// Used for both the minutes-expectation sub-score and rotation risk.
  final List<int> recentMinutes;

  /// Difficulty (FPL's 1–5 scale, lower = easier) of each of the next N
  /// fixtures, in order. Empty if the player's club has no fixture in
  /// the window (a blank gameweek).
  final List<int> upcomingFixtureDifficulty;

  /// Combined expected goals + expected assists over a recent window
  /// (e.g. last 6 gameweeks), per-90. Null when no licensed xG source is
  /// configured yet (plan section 6) — the engine falls back to a
  /// goals+assists-based proxy in that case rather than pretending a
  /// number exists.
  final double? xgi90;

  /// How many other players compete for this player's starting spot in
  /// their position at their club (plan section 10: "عدد المنافسين على
  /// المركز"). 0 = undisputed starter.
  final int positionalCompetitorCount;

  const PlayerEngineInput({
    required this.player,
    required this.form,
    required this.recentMinutes,
    required this.upcomingFixtureDifficulty,
    required this.positionalCompetitorCount,
    this.xgi90,
  });
}

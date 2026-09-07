/// A Premier League club, as referenced by FPL's `teams` array in
/// bootstrap-static. Named `Club` (not `Team`) in code to avoid clashing
/// with the user's `fantasy_teams` (their FPL squad) — a naming clash the
/// original plan's schema keeps straight only via table names.
class Club {
  final int id;
  final String name;
  final String shortName;
  final int? strengthOverallHome;
  final int? strengthOverallAway;

  const Club({
    required this.id,
    required this.name,
    required this.shortName,
    this.strengthOverallHome,
    this.strengthOverallAway,
  });

  factory Club.fromFplJson(Map<String, dynamic> json) {
    return Club(
      id: json['id'] as int,
      name: json['name'] as String,
      shortName: json['short_name'] as String,
      strengthOverallHome: json['strength_overall_home'] as int?,
      strengthOverallAway: json['strength_overall_away'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'short_name': shortName,
        'strength_overall_home': strengthOverallHome,
        'strength_overall_away': strengthOverallAway,
      };
}

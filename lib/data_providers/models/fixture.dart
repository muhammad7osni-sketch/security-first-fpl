/// Maps to schema `fixtures`. FPL's own difficulty rating is used as the
/// bootstrap source; per plan section 6, API-Football becomes the primary
/// commercial source for fixtures/lineups/live once that adapter lands —
/// this model is shape-compatible with both so switching providers means
/// changing `FixtureProvider`, not this class or its callers.
class Fixture {
  final int id;
  final int gameweekId;
  final int homeClubId;
  final int awayClubId;
  final int homeDifficulty;
  final int awayDifficulty;
  final DateTime? kickoffTime;
  final bool finished;

  const Fixture({
    required this.id,
    required this.gameweekId,
    required this.homeClubId,
    required this.awayClubId,
    required this.homeDifficulty,
    required this.awayDifficulty,
    required this.kickoffTime,
    required this.finished,
  });

  factory Fixture.fromFplJson(Map<String, dynamic> json) {
    return Fixture(
      id: json['id'] as int,
      gameweekId: json['event'] as int? ?? 0,
      homeClubId: json['team_h'] as int,
      awayClubId: json['team_a'] as int,
      homeDifficulty: json['team_h_difficulty'] as int? ?? 3,
      awayDifficulty: json['team_a_difficulty'] as int? ?? 3,
      kickoffTime: json['kickoff_time'] != null
          ? DateTime.tryParse(json['kickoff_time'] as String)
          : null,
      finished: json['finished'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameweek_id': gameweekId,
        'home_club_id': homeClubId,
        'away_club_id': awayClubId,
        'home_difficulty': homeDifficulty,
        'away_difficulty': awayDifficulty,
        'kickoff_time': kickoffTime?.toIso8601String(),
        'finished': finished,
      };
}

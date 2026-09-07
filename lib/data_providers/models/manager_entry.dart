/// A read-only snapshot of the user's official FPL squad, fetched by
/// their public `fpl_manager_id` (plan section 0: no login/session
/// simulation — this is the FPL manager ID, a public number, not a
/// credential).
class ManagerEntry {
  final int id;
  final String managerName;
  final String teamName;
  final int overallPoints;
  final int overallRank;
  final double bankTenths;
  final double teamValueTenths;

  const ManagerEntry({
    required this.id,
    required this.managerName,
    required this.teamName,
    required this.overallPoints,
    required this.overallRank,
    required this.bankTenths,
    required this.teamValueTenths,
  });

  factory ManagerEntry.fromFplJson(Map<String, dynamic> json) {
    return ManagerEntry(
      id: json['id'] as int,
      managerName:
          '${json['player_first_name'] ?? ''} ${json['player_last_name'] ?? ''}'
              .trim(),
      teamName: json['name'] as String? ?? '',
      overallPoints: json['summary_overall_points'] as int? ?? 0,
      overallRank: json['summary_overall_rank'] as int? ?? 0,
      bankTenths: (json['last_deadline_bank'] as num?)?.toDouble() ?? 0,
      teamValueTenths: (json['last_deadline_value'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One line of an `entry/{id}/event/{gw}/picks/` response: which player,
/// what squad slot, and captaincy flags — this is the read-only mirror of
/// the user's current XI/bench that the Statistics Engine and Emergency
/// Coach reason over (plan sections 3 & 10).
class SquadPick {
  final int playerId;
  final int squadPosition; // 1-15, 1-11 = starting XI
  final bool isCaptain;
  final bool isViceCaptain;
  final int multiplier; // 0 = benched, 1 = normal, 2 = captain, 3 = TC

  const SquadPick({
    required this.playerId,
    required this.squadPosition,
    required this.isCaptain,
    required this.isViceCaptain,
    required this.multiplier,
  });

  bool get isStarting => squadPosition <= 11;

  factory SquadPick.fromFplJson(Map<String, dynamic> json) {
    return SquadPick(
      playerId: json['element'] as int,
      squadPosition: json['position'] as int,
      isCaptain: json['is_captain'] as bool? ?? false,
      isViceCaptain: json['is_vice_captain'] as bool? ?? false,
      multiplier: json['multiplier'] as int? ?? 1,
    );
  }
}

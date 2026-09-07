enum PlayerPosition { goalkeeper, defender, midfielder, forward, unknown }

PlayerPosition _positionFromElementType(int elementType) {
  switch (elementType) {
    case 1:
      return PlayerPosition.goalkeeper;
    case 2:
      return PlayerPosition.defender;
    case 3:
      return PlayerPosition.midfielder;
    case 4:
      return PlayerPosition.forward;
    default:
      return PlayerPosition.unknown;
  }
}

/// Maps to schema `players` (cache table). Deliberately carries only the
/// raw facts FPL exposes — no derived scores here. Per plan section 11,
/// Player Rating / Expected Points / Rotation Risk are computed by the
/// Statistics Engine from this raw data, never invented upstream or by
/// the AI layer.
class Player {
  final int id;
  final String webName;
  final String firstName;
  final String secondName;
  final int clubId;
  final PlayerPosition position;

  /// Price in tenths of a million, as FPL returns it (e.g. 125 = £12.5m).
  final int nowCostTenths;

  final double selectedByPercent;
  final double form;
  final int minutesLastGw;
  final int totalPoints;

  /// Raw injury/availability text from FPL ("Doubtful - 75% chance of playing").
  /// This is NOT a substitute for the RotoWire/Sportmonks injuries feed
  /// (plan section 6) — it's the free baseline signal only.
  final String status; // 'a' available, 'd' doubtful, 'i' injured, 's' suspended, 'u' unavailable
  final String? news;

  const Player({
    required this.id,
    required this.webName,
    required this.firstName,
    required this.secondName,
    required this.clubId,
    required this.position,
    required this.nowCostTenths,
    required this.selectedByPercent,
    required this.form,
    required this.minutesLastGw,
    required this.totalPoints,
    required this.status,
    this.news,
  });

  double get priceMillions => nowCostTenths / 10.0;

  factory Player.fromFplJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as int,
      webName: json['web_name'] as String,
      firstName: json['first_name'] as String? ?? '',
      secondName: json['second_name'] as String? ?? '',
      clubId: json['team'] as int,
      position: _positionFromElementType(json['element_type'] as int),
      nowCostTenths: json['now_cost'] as int,
      selectedByPercent:
          double.tryParse(json['selected_by_percent']?.toString() ?? '0') ??
              0,
      form: double.tryParse(json['form']?.toString() ?? '0') ?? 0,
      minutesLastGw: json['minutes'] as int? ?? 0,
      totalPoints: json['total_points'] as int? ?? 0,
      status: json['status'] as String? ?? 'a',
      news: (json['news'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['news'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'web_name': webName,
        'first_name': firstName,
        'second_name': secondName,
        'club_id': clubId,
        'position': position.name,
        'now_cost_tenths': nowCostTenths,
        'selected_by_percent': selectedByPercent,
        'form': form,
        'minutes_last_gw': minutesLastGw,
        'total_points': totalPoints,
        'status': status,
        'news': news,
      };
}

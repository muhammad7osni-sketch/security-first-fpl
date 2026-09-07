/// One result row from FPL's public manager search endpoint:
/// GET /api/search/?text={query}&page_size=10
///
/// This endpoint is unauthenticated and returns public manager profiles.
/// We use it to let users find their own team by name instead of having
/// to know their numeric manager ID.
class FplManagerSearchResult {
  final int id;
  final String managerName;
  final String teamName;

  const FplManagerSearchResult({
    required this.id,
    required this.managerName,
    required this.teamName,
  });

  factory FplManagerSearchResult.fromFplJson(Map<String, dynamic> json) {
    final firstName = json['player_first_name'] as String? ?? '';
    final lastName = json['player_last_name'] as String? ?? '';
    return FplManagerSearchResult(
      id: json['id'] as int,
      managerName: '$firstName $lastName'.trim(),
      teamName: json['entry_name'] as String? ?? '',
    );
  }
}

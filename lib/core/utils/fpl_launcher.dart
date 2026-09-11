/// FPL launcher disabled.
///
/// Authentication and account linking must happen inside SquadIQ.
/// This file intentionally does not open the official FPL website.
class FplLauncher {
  FplLauncher._();

  static Future<bool> openHome() async => false;

  static Future<bool> openMyTeam() async => false;

  static Future<bool> openTransfers() async => false;

  static Future<bool> openPicks({int? gameweekId}) async => false;

  static Future<bool> openEntry(int entryId) async => false;

  static Future<bool> openLeagues() async => false;

  static Future<bool> openPlayer(int playerId) async => false;

  static Future<bool> openFixtures({int? gameweekId}) async => false;

  static Future<bool> openStatistics() async => false;
}
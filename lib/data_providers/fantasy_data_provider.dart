import '../core/error/result.dart';
import 'models/club.dart';
import 'models/fixture.dart';
import 'models/gameweek.dart';
import 'models/manager_entry.dart';
import 'models/manager_search_result.dart';
import 'models/player.dart';
import 'models/player_history_entry.dart';

/// The single seam the rest of the app depends on for fantasy-football
/// data. Per plan section 6: "كل مصدر بيانات وراه Interface/Adapter موحّد"
/// — swapping FPL's public endpoints for a licensed replacement later
/// means writing a new implementation of this interface, not touching
/// any feature code.
///
/// Every method is read-only by design (plan section 0): this interface
/// has no `submitTransfers`, `setCaptain`, or `playChip` method, and none
/// should be added without a separate, explicit, opt-in-gated adapter and
/// a legal sign-off — see section 0's warning.
abstract class FantasyDataProvider {
  Future<Result<List<Club>>> getClubs();

  Future<Result<List<Player>>> getPlayers();

  Future<Result<List<Gameweek>>> getGameweeks();

  Future<Result<List<Fixture>>> getFixtures({int? gameweekId});

  /// Looks up a manager by their public FPL manager ID (from their FPL
  /// profile URL) — not a login, no credentials involved.
  Future<Result<ManagerEntry>> getManagerEntry(int managerId);

  /// Searches for managers by name or team name using FPL's public search
  /// endpoint: GET /api/search/?text={query}&page_size=10
  /// Unauthenticated, returns public profiles only. Used to let users find
  /// their own team without needing to know their numeric manager ID.
  Future<Result<List<FplManagerSearchResult>>> searchManagers(String query);

  Future<Result<List<SquadPick>>> getManagerPicks({
    required int managerId,
    required int gameweekId,
  });

  /// Per-gameweek history (minutes, and xG/xA when FPL exposes them) for
  /// one player. Feeds the Statistics Engine's rotation-risk and
  /// expected-points calculations (plan section 10) — never used for
  /// scoring itself here, this adapter only returns facts.
  Future<Result<List<PlayerHistoryEntry>>> getPlayerHistory(int playerId);
}

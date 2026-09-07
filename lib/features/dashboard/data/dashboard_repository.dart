import '../../../core/error/result.dart';
import '../../../data_providers/fantasy_data_provider.dart';
import '../domain/dashboard_data.dart';

/// Assembles [DashboardData] from the read-only [FantasyDataProvider].
///
/// This is intentionally a thin composition layer, not a place for new
/// business logic: anything that looks like scoring, ranking, or
/// "which alternative should replace this player" belongs in the
/// Statistics Engine (plan sections 10-11), not here.
class DashboardRepository {
  final FantasyDataProvider _fantasyDataProvider;

  DashboardRepository(this._fantasyDataProvider);

  Future<Result<DashboardData>> load({required int fplManagerId}) async {
    final gameweeks = await _fantasyDataProvider.getGameweeks();
    final gameweeksList = gameweeks.valueOrNull;
    if (gameweeksList == null) {
      return Result.err(gameweeks.failureOrNull!);
    }

    final current = _firstWhereOrNull(gameweeksList, (g) => g.isCurrent) ??
        _firstWhereOrNull(gameweeksList, (g) => g.isNext);
    if (current == null) {
      return Result.err(const AppFailure(
        AppFailureType.unexpectedResponseShape,
        'No current or next gameweek found in FPL data',
      ));
    }
    final next = _firstWhereOrNull(gameweeksList, (g) => g.isNext);
    final deadlineGw = next ?? current;

    final managerResult =
        await _fantasyDataProvider.getManagerEntry(fplManagerId);
    final manager = managerResult.valueOrNull;
    if (manager == null) {
      return Result.err(managerResult.failureOrNull!);
    }

    final picksResult = await _fantasyDataProvider.getManagerPicks(
      managerId: fplManagerId,
      gameweekId: current.id,
    );
    final picks = picksResult.valueOrNull;
    if (picks == null) {
      return Result.err(picksResult.failureOrNull!);
    }

    final playersResult = await _fantasyDataProvider.getPlayers();
    final players = playersResult.valueOrNull;
    if (players == null) {
      return Result.err(playersResult.failureOrNull!);
    }
    final playersById = {for (final p in players) p.id: p};

    final clubsResult = await _fantasyDataProvider.getClubs();
    final clubs = clubsResult.valueOrNull;
    if (clubs == null) {
      return Result.err(clubsResult.failureOrNull!);
    }
    final clubsById = {for (final c in clubs) c.id: c};

    // Fixtures failing shouldn't block the whole dashboard - squad and
    // deadline info are still useful without the ticker. Degrade
    // gracefully to an empty list rather than erroring the whole load.
    final fixturesResult =
        await _fantasyDataProvider.getFixtures(gameweekId: deadlineGw.id);
    final fixtures = fixturesResult.valueOrNull ?? const [];

    final squad = <DashboardSquadPlayer>[];
    for (final pick in picks) {
      final player = playersById[pick.playerId];
      if (player == null) continue;
      final club = clubsById[player.clubId];
      if (club == null) continue;

      final nextFixture = _firstWhereOrNull(
        fixtures,
        (f) => f.homeClubId == club.id || f.awayClubId == club.id,
      );

      squad.add(DashboardSquadPlayer(
        player: player,
        club: club,
        isStarting: pick.isStarting,
        isCaptain: pick.isCaptain,
        isViceCaptain: pick.isViceCaptain,
        nextFixture: nextFixture,
      ));
    }

    return Result.ok(DashboardData(
      currentGameweek: current,
      nextGameweek: next,
      manager: manager,
      squad: squad,
    ));
  }

  T? _firstWhereOrNull<T>(List<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}

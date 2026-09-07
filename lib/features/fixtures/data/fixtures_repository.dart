import '../../../core/error/result.dart';
import '../../../data_providers/fantasy_data_provider.dart';
import '../../../data_providers/models/club.dart';
import '../../../data_providers/models/fixture.dart';
import '../../../data_providers/models/gameweek.dart';

/// One fixture with its clubs already resolved, ready to render.
class FixtureListEntry {
  final Fixture fixture;
  final Club home;
  final Club away;
  const FixtureListEntry({required this.fixture, required this.home, required this.away});
}

/// A gameweek's fixtures, grouped for a tabbed/sectioned view.
class GameweekFixtures {
  final Gameweek gameweek;
  final List<FixtureListEntry> fixtures;
  const GameweekFixtures({required this.gameweek, required this.fixtures});
}

class FixturesRepository {
  final FantasyDataProvider _fantasyDataProvider;

  FixturesRepository(this._fantasyDataProvider);

  Future<Result<List<GameweekFixtures>>> loadGroupedByGameweek() async {
    final gameweeksResult = await _fantasyDataProvider.getGameweeks();
    final gameweeks = gameweeksResult.valueOrNull;
    if (gameweeks == null) return Result.err(gameweeksResult.failureOrNull!);

    final fixturesResult = await _fantasyDataProvider.getFixtures();
    final fixtures = fixturesResult.valueOrNull;
    if (fixtures == null) return Result.err(fixturesResult.failureOrNull!);

    final clubsResult = await _fantasyDataProvider.getClubs();
    final clubs = clubsResult.valueOrNull;
    if (clubs == null) return Result.err(clubsResult.failureOrNull!);

    return Result.ok(groupByGameweek(gameweeks, fixtures, clubs));
  }

  /// Pure grouping/sorting logic, split out from the fetch above so it
  /// can be unit-tested without a data source.
  List<GameweekFixtures> groupByGameweek(
    List<Gameweek> gameweeks,
    List<Fixture> fixtures,
    List<Club> clubs,
  ) {
    final clubsById = {for (final c in clubs) c.id: c};
    final byGw = <int, List<FixtureListEntry>>{};

    for (final f in fixtures) {
      final home = clubsById[f.homeClubId];
      final away = clubsById[f.awayClubId];
      if (home == null || away == null) continue;
      byGw.putIfAbsent(f.gameweekId, () => []).add(
            FixtureListEntry(fixture: f, home: home, away: away),
          );
    }

    final result = gameweeks
        .where((gw) => byGw.containsKey(gw.id))
        .map((gw) => GameweekFixtures(gameweek: gw, fixtures: byGw[gw.id]!))
        .toList()
      ..sort((a, b) => a.gameweek.number.compareTo(b.gameweek.number));

    return result;
  }
}

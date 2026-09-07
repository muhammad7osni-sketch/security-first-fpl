import 'package:flutter_test/flutter_test.dart';
import 'package:squadiq/core/error/result.dart';
import 'package:squadiq/data_providers/fantasy_data_provider.dart';
import 'package:squadiq/data_providers/models/club.dart';
import 'package:squadiq/data_providers/models/fixture.dart';
import 'package:squadiq/data_providers/models/gameweek.dart';
import 'package:squadiq/data_providers/models/manager_entry.dart';
import 'package:squadiq/data_providers/models/manager_search_result.dart';
import 'package:squadiq/data_providers/models/player.dart';
import 'package:squadiq/data_providers/models/player_history_entry.dart';
import 'package:squadiq/features/statistics_engine/data/statistics_repository.dart';
import 'package:squadiq/features/transfers/data/transfers_repository.dart';

const _clubA = Club(id: 1, name: 'Club A', shortName: 'CLA');
const _clubB = Club(id: 2, name: 'Club B', shortName: 'CLB');

Player _forward({
  required int id,
  required String name,
  required int clubId,
  double form = 5,
  int priceTenths = 70,
  String status = 'a',
}) {
  return Player(
    id: id,
    webName: name,
    firstName: name,
    secondName: '',
    clubId: clubId,
    position: PlayerPosition.forward,
    nowCostTenths: priceTenths,
    selectedByPercent: 10,
    form: form,
    minutesLastGw: 90,
    totalPoints: 40,
    status: status,
  );
}

/// A fully deterministic fake honoring [FantasyDataProvider] - no
/// network, no caching quirks - so these tests exercise
/// [TransfersRepository]'s own filtering/ranking logic in isolation.
class _FakeFantasyDataProvider implements FantasyDataProvider {
  final List<Player> players;
  final List<Club> clubs;
  final List<Fixture> fixtures;

  _FakeFantasyDataProvider({
    required this.players,
    required this.clubs,
  }) : fixtures = const [];

  @override
  Future<Result<List<Club>>> getClubs() async => Result.ok(clubs);

  @override
  Future<Result<List<Player>>> getPlayers() async => Result.ok(players);

  @override
  Future<Result<List<Gameweek>>> getGameweeks() async => Result.ok([]);

  @override
  Future<Result<List<Fixture>>> getFixtures({int? gameweekId}) async =>
      Result.ok(fixtures);

  @override
  Future<Result<ManagerEntry>> getManagerEntry(int managerId) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<SquadPick>>> getManagerPicks({
    required int managerId,
    required int gameweekId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<PlayerHistoryEntry>>> getPlayerHistory(
      int playerId) async {
    return Result.ok([
      const PlayerHistoryEntry(gameweekId: 1, minutes: 90),
      const PlayerHistoryEntry(gameweekId: 2, minutes: 90),
    ]);
  }

  @override
  Future<Result<List<FplManagerSearchResult>>> searchManagers(
          String query) async =>
      Result.ok([]);
}

void main() {
  test('a much better, affordable same-position player is suggested first',
      () async {
    final playerOut =
        _forward(id: 1, name: 'Weak Forward', clubId: _clubA.id, form: 2);
    final weakAlt =
        _forward(id: 2, name: 'Similar Forward', clubId: _clubA.id, form: 2.5);
    final strongAlt =
        _forward(id: 3, name: 'Strong Forward', clubId: _clubB.id, form: 8);

    final fake = _FakeFantasyDataProvider(
      players: [playerOut, weakAlt, strongAlt],
      clubs: const [_clubA, _clubB],
    );
    final statsRepo = StatisticsRepository(fake);
    final repo = TransfersRepository(fake, statsRepo);

    final result = await repo.suggestReplacements(
      playerOut: playerOut,
      bankTenths: 100, // plenty of budget
    );

    final candidates = result.valueOrNull;
    expect(candidates, isNotNull);
    expect(candidates, isNotEmpty);
    expect(candidates!.first.player.id, strongAlt.id);
  });

  test('a different-position player is never suggested', () async {
    final playerOut = _forward(id: 1, name: 'Forward Out', clubId: _clubA.id);
    final midfielder = Player(
      id: 2,
      webName: 'Some Midfielder',
      firstName: 'Some',
      secondName: 'Midfielder',
      clubId: _clubB.id,
      position: PlayerPosition.midfielder,
      nowCostTenths: 70,
      selectedByPercent: 10,
      form: 9,
      minutesLastGw: 90,
      totalPoints: 60,
      status: 'a',
    );

    final fake = _FakeFantasyDataProvider(
      players: [playerOut, midfielder],
      clubs: const [_clubA, _clubB],
    );
    final repo = TransfersRepository(fake, StatisticsRepository(fake));

    final result =
        await repo.suggestReplacements(playerOut: playerOut, bankTenths: 100);
    final candidates = result.valueOrNull!;

    expect(candidates.any((c) => c.player.id == midfielder.id), isFalse);
  });

  test('a same-position player outside the budget is never suggested',
      () async {
    final playerOut = _forward(
        id: 1, name: 'Cheap Forward', clubId: _clubA.id, priceTenths: 50);
    final expensiveAlt = _forward(
      id: 2,
      name: 'Expensive Forward',
      clubId: _clubB.id,
      priceTenths: 200,
      form: 9,
    );

    final fake = _FakeFantasyDataProvider(
      players: [playerOut, expensiveAlt],
      clubs: const [_clubA, _clubB],
    );
    final repo = TransfersRepository(fake, StatisticsRepository(fake));

    // Bank only covers a 10-tenths (£1m) price rise, nowhere near enough
    // for the 150-tenths (£15m) gap to the expensive alternative.
    final result =
        await repo.suggestReplacements(playerOut: playerOut, bankTenths: 10);
    final candidates = result.valueOrNull!;

    expect(candidates.any((c) => c.player.id == expensiveAlt.id), isFalse);
  });

  test('an unavailable (injured/suspended) player is never suggested',
      () async {
    final playerOut = _forward(id: 1, name: 'Forward Out', clubId: _clubA.id);
    final injuredAlt = _forward(
        id: 2,
        name: 'Injured Forward',
        clubId: _clubB.id,
        form: 9,
        status: 'i');

    final fake = _FakeFantasyDataProvider(
      players: [playerOut, injuredAlt],
      clubs: const [_clubA, _clubB],
    );
    final repo = TransfersRepository(fake, StatisticsRepository(fake));

    final result =
        await repo.suggestReplacements(playerOut: playerOut, bankTenths: 100);
    final candidates = result.valueOrNull!;

    expect(candidates.any((c) => c.player.id == injuredAlt.id), isFalse);
  });

  test('no valid candidates returns an empty list, not an error', () async {
    final playerOut = _forward(id: 1, name: 'Only Forward', clubId: _clubA.id);

    final fake =
        _FakeFantasyDataProvider(players: [playerOut], clubs: const [_clubA]);
    final repo = TransfersRepository(fake, StatisticsRepository(fake));

    final result =
        await repo.suggestReplacements(playerOut: playerOut, bankTenths: 100);

    expect(result.isOk, isTrue);
    expect(result.valueOrNull, isEmpty);
  });
}

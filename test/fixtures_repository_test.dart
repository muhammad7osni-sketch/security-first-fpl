import 'package:flutter_test/flutter_test.dart';
import 'package:squadiq/data_providers/fantasy_data_provider.dart';
import 'package:squadiq/data_providers/models/club.dart';
import 'package:squadiq/data_providers/models/fixture.dart';
import 'package:squadiq/data_providers/models/gameweek.dart';
import 'package:squadiq/features/fixtures/data/fixtures_repository.dart';

const _clubA = Club(id: 1, name: 'Club A', shortName: 'CLA');
const _clubB = Club(id: 2, name: 'Club B', shortName: 'CLB');
const _clubC = Club(id: 3, name: 'Club C', shortName: 'CLC');

Gameweek _gw(int id, int number) {
  return Gameweek(
    id: id,
    number: number,
    deadlineTime: DateTime.utc(2026, 1, id),
    isCurrent: false,
    isNext: false,
    finished: false,
  );
}

/// FixturesRepository's constructor requires a FantasyDataProvider, but
/// groupByGameweek() (the method under test) never calls it - this stub
/// exists only to satisfy the constructor.
class _UnusedFantasyDataProvider implements FantasyDataProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not used by groupByGameweek() tests');
}

void main() {
  final repo = FixturesRepository(_UnusedFantasyDataProvider());

  test('fixtures are grouped under the correct gameweek', () {
    final gameweeks = [_gw(1, 1), _gw(2, 2)];
    final fixtures = [
      const Fixture(
        id: 1,
        gameweekId: 1,
        homeClubId: 1,
        awayClubId: 2,
        homeDifficulty: 2,
        awayDifficulty: 3,
        kickoffTime: null,
        finished: false,
      ),
      const Fixture(
        id: 2,
        gameweekId: 2,
        homeClubId: 2,
        awayClubId: 3,
        homeDifficulty: 4,
        awayDifficulty: 2,
        kickoffTime: null,
        finished: false,
      ),
    ];
    final clubs = [_clubA, _clubB, _clubC];

    final grouped = repo.groupByGameweek(gameweeks, fixtures, clubs);

    expect(grouped.length, 2);
    expect(grouped[0].gameweek.number, 1);
    expect(grouped[0].fixtures.single.fixture.id, 1);
    expect(grouped[1].gameweek.number, 2);
    expect(grouped[1].fixtures.single.fixture.id, 2);
  });

  test('gameweeks with no fixtures are omitted, not shown empty', () {
    final gameweeks = [_gw(1, 1), _gw(2, 2)];
    final fixtures = [
      const Fixture(
        id: 1,
        gameweekId: 1,
        homeClubId: 1,
        awayClubId: 2,
        homeDifficulty: 2,
        awayDifficulty: 3,
        kickoffTime: null,
        finished: false,
      ),
    ];
    final clubs = [_clubA, _clubB];

    final grouped = repo.groupByGameweek(gameweeks, fixtures, clubs);

    expect(grouped.length, 1);
    expect(grouped.single.gameweek.number, 1);
  });

  test('a fixture referencing an unknown club is skipped rather than '
      'crashing', () {
    final gameweeks = [_gw(1, 1)];
    final fixtures = [
      const Fixture(
        id: 1,
        gameweekId: 1,
        homeClubId: 1,
        awayClubId: 999, // not in clubs list
        homeDifficulty: 2,
        awayDifficulty: 3,
        kickoffTime: null,
        finished: false,
      ),
    ];
    final clubs = [_clubA];

    final grouped = repo.groupByGameweek(gameweeks, fixtures, clubs);

    expect(grouped, isEmpty);
  });

  test('groups are sorted by gameweek number, regardless of input order', () {
    final gameweeks = [_gw(2, 2), _gw(1, 1)];
    final fixtures = [
      const Fixture(
        id: 1,
        gameweekId: 1,
        homeClubId: 1,
        awayClubId: 2,
        homeDifficulty: 2,
        awayDifficulty: 3,
        kickoffTime: null,
        finished: false,
      ),
      const Fixture(
        id: 2,
        gameweekId: 2,
        homeClubId: 2,
        awayClubId: 1,
        homeDifficulty: 3,
        awayDifficulty: 2,
        kickoffTime: null,
        finished: false,
      ),
    ];
    final clubs = [_clubA, _clubB];

    final grouped = repo.groupByGameweek(gameweeks, fixtures, clubs);

    expect(grouped.map((g) => g.gameweek.number).toList(), [1, 2]);
  });
}

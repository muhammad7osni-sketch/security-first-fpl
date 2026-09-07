import '../../../core/error/result.dart';
import '../../../data_providers/fantasy_data_provider.dart';
import '../../../data_providers/models/club.dart';
import '../../../data_providers/models/player.dart';

/// One entry in the browsable player list: a player plus its resolved
/// club, ready for a list/search UI.
class PlayerListEntry {
  final Player player;
  final Club club;
  const PlayerListEntry({required this.player, required this.club});
}

enum PlayerSortBy { form, totalPoints, priceHigh, priceLow, ownership }

/// Read-only browsing over the full ~600-player pool.
///
/// Deliberately does NOT run every player through the Statistics Engine
/// — `getPlayerHistory()` is one HTTP call per player, and scoring the
/// entire pool on every screen open would mean hundreds of requests
/// against an unofficial, rate-limit-unknown endpoint (plan section 21's
/// caution applies directly here). This screen shows FPL's own raw
/// stats (form, points, price, ownership) for browsing/searching; full
/// engine scoring is reserved for bounded sets — a 15-man squad
/// (dashboard), or the small pre-filtered candidate shortlist Transfers
/// builds before scoring (see `TransfersRepository`).
class PlayersRepository {
  final FantasyDataProvider _fantasyDataProvider;

  PlayersRepository(this._fantasyDataProvider);

  Future<Result<List<PlayerListEntry>>> loadAll() async {
    final playersResult = await _fantasyDataProvider.getPlayers();
    final players = playersResult.valueOrNull;
    if (players == null) return Result.err(playersResult.failureOrNull!);

    final clubsResult = await _fantasyDataProvider.getClubs();
    final clubs = clubsResult.valueOrNull;
    if (clubs == null) return Result.err(clubsResult.failureOrNull!);

    final clubsById = {for (final c in clubs) c.id: c};
    final entries = <PlayerListEntry>[];
    for (final p in players) {
      final club = clubsById[p.clubId];
      if (club == null) continue;
      entries.add(PlayerListEntry(player: p, club: club));
    }
    return Result.ok(entries);
  }

  List<PlayerListEntry> filterAndSort(
    List<PlayerListEntry> entries, {
    PlayerPosition? position,
    String query = '',
    PlayerSortBy sortBy = PlayerSortBy.form,
  }) {
    var filtered = entries.where((e) {
      if (position != null && e.player.position != position) return false;
      if (query.isNotEmpty &&
          !e.player.webName.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (sortBy) {
        case PlayerSortBy.form:
          return b.player.form.compareTo(a.player.form);
        case PlayerSortBy.totalPoints:
          return b.player.totalPoints.compareTo(a.player.totalPoints);
        case PlayerSortBy.priceHigh:
          return b.player.nowCostTenths.compareTo(a.player.nowCostTenths);
        case PlayerSortBy.priceLow:
          return a.player.nowCostTenths.compareTo(b.player.nowCostTenths);
        case PlayerSortBy.ownership:
          return b.player.selectedByPercent.compareTo(a.player.selectedByPercent);
      }
    });

    return filtered;
  }
}

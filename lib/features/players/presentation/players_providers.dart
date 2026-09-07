import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data_providers/models/player.dart';
import '../data/players_repository.dart';

final playersRepositoryProvider = Provider<PlayersRepository>((ref) {
  return PlayersRepository(ref.watch(fantasyDataProviderProvider));
});

final allPlayersProvider = FutureProvider<List<PlayerListEntry>>((ref) async {
  final repo = ref.watch(playersRepositoryProvider);
  final result = await repo.loadAll();
  return result.when(ok: (v) => v, err: (failure) => throw failure);
});

class PlayersFilterState {
  final PlayerPosition? position;
  final String query;
  final PlayerSortBy sortBy;

  const PlayersFilterState({
    this.position,
    this.query = '',
    this.sortBy = PlayerSortBy.form,
  });

  PlayersFilterState copyWith({
    PlayerPosition? position,
    bool clearPosition = false,
    String? query,
    PlayerSortBy? sortBy,
  }) {
    return PlayersFilterState(
      position: clearPosition ? null : (position ?? this.position),
      query: query ?? this.query,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

final playersFilterProvider =
    StateProvider<PlayersFilterState>((ref) => const PlayersFilterState());

final filteredPlayersProvider = Provider<AsyncValue<List<PlayerListEntry>>>((ref) {
  final asyncAll = ref.watch(allPlayersProvider);
  final filter = ref.watch(playersFilterProvider);
  final repo = ref.watch(playersRepositoryProvider);

  return asyncAll.whenData((all) => repo.filterAndSort(
        all,
        position: filter.position,
        query: filter.query,
        sortBy: filter.sortBy,
      ));
});

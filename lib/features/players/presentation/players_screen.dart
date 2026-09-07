import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data_providers/models/player.dart';
import 'players_providers.dart';
import '../data/players_repository.dart';

class PlayersScreen extends ConsumerWidget {
  const PlayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPlayers = ref.watch(filteredPlayersProvider);
    final filter = ref.watch(playersFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Players')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search players…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => ref
                  .read(playersFilterProvider.notifier)
                  .update((s) => s.copyWith(query: value)),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _PositionChip(label: 'All', position: null, current: filter.position),
                _PositionChip(
                    label: 'GK', position: PlayerPosition.goalkeeper, current: filter.position),
                _PositionChip(
                    label: 'DEF', position: PlayerPosition.defender, current: filter.position),
                _PositionChip(
                    label: 'MID', position: PlayerPosition.midfielder, current: filter.position),
                _PositionChip(
                    label: 'FWD', position: PlayerPosition.forward, current: filter.position),
                const SizedBox(width: 12),
                _SortChip(sortBy: PlayerSortBy.form, label: 'Form', current: filter.sortBy),
                _SortChip(
                    sortBy: PlayerSortBy.totalPoints, label: 'Points', current: filter.sortBy),
                _SortChip(
                    sortBy: PlayerSortBy.priceHigh, label: 'Price ↓', current: filter.sortBy),
                _SortChip(
                    sortBy: PlayerSortBy.ownership, label: 'Owned %', current: filter.sortBy),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: asyncPlayers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Failed to load players: $error')),
              data: (players) => ListView.builder(
                itemCount: players.length,
                itemBuilder: (context, index) => _PlayerTile(entry: players[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionChip extends ConsumerWidget {
  final String label;
  final PlayerPosition? position;
  final PlayerPosition? current;

  const _PositionChip({required this.label, required this.position, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = position == current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => ref.read(playersFilterProvider.notifier).update(
              (s) => s.copyWith(position: position, clearPosition: position == null),
            ),
      ),
    );
  }
}

class _SortChip extends ConsumerWidget {
  final PlayerSortBy sortBy;
  final String label;
  final PlayerSortBy current;

  const _SortChip({required this.sortBy, required this.label, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = sortBy == current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            ref.read(playersFilterProvider.notifier).update((s) => s.copyWith(sortBy: sortBy)),
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final PlayerListEntry entry;
  const _PlayerTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final player = entry.player;
    return ListTile(
      title: Text(player.webName),
      subtitle: Text('${entry.club.shortName} · ${_positionLabel(player.position)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('£${player.priceMillions.toStringAsFixed(1)}m'),
          Text(
            'Form ${player.form.toStringAsFixed(1)} · ${player.totalPoints}pts',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _positionLabel(PlayerPosition position) {
    switch (position) {
      case PlayerPosition.goalkeeper:
        return 'GK';
      case PlayerPosition.defender:
        return 'DEF';
      case PlayerPosition.midfielder:
        return 'MID';
      case PlayerPosition.forward:
        return 'FWD';
      case PlayerPosition.unknown:
        return '—';
    }
  }
}

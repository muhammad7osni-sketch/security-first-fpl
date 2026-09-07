import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/status_colors.dart';
import '../data/fixtures_repository.dart';
import 'fixtures_providers.dart';

class FixturesScreen extends ConsumerWidget {
  const FixturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGrouped = ref.watch(groupedFixturesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fixtures')),
      body: asyncGrouped.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load fixtures: $error')),
        data: (grouped) {
          if (grouped.isEmpty) {
            return const Center(child: Text('No fixtures available.'));
          }
          final initialIndex = grouped.indexWhere((g) => g.gameweek.isCurrent);
          return DefaultTabController(
            length: grouped.length,
            initialIndex: initialIndex >= 0 ? initialIndex : 0,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: [
                    for (final g in grouped) Tab(text: 'GW${g.gameweek.number}'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final g in grouped) _GameweekFixtureList(group: g),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GameweekFixtureList extends StatelessWidget {
  final GameweekFixtures group;
  const _GameweekFixtureList({required this.group});

  @override
  Widget build(BuildContext context) {
    if (group.fixtures.isEmpty) {
      return const Center(child: Text('No fixtures this gameweek.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: group.fixtures.length,
      itemBuilder: (context, index) => _FixtureCard(entry: group.fixtures[index]),
    );
  }
}

class _FixtureCard extends StatelessWidget {
  final FixtureListEntry entry;
  const _FixtureCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final f = entry.fixture;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(entry.home.name, textAlign: TextAlign.right),
            ),
            _DifficultyBadge(difficulty: f.homeDifficulty),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('vs', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            _DifficultyBadge(difficulty: f.awayDifficulty),
            Expanded(child: Text(entry.away.name)),
          ],
        ),
      ),
    );
  }
}

class _DifficultyBadge extends StatelessWidget {
  final int difficulty;
  const _DifficultyBadge({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    final color = switch (difficulty) {
      <= 2 => status.good,
      3 => status.warning,
      _ => status.critical,
    };
    return CircleAvatar(
      radius: 12,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Text(
        '$difficulty',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

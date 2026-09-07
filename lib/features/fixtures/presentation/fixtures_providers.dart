import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/fixtures_repository.dart';

final fixturesRepositoryProvider = Provider<FixturesRepository>((ref) {
  return FixturesRepository(ref.watch(fantasyDataProviderProvider));
});

final groupedFixturesProvider = FutureProvider<List<GameweekFixtures>>((ref) async {
  final repo = ref.watch(fixturesRepositoryProvider);
  final result = await repo.loadGroupedByGameweek();
  return result.when(ok: (v) => v, err: (failure) => throw failure);
});

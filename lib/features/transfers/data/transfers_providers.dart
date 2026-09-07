import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../statistics_engine/data/statistics_providers.dart';
import 'transfers_repository.dart';

final transfersRepositoryProvider = Provider<TransfersRepository>((ref) {
  return TransfersRepository(
    ref.watch(fantasyDataProviderProvider),
    ref.watch(statisticsRepositoryProvider),
  );
});

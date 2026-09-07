import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_providers/fantasy_data_provider.dart';
import '../data_providers/fpl_provider.dart';

/// Provider for the fantasy data source. Every feature should depend on
/// this (the interface), never on [FplProvider] directly — this is what
/// makes "swap FPL for a licensed source later" (plan section 6) an
/// override of one line, here.
final fantasyDataProviderProvider = Provider<FantasyDataProvider>((ref) {
  return FplProvider();
});

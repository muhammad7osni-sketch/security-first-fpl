import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_providers.dart';
import '../domain/coin_transaction.dart';
import '../data/wallet_repository.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.watch(supabaseClientProvider));
});

final walletBalanceProvider = FutureProvider<int>((ref) async {
  final appUser = await ref.watch(currentAppUserProvider.future);
  if (appUser == null) return 0;
  final repo = ref.watch(walletRepositoryProvider);
  final result = await repo.getBalance(appUser.id);
  return result.when(ok: (v) => v, err: (_) => 0);
});

final walletTransactionsProvider = FutureProvider<List<CoinTransaction>>((ref) async {
  final appUser = await ref.watch(currentAppUserProvider.future);
  if (appUser == null) return const [];
  final repo = ref.watch(walletRepositoryProvider);
  final result = await repo.getRecentTransactions(appUser.id);
  return result.when(ok: (v) => v, err: (_) => const []);
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/stat_number.dart';
import '../domain/coin_transaction.dart';
import 'wallet_providers.dart';

/// Read-only wallet view (plan section 5). No spend/purchase UI here -
/// see `WalletRepository`'s doc comment for why that needs a backend
/// service role this Flutter-only slice doesn't include yet.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncBalance = ref.watch(walletBalanceProvider);
    final asyncTransactions = ref.watch(walletTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.monetization_on_outlined,
                      size: 36, color: context.status.featured),
                  const SizedBox(height: 8),
                  asyncBalance.when(
                    loading: () => const CircularProgressIndicator(),
                    error: (_, __) => const Text('—'),
                    data: (balance) => StatNumber(
                      value: '$balance',
                      label: 'COINS',
                      valueStyle: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          asyncTransactions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('$error'),
            data: (transactions) {
              if (transactions.isEmpty) {
                return const Text('No transactions yet.');
              }
              return Column(
                children: [for (final t in transactions) _TransactionTile(transaction: t)],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final CoinTransaction transaction;
  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.amount >= 0;
    final status = context.status;
    final color = isCredit ? status.good : status.critical;
    return ListTile(
      leading: Icon(
        isCredit ? Icons.add_circle_outline : Icons.remove_circle_outline,
        color: color,
      ),
      title: Text(_typeLabel(transaction.type)),
      subtitle: Text(transaction.createdAt.toLocal().toString()),
      trailing: Text(
        '${isCredit ? '+' : ''}${transaction.amount}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _typeLabel(CoinTransactionType type) {
    switch (type) {
      case CoinTransactionType.purchase:
        return 'Purchase';
      case CoinTransactionType.dailyReward:
        return 'Daily reward';
      case CoinTransactionType.referral:
        return 'Referral bonus';
      case CoinTransactionType.achievement:
        return 'Achievement';
      case CoinTransactionType.spend:
        return 'Spent';
      case CoinTransactionType.unknown:
        return 'Transaction';
    }
  }
}

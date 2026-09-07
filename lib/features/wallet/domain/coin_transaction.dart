enum CoinTransactionType { purchase, dailyReward, referral, achievement, spend, unknown }

CoinTransactionType _typeFromString(String raw) {
  switch (raw) {
    case 'purchase':
      return CoinTransactionType.purchase;
    case 'daily_reward':
      return CoinTransactionType.dailyReward;
    case 'referral':
      return CoinTransactionType.referral;
    case 'achievement':
      return CoinTransactionType.achievement;
    case 'spend':
      return CoinTransactionType.spend;
    default:
      return CoinTransactionType.unknown;
  }
}

/// Maps to a row in the append-only `coin_transactions` ledger
/// (schema.sql). This app never writes to this table directly — see
/// `WalletRepository`'s doc comment — so this model is read-only by
/// construction: no `toJson`, nothing that implies the client can create
/// one.
class CoinTransaction {
  final String id;
  final int amount; // positive = credit, negative = debit
  final CoinTransactionType type;
  final DateTime createdAt;

  const CoinTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
  });

  factory CoinTransaction.fromSupabaseRow(Map<String, dynamic> row) {
    return CoinTransaction(
      id: row['id'] as String,
      amount: row['amount'] as int,
      type: _typeFromString(row['type'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

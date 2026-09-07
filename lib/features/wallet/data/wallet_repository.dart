import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/result.dart';
import '../domain/coin_transaction.dart';

/// Read-only view over `wallets` / `coin_transactions` (schema.sql).
///
/// Per plan section 5 and the schema's own RLS policy, coin balances are
/// only ever changed by a backend service role after server-side
/// receipt validation — the authenticated client role has no
/// insert/update/delete grant on `coin_transactions`, and this
/// repository doesn't attempt any (there is deliberately no `spend()` or
/// `credit()` method here). Actual purchase/spend flows require that
/// backend piece, which is out of scope for this Flutter-only slice —
/// see the README's monetization status note.
class WalletRepository {
  final sb.SupabaseClient _client;

  WalletRepository(this._client);

  Future<Result<int>> getBalance(String userId) async {
    try {
      final row = await _client
          .from('wallets')
          .select('coin_balance')
          .eq('user_id', userId)
          .maybeSingle();
      return Result.ok(row?['coin_balance'] as int? ?? 0);
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  Future<Result<List<CoinTransaction>>> getRecentTransactions(
    String walletUserId, {
    int limit = 30,
  }) async {
    try {
      final rows = await _client
          .from('coin_transactions')
          .select()
          .eq('wallet_id', walletUserId)
          .order('created_at', ascending: false)
          .limit(limit);
      return Result.ok(
        (rows as List).cast<Map<String, dynamic>>().map(CoinTransaction.fromSupabaseRow).toList(),
      );
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }
}

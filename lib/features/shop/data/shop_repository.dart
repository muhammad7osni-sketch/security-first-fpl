import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/result.dart';
import '../domain/store_product.dart';

/// Read-only product catalog + purchase submission.
///
/// Actual payment happens through the platform store (Google Play /
/// App Store in-app purchase APIs), which this Flutter-only slice does
/// not integrate — there's no `in_app_purchase` package wired up here.
/// `submitPurchase()` assumes the caller already has a platform receipt
/// string and only forwards it to the `validate-purchase` edge function
/// for server-side verification and coin crediting. Wiring the actual
/// platform purchase flow (showing the native purchase sheet, obtaining
/// a receipt) is a real remaining piece — see the README.
class ShopRepository {
  final sb.SupabaseClient _client;

  ShopRepository(this._client);

  Future<Result<List<StoreProduct>>> loadProducts() async {
    try {
      final rows = await _client.from('store_products').select();
      return Result.ok(
        (rows as List).cast<Map<String, dynamic>>().map(StoreProduct.fromSupabaseRow).toList(),
      );
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  /// Sends a platform receipt to the `validate-purchase` edge function
  /// (supabase/functions/validate-purchase) for server-side validation.
  /// Never credits coins or writes `purchases`/`coin_transactions`
  /// directly from the client — that write path is intentionally
  /// unavailable to the authenticated role (schema.sql's RLS policy).
  Future<Result<PurchaseStatus>> submitPurchase({
    required String productId,
    required String platformReceipt,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'validate-purchase',
        body: {'product_id': productId, 'receipt': platformReceipt},
      );

      if (response.status != 200) {
        return Result.err(AppFailure(
          AppFailureType.network,
          'Purchase validation returned status ${response.status}',
        ));
      }

      final statusStr = (response.data as Map)['status'] as String? ?? 'failed';
      return Result.ok(_parseStatus(statusStr));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  PurchaseStatus _parseStatus(String raw) {
    switch (raw) {
      case 'validated':
        return PurchaseStatus.validated;
      case 'refunded':
        return PurchaseStatus.refunded;
      case 'pending':
        return PurchaseStatus.pending;
      default:
        return PurchaseStatus.failed;
    }
  }
}

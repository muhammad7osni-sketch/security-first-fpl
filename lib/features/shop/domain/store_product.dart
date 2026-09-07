/// Maps to `store_products` (schema.sql). Read-only reference data —
/// products are configured server-side (or directly in the DB), never
/// created by the client.
class StoreProduct {
  final String id;
  final String name;
  final int? priceCoins;
  final int? priceMoneyCents;
  final String featureKey;

  const StoreProduct({
    required this.id,
    required this.name,
    required this.featureKey,
    this.priceCoins,
    this.priceMoneyCents,
  });

  factory StoreProduct.fromSupabaseRow(Map<String, dynamic> row) {
    return StoreProduct(
      id: row['id'] as String,
      name: row['name'] as String,
      featureKey: row['feature_key'] as String,
      priceCoins: row['price_coins'] as int?,
      priceMoneyCents: row['price_money_cents'] as int?,
    );
  }

  String get priceLabel {
    if (priceCoins != null) return '$priceCoins coins';
    if (priceMoneyCents != null) return '\$${(priceMoneyCents! / 100).toStringAsFixed(2)}';
    return '—';
  }
}

enum PurchaseStatus { pending, validated, refunded, failed }

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/shop_providers.dart';
import '../domain/store_product.dart';

/// Product catalog screen. The "Buy" action here is intentionally a
/// placeholder message, not a working purchase - there is no
/// in_app_purchase platform integration in this slice yet (see
/// ShopRepository's doc comment). Wiring a real purchase means: native
/// purchase sheet -> platform receipt -> ShopRepository.submitPurchase
/// -> validate-purchase edge function (which itself still needs real
/// Apple/Google receipt verification, not just the stub currently
/// there).
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProducts = ref.watch(storeProductsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shop')),
      body: asyncProducts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load products: $error')),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No products configured yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            itemBuilder: (context, index) => _ProductCard(product: products[index]),
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final StoreProduct product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(product.name),
        subtitle: Text(product.priceLabel),
        trailing: FilledButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Purchasing isn't wired up yet - needs a native "
                "in-app-purchase integration to get a real receipt first.",
              ),
            ),
          ),
          child: const Text('Buy'),
        ),
      ),
    );
  }
}

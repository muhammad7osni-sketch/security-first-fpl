import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_providers.dart';
import '../domain/store_product.dart';
import 'shop_repository.dart';

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository(ref.watch(supabaseClientProvider));
});

final storeProductsProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final repo = ref.watch(shopRepositoryProvider);
  final result = await repo.loadProducts();
  return result.when(ok: (v) => v, err: (failure) => throw failure);
});

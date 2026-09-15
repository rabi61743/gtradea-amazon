import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// A saved row as the server holds it.
///
/// The same shape as a cart row, because it is the same kind of record: a
/// product the account has put aside, with the snapshot taken when it was
/// saved so the list still renders after the upstream listing changes.
class ServerWishlistItem {
  const ServerWishlistItem({
    required this.id,
    this.productId,
    this.sourceProductId,
    this.source = 'local',
    this.category,
    this.productData = const {},
  });

  /// The server row id. Removal addresses this, not the product.
  final String id;

  final String? productId;

  /// The catalogue key for an imported product. Which of this and [productId]
  /// is set depends on where the product came from.
  final String? sourceProductId;

  final String source;
  final String? category;

  /// Name, price and picture as they were when it was saved.
  final Map<String, dynamic> productData;

  /// The catalogue key this row is for, whichever column it landed in.
  String get key => sourceProductId ?? productId ?? id;

  factory ServerWishlistItem.fromJson(Map<String, dynamic> json) {
    // A local catalogue row carries its fields in a joined `product` object
    // instead of `product_data`. Only one is ever populated.
    final data = asMap(json['product_data']).isNotEmpty
        ? asMap(json['product_data'])
        : asMap(json['product']);

    return ServerWishlistItem(
      id: asString(json['id']) ?? '',
      productId: asString(json['product_id']),
      sourceProductId: asString(json['source_product_id']),
      source: asString(json['source']) ?? 'local',
      category: asString(json['category']) ?? asString(data['category']),
      productData: data,
    );
  }
}

/// The signed-in shopper's wishlist, on the server.
///
/// `/wishlist` is the route the sibling storefront has used since it shipped --
/// list, add, remove by row id, clear -- and it answers 401 unauthenticated,
/// which is what makes it the account's list rather than the device's. A guest
/// has no server wishlist at all, which is why [WishlistStore] keeps a local
/// one and reconciles on sign-in.
class WishlistRepository {
  WishlistRepository._();

  static final WishlistRepository instance = WishlistRepository._();

  Dio get _dio => ApiClient.http;

  Future<List<ServerWishlistItem>> list() => guarded(() async {
    final res = await _dio.get('/wishlist');
    return asRows(res.data, key: 'items')
        .map(ServerWishlistItem.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  });

  /// Saves a product and returns the row the server created.
  Future<ServerWishlistItem> add({
    required String source,
    String? sourceProductId,
    String? productId,
    String? category,
    Map<String, dynamic>? productData,
  }) {
    return guarded(() async {
      final res = await _dio.post(
        '/wishlist',
        data: {
          // Passed explicitly rather than defaulted: an imported product and a
          // local one are stored in different columns, and guessing here files
          // the row where nothing will find it again.
          'source': source,
          'category': ?category,
          'source_product_id': ?sourceProductId,
          'product_id': ?productId,
          'product_data': ?productData,
        },
      );
      return ServerWishlistItem.fromJson(asMap(res.data));
    });
  }

  Future<void> remove(String id) => guarded(() async {
    await _dio.delete('/wishlist/$id');
  });

  Future<void> clear() => guarded(() async {
    await _dio.delete('/wishlist');
  });
}

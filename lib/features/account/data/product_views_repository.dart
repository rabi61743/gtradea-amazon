import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// One product this shopper opened, and when.
class ProductView {
  const ProductView({
    required this.productId,
    required this.title,
    required this.viewedAt,
    this.imageUrl,
    this.priceLabel,
    this.price,
    this.category,
  });

  /// The catalogue id, which is what opens the product page.
  final String productId;

  final String title;
  final DateTime viewedAt;
  final String? imageUrl;

  /// The price as it was shown at the time, which is how this app records it.
  final String? priceLabel;

  /// A numeric price where the server had one.
  final num? price;

  final String? category;

  factory ProductView.fromJson(Map<String, dynamic> json) {
    // The app writes the product under `product_data`; a server that flattens
    // it is read just as well.
    final data = asMap(json['product_data']);
    Object? pick(String key) => data[key] ?? json[key];

    return ProductView(
      productId:
          asString(json['source_product_id']) ??
          asString(json['product_id']) ??
          asString(pick('source_product_id')) ??
          '',
      title: asString(pick('name')) ?? asString(pick('title')) ?? '',
      viewedAt:
          asDate(json['viewed_at']) ??
          asDate(json['created_at']) ??
          asDate(json['updated_at']) ??
          DateTime.now(),
      imageUrl: asString(pick('image_url')) ?? asString(pick('imageUrl')),
      priceLabel: asString(pick('price_label')),
      price: asNum(pick('price')),
      category: asString(pick('category')),
    );
  }
}

/// The shopper's own view history, at `/product-views`.
///
/// The app has posted to this route on every product open since it shipped and
/// never read it back. This is the read side of the history it was already
/// keeping -- not a second one.
///
/// The server scopes the list to the caller's session; there is no id in the
/// path, so there is no route to anybody else's.
class ProductViewsRepository {
  ProductViewsRepository._();

  static final ProductViewsRepository instance = ProductViewsRepository._();

  Dio get _dio => ApiClient.http;

  /// Most recently opened first.
  Future<List<ProductView>> list({int limit = 100}) => guarded(() async {
    final res = await _dio.get(
      '/product-views',
      queryParameters: {'limit': limit},
    );
    final views = asRows(res.data, key: 'views')
        .map(ProductView.fromJson)
        .where((view) => view.productId.isNotEmpty && view.title.isNotEmpty)
        .toList();
    views.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return List.unmodifiable(views);
  });

  /// Forgets one product, by the catalogue id the row was written with.
  Future<void> remove(String productId) => guarded(() async {
    await _dio.delete(
      '/product-views',
      queryParameters: {'source_product_id': productId},
    );
  });

  /// Forgets the lot.
  Future<void> clear() => guarded(() async {
    await _dio.delete('/product-views');
  });
}

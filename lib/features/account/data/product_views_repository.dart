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

/// One answer from `/product-views`.
class ProductViewsPage {
  const ProductViewsPage({
    required this.views,
    required this.received,
    this.hasMore,
  });

  /// The readable rows, newest first.
  final List<ProductView> views;

  /// How many rows the server sent, before unreadable ones were dropped -- the
  /// figure to compare with what was asked for.
  final int received;

  /// The server's own word on whether older rows exist. Null when it did not
  /// say, which is every answer the live route gives today.
  final bool? hasMore;
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

  /// The largest `limit` the route honours. Measured against the live gateway:
  /// anything above 100 is not clamped but silently answered with its default
  /// of 20 rows, which would read as a history that shrank.
  static const maxLimit = 100;

  /// Most recently opened first.
  Future<List<ProductView>> list({int limit = 100}) async =>
      (await page(limit: limit)).views;

  /// The newest [limit] rows, and whether the server says there are more.
  ///
  /// `/product-views` takes a limit and nothing else -- `offset`, `page`,
  /// `cursor` and `before` are all ignored, measured on the live route -- and
  /// answers a bare array with no count. [ProductViewsPage.hasMore] is
  /// therefore null today; it is read from `has_more` / `hasMore` the day the
  /// server wraps its answer and says so itself.
  Future<ProductViewsPage> page({required int limit}) => guarded(() async {
    final res = await _dio.get(
      '/product-views',
      queryParameters: {'limit': limit.clamp(1, maxLimit)},
    );
    final body = res.data;
    final views = asRows(body, key: 'views')
        .map(ProductView.fromJson)
        .where((view) => view.productId.isNotEmpty && view.title.isNotEmpty)
        .toList();
    views.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    final meta = asMap(body);
    final more = meta['has_more'] ?? meta['hasMore'];
    return ProductViewsPage(
      views: List.unmodifiable(views),
      received: asRows(body, key: 'views').length,
      hasMore: more == null ? null : asBool(more),
    );
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

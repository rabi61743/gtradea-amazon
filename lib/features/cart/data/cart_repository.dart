import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// A cart row as the server holds it.
class ServerCartItem {
  const ServerCartItem({
    required this.id,
    required this.quantity,
    this.productId,
    this.sourceProductId,
    this.source = 'local',
    this.variantLabel,
    this.productData = const {},
  });

  /// The server row id. Every update and delete addresses this, not the
  /// product -- two rows can hold the same product in different variants.
  final String id;

  final int quantity;
  final String? productId;

  /// The catalogue key for an imported product. Which of this and [productId]
  /// is set depends on where the product came from.
  final String? sourceProductId;

  final String source;
  final String? variantLabel;

  /// The snapshot taken when the line was added: name, price, image. The
  /// server stores it verbatim so a cart still renders after the upstream
  /// listing changes or disappears.
  final Map<String, dynamic> productData;

  /// The catalogue key this row is for, whichever column it landed in.
  String get key => sourceProductId ?? productId ?? id;

  factory ServerCartItem.fromJson(Map<String, dynamic> json) {
    // A local catalogue row carries its fields in a joined `product` object
    // instead of `product_data`. Only one is ever populated.
    final data = asMap(json['product_data']).isNotEmpty
        ? asMap(json['product_data'])
        : asMap(json['product']);

    return ServerCartItem(
      id: asString(json['id']) ?? '',
      quantity: asInt(json['quantity']) ?? 1,
      productId: asString(json['product_id']),
      sourceProductId: asString(json['source_product_id']),
      source: asString(json['source']) ?? 'local',
      variantLabel:
          asString(json['variant_label']) ?? asString(data['variantLabel']),
      productData: data,
    );
  }
}

/// What `GET /cart` answers.
class ServerCart {
  const ServerCart({this.items = const [], this.subtotal = 0});

  final List<ServerCartItem> items;

  /// The server's own subtotal. Read but not trusted as the figure to charge:
  /// the totals the shopper sees are built from the lines, and if the two ever
  /// disagree that is worth knowing rather than papering over.
  final num subtotal;

  factory ServerCart.fromJson(Map<String, dynamic> json) => ServerCart(
    items: asRows(json['items'])
        .map(ServerCartItem.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false),
    subtotal: asNum(json['subtotal']) ?? 0,
  );
}

/// The signed-in shopper's cart, on the server.
///
/// Every call needs a session; the interceptor attaches it. A guest has no
/// server cart at all, which is why [CartStore] keeps a local one.
class CartRepository {
  CartRepository._();

  static final CartRepository instance = CartRepository._();

  Dio get _dio => ApiClient.http;

  Future<ServerCart> list() => guarded(() async {
    final res = await _dio.get('/cart');
    return ServerCart.fromJson(asMap(res.data));
  });

  /// Adds a line and returns the row the server created.
  Future<ServerCartItem> add({
    required int quantity,
    required String source,
    String? sourceProductId,
    String? productId,
    String? variantLabel,
    Map<String, dynamic>? productData,
  }) {
    return guarded(() async {
      final res = await _dio.post(
        '/cart',
        data: {
          'quantity': quantity,
          // Passed explicitly rather than defaulted: the server routes an order
          // differently for an imported product than for a local one, and
          // guessing here would send local products down the import path.
          'source': source,
          'source_product_id': ?sourceProductId,
          'product_id': ?productId,
          'variant_label': ?variantLabel,
          'product_data': ?productData,
        },
      );
      return ServerCartItem.fromJson(asMap(res.data));
    });
  }

  Future<void> setQuantity(String id, int quantity) => guarded(() async {
    await _dio.patch('/cart/$id', data: {'quantity': quantity});
  });

  Future<void> remove(String id) => guarded(() async {
    await _dio.delete('/cart/$id');
  });

  /// Empties the whole cart.
  ///
  /// Deliberately not called after placing an order. An order can be placed for
  /// part of the cart, and clearing everything would destroy the lines the
  /// shopper deliberately left behind.
  Future<void> clear() => guarded(() async {
    await _dio.delete('/cart');
  });
}

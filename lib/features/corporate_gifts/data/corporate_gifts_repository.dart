import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../../catalog/data/product.dart';

/// One page of the Corporate Gifts collection.
class CorporateGiftsPage {
  const CorporateGiftsPage({required this.products, required this.total});

  /// The rows this request asked for, in the order the curator set.
  final List<Product> products;

  /// How many products the whole query matches, not how many are in this page.
  /// It is what says whether there is another page to ask for.
  final int total;
}

/// The Corporate Gifts collection.
///
/// A curated collection the shop maintains -- 131 products at the time of
/// writing -- served by `GET /free-delivery?collection=corporate-gifts`. The
/// endpoint is shared by every product collection and named after the first
/// one it carried; the `collection` parameter is what picks this one out.
///
/// **Searching happens on the server.** Passing `q` narrows the collection and
/// returns a `total` for the narrowed set, so this asks for what it needs
/// rather than downloading the collection and filtering it here. That is the
/// opposite of the Free Delivery page's arrangement, and deliberately: the
/// legacy shape that page reads (no `collection` parameter) ignores every
/// parameter it is sent, while this one honours `q`, `offset` and `limit`.
///
/// Rows arrive flat -- title, image, price, badge, already resolved for the
/// shopfront -- rather than in the `{item, pricing}` envelope the catalogue
/// feed uses.
class CorporateGiftsRepository {
  CorporateGiftsRepository._();

  static final CorporateGiftsRepository instance = CorporateGiftsRepository._();

  Dio get _dio => ApiClient.http;

  /// The collection's slug, as the admin curates it.
  static const slug = 'corporate-gifts';

  /// Rows per request. The storefront's own page size for this endpoint, and
  /// comfortably more than a phone screen shows before the next page is asked
  /// for.
  static const pageSize = 48;

  /// A page of the collection, narrowed to [query] when there is one.
  ///
  /// [cancelToken] is how the screen drops a search the shopper has already
  /// typed past: an abandoned request still holds the connection the current
  /// one needs.
  Future<CorporateGiftsPage> page({
    String query = '',
    int offset = 0,
    int limit = pageSize,
    CancelToken? cancelToken,
  }) {
    final trimmed = query.trim();

    return guarded(() async {
      final res = await _dio.get(
        '/free-delivery',
        queryParameters: {
          'collection': slug,
          'limit': limit,
          if (offset > 0) 'offset': offset,
          // Sent only when there is something to search for. An empty `q`
          // would be a filter that matches nothing on some servers and
          // everything on others; not sending it means the plain collection.
          if (trimmed.isNotEmpty) 'q': trimmed,
        },
        options: guestCall,
        cancelToken: cancelToken,
      );

      final body = asMap(res.data);
      final rows = asRows(body, key: 'items');
      final products = [for (final row in rows) _product(row)]
          .where((p) => p.numIid.isNotEmpty && p.title.isNotEmpty)
          .toList();

      return CorporateGiftsPage(
        products: products,
        // The server's count of the whole match, falling back to what arrived
        // so a missing field cannot make the page ask for more forever.
        total: asInt(body['total']) ?? products.length,
      );
    });
  }

  /// One collection row as a catalogue product.
  ///
  /// `price` is already the shopper's own currency -- the same figure the
  /// storefront prints beside its rupee symbol -- so it goes straight to
  /// `display_price` rather than through the 1688 pricing envelope.
  static Product _product(Map<String, dynamic> row) {
    return Product.fromJson({
      'num_iid': asString(row['num_iid']),
      'title': asString(row['title']),
      'pic_url': asString(row['image_url']),
      'display_price': asNum(row['price']),
    });
  }
}

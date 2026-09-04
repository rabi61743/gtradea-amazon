import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../../catalog/data/product.dart';
import 'free_delivery_search.dart';

/// The products the shop delivers free.
///
/// `GET /free-delivery` is a **curated list of products**, not an order-value
/// rule: 557 of them at the time of writing, each flagged `free_delivery` by
/// whoever maintains the collection. That distinction is the whole reason this
/// exists -- see [FreeDeliveryRepository.threshold] for the other half.
///
/// Rows arrive in the same `{item, pricing}` envelope the product page uses,
/// wrapped in listing fields of their own, so the display price comes from
/// `pricing.displayPrice` rather than the raw 1688 figure on the item.
class FreeDeliveryRepository {
  FreeDeliveryRepository._();

  static final FreeDeliveryRepository instance = FreeDeliveryRepository._();

  Dio get _dio => ApiClient.http;

  /// The order value above which delivery is free, when the shop sets one.
  ///
  /// `site_settings.free_delivery_threshold` exists as a key and is **null**:
  /// no such rule is configured. Read here rather than assumed so the banner
  /// can promise it the day somebody sets it, and say something true until
  /// then -- delivery is quoted per order from weight, volume and destination,
  /// and a headline figure the checkout then contradicts is worse than no
  /// figure at all.
  Future<num?> threshold() => guarded(() async {
    final res = await _dio.get(
      '/site-settings/free_delivery_threshold',
      options: guestCall,
    );
    return asNum(asMap(res.data)['setting_value']);
  });

  /// The free-delivery collection, newest first as the server orders it.
  Future<List<Product>> products({int limit = 40}) async {
    final rows = await listings(limit: limit);
    return [for (final row in rows) row.product];
  }

  /// The same collection, with the fields a search needs.
  ///
  /// The category a listing was filed under and its brand are not part of a
  /// product card, so they are not on [Product] -- but they are the two things
  /// besides the title worth finding a product by. See [FreeDeliveryIndex].
  ///
  /// A note on `limit`: the endpoint ignores it, along with every other
  /// parameter it is sent, and answers with the whole collection. It is still
  /// passed, so that the day the server starts honouring it this asks for what
  /// it wants rather than silently relying on being given everything.
  Future<List<FreeDeliveryListing>> listings({int limit = 40}) =>
      guarded(() async {
        final res = await _dio.get(
          '/free-delivery',
          queryParameters: {'limit': limit},
          options: guestCall,
        );
        return asRows(res.data)
            .map(_listing)
            .where(
              (row) =>
                  row.product.numIid.isNotEmpty && row.product.title.isNotEmpty,
            )
            .toList(growable: false);
      });

  /// One listing row as a catalogue product.
  ///
  /// The curator can rename a listing for the shopfront -- `custom_name` beside
  /// a `use_custom_name` flag -- and where they have, that name is the one to
  /// show: the seller's own title is written for a wholesale index and runs to
  /// a paragraph.
  static FreeDeliveryListing _listing(Map<String, dynamic> row) {
    final data = asMap(row['product_data']);
    final item = asMap(data['item']);
    final pricing = asMap(data['pricing']);

    final custom = asString(row['custom_name']);
    final useCustom = asBool(row['use_custom_name']) && custom != null;

    return FreeDeliveryListing(
      category: asString(item['category_name']),
      brand: asString(item['brand']),
      product: Product.fromJson({
        'num_iid': asString(item['num_iid']) ?? asString(row['num_iid']),
        'title': useCustom ? custom : asString(item['title']),
        'pic_url': asString(item['pic_url']),
        // The shopper's currency, not the raw 1688 price on the item.
        'display_price': asNum(pricing['displayPrice']),
        'sales': item['sales'],
        'min_order': item['min_order'],
      }),
    );
  }
}

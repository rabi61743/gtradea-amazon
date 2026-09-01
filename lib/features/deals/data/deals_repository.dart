import 'dart:developer' as developer;

import '../../catalog/data/catalog_repository.dart';
import '../../flash_sale/data/deal_pricing.dart';
import '../../flash_sale/data/flash_sale.dart';

/// One page of deals, and what the caller needs to ask for the next one.
class DealsPage {
  const DealsPage({
    required this.items,
    required this.hasMore,
    required this.rowsConsumed,
    this.filterCutShort = false,
  });

  final List<FlashSaleItem> items;

  /// Whether the catalogue had more rows after this page.
  final bool hasMore;

  /// How many raw catalogue rows were read to produce [items].
  ///
  /// Not the same as `items.length` once a discount filter is on, and this is
  /// the number the next `offset` has to advance by -- paging by the filtered
  /// count would re-read the rows the filter dropped, forever.
  final int rowsConsumed;

  /// True when the fetch stopped on its round-trip budget rather than on the
  /// end of the catalogue. The page is short but there is more out there.
  final bool filterCutShort;
}

/// Products presented as deals.
///
/// There is no deals endpoint -- `/deals`, `/offers` and `/promotions` all 404,
/// and `/search/products` silently ignores `on_sale`, `has_discount` and
/// `discounted` (all three return the same rows). So a "deal" here is an
/// ordinary catalogue row priced through [dealPricing], and the discount filter
/// is applied on this side.
///
/// See `docs/flash-sales-api.md` for the endpoint this would rather be reading.
class DealsRepository {
  DealsRepository._();

  static final DealsRepository instance = DealsRepository._();

  /// How many catalogue rows to pull per round trip while filling a page.
  static const _fetchSize = 24;

  /// How many round trips one page may take.
  ///
  /// The discount filter runs here, not on the server, so a narrow band can
  /// reject most of what comes back. Without a ceiling, "50% and over" against
  /// a catalogue that happens to have few would spin through the entire
  /// catalogue on one scroll tick.
  static const _maxRoundTrips = 4;

  /// A page of deals, filled past whatever the discount filter rejects.
  Future<DealsPage> page({
    String query = '',
    String? categoryCid,
    num? minPrice,
    num? maxPrice,
    int minDiscount = 0,
    ProductSort sort = ProductSort.sales,
    int pageSize = 24,
    int offset = 0,
  }) async {
    // Never below 1. The catalogue is full of "price on request" rows, and
    // `sort=price_asc` puts every one of them first -- hundreds of nulls before
    // the first real price. They are all dropped below as unpriced, so without
    // this floor the cheapest-first sort spends its whole round-trip budget on
    // rows it cannot use and reports an empty page. `min_price` is a filter the
    // server genuinely applies, so this costs nothing and is not a guess.
    final floor = (minPrice == null || minPrice < 1) ? 1 : minPrice;

    final items = <FlashSaleItem>[];
    var consumed = 0;
    var trips = 0;
    var exhausted = false;

    while (items.length < pageSize && trips < _maxRoundTrips && !exhausted) {
      trips++;
      final products = await CatalogRepository.instance.search(
        query: query,
        categoryCid: categoryCid,
        minPrice: floor,
        maxPrice: maxPrice,
        sort: sort,
        pageSize: _fetchSize,
        offset: offset + consumed,
      );

      // A short answer is the end of the catalogue, and the only reliable
      // signal of it -- there is no total count in the response.
      exhausted = products.length < _fetchSize;
      consumed += products.length;

      for (final product in products) {
        // "Price on request" rows exist in this feed. A deal card for one would
        // advertise a discount off nothing.
        if (!product.hasPrice) continue;
        final item = dealPricing(product);
        if (item.discountPercent < minDiscount) continue;
        items.add(item);
      }
    }

    final cutShort =
        items.length < pageSize && !exhausted && trips >= _maxRoundTrips;

    if (cutShort) {
      // Said out loud rather than swallowed: a page that stops here looks
      // identical to the end of the catalogue, and the two mean opposite
      // things to whoever is reading the screen.
      developer.log(
        'deals: stopped after $trips fetches with ${items.length}/$pageSize '
        'items at $minDiscount%+; more may exist',
        name: 'deals',
      );
    }

    return DealsPage(
      items: items,
      hasMore: !exhausted,
      rowsConsumed: consumed,
      filterCutShort: cutShort,
    );
  }
}

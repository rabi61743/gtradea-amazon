import 'package:flutter/material.dart';

import '../../../core/network/json.dart';
import '../../catalog/data/product.dart';
import '../../home/widgets/product_rail.dart';

/// A selectable variant, e.g. a colourway.
class ProductVariant {
  const ProductVariant({
    required this.label,
    required this.imageUrl,
    this.inStock = true,
    this.skuId,
    this.specId,
    this.price,
  });

  final String label;
  final String imageUrl;

  /// The SKU this option buys. Sent with the cart line, because the order the
  /// server places upstream is against a SKU, not against a colour name.
  final String? skuId;

  /// The spec hash order creation needs alongside the SKU id.
  final String? specId;

  /// This option's own price, when the seller prices options differently.
  final num? price;

  /// Out-of-stock variants stay visible but unselectable. Hiding them makes a
  /// shopper think the option never existed and hunt for it elsewhere.
  final bool inStock;
}

/// One row of the specification table.
class ProductSpec {
  const ProductSpec(this.label, this.value);
  final String label;
  final String value;
}

/// A named guarantee, e.g. returns or payment on delivery.
class Assurance {
  const Assurance({
    required this.label,
    required this.icon,
    required this.detail,
  });

  final String label;
  final IconData icon;

  /// What the guarantee actually means, in a sentence. The reference shows
  /// these as chevrons; a promise the shopper cannot read is not a promise.
  final String detail;
}

/// One review, as written.
class ProductReview {
  const ProductReview({
    required this.author,
    required this.rating,
    required this.when,
    required this.body,
    this.verified = true,
  });

  final String author;
  final double rating;
  final String when;
  final String body;
  final bool verified;
}

/// Ratings in aggregate.
///
/// Carries the whole distribution, not just the mean: a 4.3 built from steady
/// fours reads very differently from one built of fives and ones, and the
/// average alone hides which it is.
class RatingSummary {
  const RatingSummary({
    required this.average,
    required this.total,
    required this.distribution,
    required this.verifiedShare,
  });

  final double average;
  final int total;

  /// Counts for five stars down to one, in that order.
  final List<int> distribution;

  /// Share of ratings from confirmed purchases, 0 to 1.
  final double verifiedShare;

  int get verifiedCount => (total * verifiedShare).round();

  /// Plain-language read of the average, so the number is not the only cue.
  String get verdict {
    if (average >= 4.5) return 'Excellent';
    if (average >= 4.0) return 'Very good';
    if (average >= 3.0) return 'Mixed';
    return 'Poor';
  }
}

/// Everything the detail page shows about one product.
///
/// A view model built from `GET /api/1688/product`, not a copy of it: the
/// response carries a CNY price ladder, referral URLs and raw markup that the
/// page has no business rendering.
class ProductDetail {
  const ProductDetail({
    required this.numIid,
    required this.title,
    required this.price,
    required this.rating,
    required this.reviewCount,
    required this.images,
    required this.variants,
    required this.specs,
    required this.description,
    this.listPrice,
    this.minOrder = 1,
    this.category,
    this.categoryCid,
    this.soldCount,
    this.freeDelivery = false,
    this.unitLabel = 'pcs',
    this.sellerName,
    this.location,
    this.tiers = const [],
    this.highlights = const [],
    this.assurances = const [],
    this.reviews = const [],
    this.similar = const [],
    this.ratingSummary,
    this.isPreview = false,
  });

  /// The catalogue key, and what every cart and order line refers to.
  final String numIid;

  final String title;
  final num price;

  /// Struck-through "was" price.
  ///
  /// Always null against this catalogue, and deliberately so: the server
  /// publishes one price per product, and a crossed-out number derived from a
  /// markup nobody publishes is an invented discount.
  final num? listPrice;

  final double rating;
  final int reviewCount;
  final List<String> images;
  final List<ProductVariant> variants;
  final List<ProductSpec> specs;
  final String description;
  final int minOrder;

  /// Which department this belongs to. Carried onto the cart line so a
  /// category-restricted coupon knows whether it applies.
  final String? category;
  final String? categoryCid;

  final int? soldCount;
  final bool freeDelivery;

  /// What one unit is called: pieces, sets, metres. Wholesale rows are not
  /// always sold by the piece, and "2 sets" is not "2 pieces".
  final String unitLabel;

  final String? sellerName;
  final String? location;

  /// The bulk-price ladder, cheapest rung last. Empty for most products.
  final List<QuantityTier> tiers;

  /// The handful of facts a shopper checks before anything else. Separate from
  /// [specs], which is the exhaustive table.
  final List<ProductSpec> highlights;

  final List<Assurance> assurances;
  final List<ProductReview> reviews;
  final List<ProductItem> similar;
  final RatingSummary? ratingSummary;

  /// True while this is the card's own data standing in for the full record.
  /// The page renders it immediately and swaps when the detail lands.
  final bool isPreview;

  /// Whole-percent saving, or null when there is nothing honest to claim.
  int? get discountPercent {
    final list = listPrice;
    if (list == null || list <= price) return null;
    return (((list - price) / list) * 100).round();
  }

  /// VAT already inside the shown price, back-solved at 13% the way both
  /// GtradeA storefronts do it. Null when it rounds away to nothing.
  int? get vatIncluded {
    if (price <= 0) return null;
    final derived = (price * 13 / 113).round();
    return derived > 0 ? derived : null;
  }

  /// The unit price at a given quantity, stepping down the bulk ladder.
  num priceAt(int quantity) {
    var best = price;
    for (final tier in tiers) {
      if (quantity >= tier.minQuantity && tier.price != null) {
        best = tier.price!;
      }
    }
    return best;
  }

  ProductDetail copyWith({List<ProductItem>? similar}) => ProductDetail(
        numIid: numIid,
        title: title,
        price: price,
        rating: rating,
        reviewCount: reviewCount,
        images: images,
        variants: variants,
        specs: specs,
        description: description,
        listPrice: listPrice,
        minOrder: minOrder,
        category: category,
        categoryCid: categoryCid,
        soldCount: soldCount,
        freeDelivery: freeDelivery,
        unitLabel: unitLabel,
        sellerName: sellerName,
        location: location,
        tiers: tiers,
        highlights: highlights,
        assurances: assurances,
        reviews: reviews,
        similar: similar ?? this.similar,
        ratingSummary: ratingSummary,
        isPreview: isPreview,
      );

  /// What the page can draw from the card that was tapped, before the detail
  /// request has answered.
  ///
  /// Worth doing because the sourcing service is slow: the title, price and
  /// photograph are already on screen in the rail, and re-showing them beats a
  /// blank page for a second and a half.
  factory ProductDetail.fromProduct(Product product) => ProductDetail(
        numIid: product.numIid,
        title: product.title,
        price: product.displayPrice ?? 0,
        rating: product.rating ?? 0,
        reviewCount: 0,
        images: product.imageUrl == null ? const [] : [product.imageUrl!],
        variants: const [],
        specs: const [],
        description: '',
        minOrder: product.minOrder,
        category: product.categoryName,
        categoryCid: product.categoryCid,
        soldCount: product.sales,
        assurances: storeAssurances,
        isPreview: true,
      );

  /// The full record.
  ///
  /// [fallback] is the card that opened the page: the sourcing service
  /// occasionally answers without a price, and the figure the shopper just saw
  /// in the rail is a better answer than zero.
  factory ProductDetail.fromApi(
    Map<String, dynamic> response, {
    Product? fallback,
  }) {
    final item = asMap(response['item']);
    final pricing = asMap(response['pricing']);

    final images = <String>[];
    final lead = asString(item['pic_url']);
    if (lead != null) images.add(lead);
    final rawImages = item['images'];
    if (rawImages is List) {
      for (final url in rawImages) {
        final s = asString(url);
        if (s != null && !images.contains(s)) images.add(s);
      }
    }
    if (images.isEmpty && fallback?.imageUrl != null) {
      images.add(fallback!.imageUrl!);
    }

    final skus = _skus(item);
    final variants = _variants(skus, pricing);
    final specs = _specs(item);
    final tiers = _tiers(pricing);

    final moq = asInt(item['min_order_quantity']) ?? fallback?.minOrder ?? 1;
    final blurb = asString(item['desc_short']) ?? asString(item['description']);

    final seller = asMap(item['seller_info']);

    return ProductDetail(
      numIid: asString(item['num_iid']) ?? fallback?.numIid ?? '',
      title: asString(item['title']) ?? fallback?.title ?? '',
      price: asNum(pricing['displayPrice']) ?? fallback?.displayPrice ?? 0,
      // No reviews exist for this catalogue. Showing a zero-star summary would
      // read as "rated badly" rather than "not rated yet", so the page hides
      // the whole section instead.
      rating: 0,
      reviewCount: 0,
      images: images,
      variants: variants,
      specs: specs,
      description: blurb == null ? '' : stripHtml(blurb),
      minOrder: moq > 0 ? moq : 1,
      category: asString(item['category_name']) ?? fallback?.categoryName,
      categoryCid: asString(item['category_id']) ?? fallback?.categoryCid,
      soldCount: asInt(item['total_sold']) ?? fallback?.sales,
      unitLabel: _unit(asString(item['sell_unit']) ?? asString(item['unit'])),
      sellerName: asString(seller['shop_name']) ??
          asString(seller['nick']) ??
          asString(item['seller_nick']),
      location: asString(item['location']),
      tiers: tiers,
      // The first few rows of the spec table, which is what a shopper scans
      // before reading anything else.
      highlights: specs.take(6).toList(growable: false),
      assurances: storeAssurances,
      );
  }
}

/// One purchasable combination.
List<_Sku> _skus(Map<String, dynamic> item) {
  final raw = item['skus'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((s) {
    final sku = s.cast<String, dynamic>();
    final parts = sku['variant_parts'];
    return _Sku(
      skuId: asString(sku['sku_id']) ?? '',
      specId: asString(sku['spec_id']),
      quantity: asInt(sku['quantity']),
      imageUrl: asString(sku['image_url']),
      values: parts is! List
          ? const []
          : parts
              .whereType<Map>()
              .map((p) => asString(p['value']))
              .whereType<String>()
              .toList(growable: false),
    );
  }).where((s) => s.skuId.isNotEmpty && s.values.isNotEmpty).toList();
}

class _Sku {
  const _Sku({
    required this.skuId,
    required this.values,
    this.specId,
    this.quantity,
    this.imageUrl,
  });

  final String skuId;
  final String? specId;
  final int? quantity;
  final String? imageUrl;
  final List<String> values;
}

/// Flattens the SKUs into the selectable list the picker shows.
///
/// One entry per buyable combination rather than one per axis. A wholesale
/// offer can carry colour and size on separate axes where only some pairs
/// exist, and a two-axis picker would happily offer a pair that does not --
/// which is a checkout failure rather than a display bug.
List<ProductVariant> _variants(List<_Sku> skus, Map<String, dynamic> pricing) {
  if (skus.isEmpty) return const [];
  final prices = asMap(pricing['skuPrices']);

  return skus.map((sku) {
    final raw = prices[sku.skuId];
    final price = raw is Map ? asNum(raw['displayPrice']) : asNum(raw);
    return ProductVariant(
      label: sku.values.join(' / '),
      imageUrl: sku.imageUrl ?? '',
      // Null stock means the seller did not say, which is not the same as none.
      inStock: sku.quantity == null || sku.quantity! > 0,
      skuId: sku.skuId,
      specId: sku.specId,
      price: price,
    );
  }).toList(growable: false);
}

List<ProductSpec> _specs(Map<String, dynamic> item) {
  final raw = item['props'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((p) => (asString(p['name']), asString(p['value'])))
      .where((p) => p.$1 != null && p.$2 != null)
      .map((p) => ProductSpec(p.$1!, p.$2!))
      .toList(growable: false);
}

/// The bulk ladder in rupees, deduplicated and ascending.
///
/// 1688 sends several rungs sharing one threshold at different prices; keeping
/// them all would show the same quantity twice with two different prices.
List<QuantityTier> _tiers(Map<String, dynamic> pricing) {
  final raw = pricing['quantityTiers'];
  if (raw is! List) return const [];
  final tiers = raw
      .whereType<Map>()
      .map((t) => QuantityTier(
            minQuantity: asInt(t['min_quantity']) ?? 0,
            price: asNum(t['displayPrice']),
          ))
      .where((t) => t.minQuantity > 0 && t.price != null)
      .toList()
    ..sort((a, b) {
      final byQty = a.minQuantity.compareTo(b.minQuantity);
      return byQty != 0 ? byQty : a.price!.compareTo(b.price!);
    });

  final seen = <int>{};
  return tiers.where((t) => seen.add(t.minQuantity)).toList(growable: false);
}

/// A rung of the bulk-price ladder.
class QuantityTier {
  const QuantityTier({required this.minQuantity, this.price});

  final int minQuantity;
  final num? price;
}

/// The sales unit in English.
///
/// The sourcing service translates this upstream; this is the safety net for
/// the occasional offer that comes through untranslated, so a shopper is not
/// shown a Chinese character where a unit should be.
String _unit(String? raw) {
  final u = raw?.trim();
  if (u == null || u.isEmpty) return 'pcs';
  return _unitMap[u] ?? u;
}

const Map<String, String> _unitMap = {
  '件': 'pcs', '个': 'pcs', '只': 'pcs', '枚': 'pcs', '片': 'pcs', '粒': 'pcs',
  '条': 'pcs', '根': 'pcs', '支': 'pcs', '把': 'pcs', '张': 'sheets',
  '双': 'pairs', '对': 'pairs', '套': 'sets', '组': 'sets',
  '包': 'packs', '袋': 'bags', '箱': 'boxes', '盒': 'boxes', '桶': 'barrels',
  '瓶': 'bottles', '罐': 'cans', '管': 'tubes', '卷': 'rolls', '匹': 'rolls',
  '米': 'm', '厘米': 'cm', '毫米': 'mm', '千克': 'kg', '公斤': 'kg', '克': 'g',
  '斤': 'jin (500g)', '吨': 'tons', '升': 'L', '毫升': 'ml',
  '平方米': 'sqm', '立方米': 'cbm',
};

/// What GtradeA promises on every order.
///
/// Storefront policy rather than product data, which is why it is written here
/// and not read from the catalogue: it is the same on every page.
const storeAssurances = [
  Assurance(
    label: '7-day returns',
    icon: Icons.assignment_return_outlined,
    detail: 'Send it back within 7 days of delivery for a full refund, as long '
        'as tags are attached and it is unused.',
  ),
  Assurance(
    label: 'Cash on delivery',
    icon: Icons.payments_outlined,
    detail: 'Pay the courier when it arrives, or pay online with Khalti, '
        'eSewa, ConnectIPS or Fonepay.',
  ),
  Assurance(
    label: 'Quality checked',
    icon: Icons.verified_outlined,
    detail: 'Inspected before dispatch. Anything damaged or mismatched is '
        'replaced at no cost.',
  ),
];

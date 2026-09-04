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
    this.stock,
    this.axisNames = const [],
    this.axisValues = const [],
  });

  final String label;
  final String imageUrl;

  /// The axes this option sits on, and where on each it sits: `['Color',
  /// 'Size']` against `['Wine red', 'M']`.
  ///
  /// Kept apart from [label] rather than derived back out of it. The label is
  /// for reading -- it joins the values with a slash -- and a seller who puts a
  /// slash in a colour name would make that join impossible to undo. These two
  /// are what [VariantMatrix] pivots on, so they have to be the originals.
  final List<String> axisNames;
  final List<String> axisValues;

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

  /// How many the seller says are left, when they said.
  ///
  /// Null is "they did not say", which is not zero -- see [inStock]. Wholesale
  /// listings routinely publish five figures here, so this is worth showing
  /// only when it is small enough to be a constraint on the order.
  final int? stock;
}

/// One axis value down the side of a [VariantMatrix], with its photograph.
class VariantRow {
  const VariantRow({required this.value, required this.imageUrl});

  final String value;

  /// The first picture any SKU in this row carried. Sellers photograph the
  /// colourway, not the colour-and-size, so every cell in a row shares one.
  final String imageUrl;
}

/// A two-axis listing pivoted into a grid: colours down, sizes across.
///
/// Wholesale listings are sold this way -- 21 colours by 4 sizes is 84 SKUs,
/// and the flat picker [VariantPicker] draws asks a buyer to find each of those
/// 84 in a horizontal strip and buy them one at a time. The grid puts every
/// combination on screen at once and lets a quantity be typed into each.
///
/// Null for anything that is not exactly two axes. One axis is a strip and the
/// strip is better at it; three axes do not pivot into a plane at all. Both
/// fall back to the existing picker rather than being forced into a shape they
/// do not have.
class VariantMatrix {
  const VariantMatrix({
    required this.rowLabel,
    required this.columnLabel,
    required this.rows,
    required this.columns,
    required this.cells,
  });

  /// What the seller calls each axis -- "Color", "Size" -- never assumed. A
  /// listing can sell by material and by length, and labelling those two
  /// "Colour" and "Size" would be a lie the grid tells in its own headers.
  final String rowLabel;
  final String columnLabel;

  final List<VariantRow> rows;
  final List<String> columns;

  /// Keyed on the two axis values. Sparse on purpose: a seller who stocks
  /// eight colours but only three of them in XL leaves those cells empty, and
  /// the grid has to draw the hole rather than invent a SKU to fill it.
  final Map<(String, String), ProductVariant> cells;

  ProductVariant? at(String row, String column) => cells[(row, column)];

  bool get isEmpty => rows.isEmpty || columns.isEmpty;

  /// Every SKU the grid can actually sell.
  Iterable<ProductVariant> get buyable => cells.values.where((v) => v.inStock);

  /// True when the SKUs are not all the same price, which is what decides
  /// whether the grid has to show a price per row. Most listings price one
  /// figure across every combination and a column of identical numbers is
  /// noise; some charge more for XL, and hiding that until checkout is worse.
  bool get pricesVary {
    final prices = cells.values.map((v) => v.price).toSet();
    return prices.length > 1;
  }

  /// Pivots [variants], or returns null if they do not form a grid.
  static VariantMatrix? from(List<ProductVariant> variants) {
    if (variants.length < 2) return null;

    // All or nothing. A listing where nine SKUs carry two axes and one carries
    // three is not a grid with a hole in it -- it is a shape this cannot
    // represent, and half-drawing it would misprice the odd one out.
    if (variants.any((v) => v.axisValues.length != 2)) return null;

    final rowOrder = <String>[];
    final rowImages = <String, String>{};
    final columnOrder = <String>[];
    final cells = <(String, String), ProductVariant>{};

    for (final variant in variants) {
      final row = variant.axisValues[0];
      final column = variant.axisValues[1];
      if (row.isEmpty || column.isEmpty) return null;

      if (!rowImages.containsKey(row)) {
        rowOrder.add(row);
        rowImages[row] = variant.imageUrl;
      } else if (rowImages[row]!.isEmpty) {
        rowImages[row] = variant.imageUrl;
      }
      if (!columnOrder.contains(column)) columnOrder.add(column);

      // First wins. A duplicated combination is a feed error, and the
      // alternative -- last wins -- would silently pick a different SKU than
      // the one the price block above is quoting.
      cells.putIfAbsent((row, column), () => variant);
    }

    // A single column is a list wearing a table's clothes, and a single row is
    // a strip. Both are what the picker already does well.
    if (rowOrder.length < 2 && columnOrder.length < 2) return null;

    final names = variants.first.axisNames;
    return VariantMatrix(
      rowLabel: _axisName(names, 0, 'Option'),
      columnLabel: _axisName(names, 1, 'Variant'),
      rows: rowOrder
          .map((value) => VariantRow(value: value, imageUrl: rowImages[value]!))
          .toList(growable: false),
      columns: columnOrder,
      cells: cells,
    );
  }

  static String _axisName(List<String> names, int index, String fallback) {
    final name = index < names.length ? names[index].trim() : '';
    if (name.isEmpty) return fallback;
    // Sellers write these both ways -- "Color" on one listing, "color" on the
    // next -- and a header that is capitalised on one product and not on the
    // next reads as a rendering bug.
    return name[0].toUpperCase() + name.substring(1);
  }
}

/// A column header short enough to be one.
///
/// Sizes arrive from the feed carrying their own fitting guide:
/// `S【 40-50kg 】`, `M【 50.5-57.5kg 】`. Set in full they make a column three
/// times wider than the input box under it, and the part that distinguishes one
/// from another is the first two characters. The full text is not thrown away
/// -- the grid shows it on long press and the cart line carries it -- this is
/// only what fits above the boxes.
String shortVariantLabel(String value) {
  final trimmed = value.trim();
  // Bracketed asides, in both the Latin and the full-width forms the feed
  // mixes within a single listing.
  final cut = trimmed.split(RegExp(r'[【（(\[]')).first.trim();
  if (cut.isEmpty) return trimmed;
  return cut;
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
    this.variantLabel = 'Option',
    this.sellerName,
    this.location,
    this.tiers = const [],
    this.highlights = const [],
    this.assurances = const [],
    this.reviews = const [],
    this.similar = const [],
    this.ratingSummary,
    this.detailImages = const [],
    this.videoUrl,
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

  /// The seller's long-form photography, below the gallery: close-ups, size
  /// charts, fabric shots. Empty for plenty of listings, and drawn only where
  /// it is not -- see [_detailImages] for where these actually come from.
  final List<String> detailImages;

  /// The seller's video, when the listing has one.
  ///
  /// Null is the ordinary case and is what keeps an empty player off the page:
  /// roughly four listings in ten carry one, measured across the discover feed.
  /// The gallery adds a slide only when this is set.
  final String? videoUrl;

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

  /// What the options are: Colour, Size, or several axes at once. Named by the
  /// listing rather than assumed, so a size is never labelled a colour.
  final String variantLabel;

  final String? sellerName;
  final String? location;

  /// The bulk-price ladder, cheapest rung last. Empty for most products.
  final List<QuantityTier> tiers;

  /// The facts a shopper checks before anything else, in the order the seller
  /// filed them.
  ///
  /// The whole list, not a slice of it: how many fit above a "View more" is a
  /// question about the card that draws them, and it used to be answered here
  /// -- which left the card with nothing to reveal. [specs] is still the
  /// exhaustive table the Specifications panel prints.
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
    variantLabel: variantLabel,
    sellerName: sellerName,
    location: location,
    tiers: tiers,
    highlights: highlights,
    assurances: assurances,
    reviews: reviews,
    similar: similar ?? this.similar,
    ratingSummary: ratingSummary,
    // Both media fields carried through. They were not, and while nothing
    // calls this today, a copy that silently drops the seller's photography
    // and video is a bug lying in wait for the first caller.
    detailImages: detailImages,
    videoUrl: videoUrl,
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
    final detailImages = _detailImages(item, images);
    final videoUrl = _videoUrl(item);

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
      detailImages: detailImages,
      videoUrl: videoUrl,
      variants: variants,
      specs: specs,
      description: blurb == null ? '' : stripHtml(blurb),
      minOrder: moq > 0 ? moq : 1,
      category: asString(item['category_name']) ?? fallback?.categoryName,
      categoryCid: asString(item['category_id']) ?? fallback?.categoryCid,
      soldCount: asInt(item['total_sold']) ?? fallback?.sales,
      unitLabel: _unit(asString(item['sell_unit']) ?? asString(item['unit'])),
      variantLabel: _axisLabel(skus),
      sellerName:
          asString(seller['shop_name']) ??
          asString(seller['nick']) ??
          asString(item['seller_nick']),
      location: asString(item['location']),
      tiers: tiers,
      // The same facts the table holds, for the card that shows the first few
      // of them and offers the rest. The card decides how many that is.
      highlights: specs,
      assurances: storeAssurances,
    );
  }
}

/// The seller's long-form photography: the close-ups, the size chart, the
/// fabric shots that sit below the fold on the web storefront.
///
/// Two sources, in order, and both are the server's:
///
///   1. **`desc_images`**, which is the field meant for exactly this. It was
///      measured **empty on every product sampled**, so it cannot be relied on
///      alone -- but it is the right field, and if the service starts filling
///      it this picks it up with no change here.
///   2. **the description HTML**, where the images actually are. One live
///      listing carries 21 of them in `<img src="...">` tags inside the very
///      blurb this page already renders as text, throwing the pictures away.
///
/// Anything already in the main gallery is dropped, so the strip does not
/// repeat the five photographs shown directly above it.
List<String> _detailImages(Map<String, dynamic> item, List<String> gallery) {
  final found = <String>[];

  void take(String? url) {
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http')) return;
    if (gallery.contains(url) || found.contains(url)) return;
    found.add(url);
  }

  final published = item['desc_images'];
  if (published is List) {
    for (final url in published) {
      take(asString(url));
    }
  }
  if (found.isNotEmpty) return found;

  final html = asString(item['description']);
  if (html == null) return const [];
  for (final match in _imgSrc.allMatches(html)) {
    take(match.group(1));
  }
  return found;
}

/// `src="https://…"` in the seller's own markup. Deliberately not an HTML
/// parser: this is one attribute in a blob of vendor markup, and a parser
/// would be a dependency and a new class of failure for one regular
/// expression's worth of work.
final _imgSrc = RegExp(r'''src\s*=\s*["'](https?://[^"']+)["']''');

/// The listing's video, or null.
///
/// Both halves are required. `has_video` is the server saying there is one and
/// `video_url` is where it lives, and a listing carrying the flag without the
/// address is a slide that could only fail -- so the flag alone is not enough.
///
/// The `http` guard is the same one every other URL on this page goes through:
/// the field has been seen holding placeholder text, and a player pointed at
/// something that is not an address fails slowly and with a black rectangle,
/// which is the worst of both.
String? _videoUrl(Map<String, dynamic> item) {
  if (!asBool(item['has_video'])) return null;
  final url = asString(item['video_url']);
  if (url == null || !url.startsWith('http')) return null;
  return url;
}

/// One purchasable combination.
List<_Sku> _skus(Map<String, dynamic> item) {
  final raw = item['skus'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((s) {
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
          names: parts is! List
              ? const []
              : parts
                    .whereType<Map>()
                    .map((p) => asString(p['name']))
                    .whereType<String>()
                    .toList(growable: false),
        );
      })
      .where((s) => s.skuId.isNotEmpty && s.values.isNotEmpty)
      .toList();
}

class _Sku {
  const _Sku({
    required this.skuId,
    required this.values,
    this.specId,
    this.quantity,
    this.imageUrl,
    this.names = const [],
  });

  final String skuId;
  final String? specId;
  final int? quantity;
  final String? imageUrl;
  final List<String> values;

  /// The axis each value belongs to: Colour, Size, Material.
  final List<String> names;
}

/// What to call the row of options.
///
/// Taken from the SKU attributes rather than hard-coded, because these are not
/// always colours -- a listing can sell by size, by material, or by three axes
/// at once, and calling a size "Colour" is worse than saying nothing.
String _axisLabel(List<_Sku> skus) {
  for (final sku in skus) {
    final names = sku.names.where((n) => n.isNotEmpty).toList();
    if (names.isNotEmpty) return names.join(' / ');
  }
  return 'Option';
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

  return skus
      .map((sku) {
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
          stock: sku.quantity,
          axisNames: sku.names,
          axisValues: sku.values,
        );
      })
      .toList(growable: false);
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
  final tiers =
      raw
          .whereType<Map>()
          .map(
            (t) => QuantityTier(
              minQuantity: asInt(t['min_quantity']) ?? 0,
              price: asNum(t['displayPrice']),
            ),
          )
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
  '件': 'pcs',
  '个': 'pcs',
  '只': 'pcs',
  '枚': 'pcs',
  '片': 'pcs',
  '粒': 'pcs',
  '条': 'pcs',
  '根': 'pcs',
  '支': 'pcs',
  '把': 'pcs',
  '张': 'sheets',
  '双': 'pairs',
  '对': 'pairs',
  '套': 'sets',
  '组': 'sets',
  '包': 'packs',
  '袋': 'bags',
  '箱': 'boxes',
  '盒': 'boxes',
  '桶': 'barrels',
  '瓶': 'bottles',
  '罐': 'cans',
  '管': 'tubes',
  '卷': 'rolls',
  '匹': 'rolls',
  '米': 'm',
  '厘米': 'cm',
  '毫米': 'mm',
  '千克': 'kg',
  '公斤': 'kg',
  '克': 'g',
  '斤': 'jin (500g)',
  '吨': 'tons',
  '升': 'L',
  '毫升': 'ml',
  '平方米': 'sqm',
  '立方米': 'cbm',
};

/// What GtradeA promises on every order.
///
/// Storefront policy rather than product data, which is why it is written here
/// and not read from the catalogue: it is the same on every page.
const storeAssurances = [
  Assurance(
    label: '7-day returns',
    icon: Icons.assignment_return_outlined,
    detail:
        'Send it back within 7 days of delivery for a full refund, as long '
        'as tags are attached and it is unused.',
  ),
  Assurance(
    label: 'Cash on delivery',
    icon: Icons.payments_outlined,
    detail:
        'Pay the courier when it arrives, or pay online with Khalti, '
        'eSewa, ConnectIPS or Fonepay.',
  ),
  Assurance(
    label: 'Quality checked',
    icon: Icons.verified_outlined,
    detail:
        'Inspected before dispatch. Anything damaged or mismatched is '
        'replaced at no cost.',
  ),
];

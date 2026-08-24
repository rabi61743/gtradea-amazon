import '../../../core/network/json.dart';

/// A product as the catalogue feed returns it.
///
/// One model for every listing surface -- home rails, category pages, search
/// results -- because they are all the same endpoint family returning the same
/// row. The detail screen has a much larger model of its own.
class Product {
  const Product({
    required this.numIid,
    required this.title,
    this.imageUrl,
    this.displayPrice,
    this.sales,
    this.rating,
    this.categoryCid,
    this.categoryName,
    this.parentCategoryName,
    this.minOrder = 1,
    this.sellerIdentities = const [],
    this.repurchaseRate,
    this.tradeScore,
  });

  /// The catalogue key. Not `id` -- that is a local row number, and the
  /// image-search endpoint returns it as 0 for everything.
  final String numIid;
  final String title;
  final String? imageUrl;

  /// The price in rupees, which is the only price a shopper ever sees.
  ///
  /// Nullable, and genuinely: the feed returns rows whose pricing has not been
  /// worked out yet. Those show as "Price on request" rather than as Rs. 0,
  /// which would be a lie about a real product.
  final num? displayPrice;

  bool get hasPrice => displayPrice != null && displayPrice! > 0;

  /// Units sold. The nearest thing this catalogue has to a popularity signal --
  /// there are no review counts.
  final int? sales;

  /// Almost always null in this catalogue. Kept so a rating is shown the day
  /// the server starts sending one, and nothing is invented in the meantime.
  final double? rating;

  final String? categoryCid;
  final String? categoryName;
  final String? parentCategoryName;

  /// Minimum order quantity. Wholesale rows can require more than one, and the
  /// cart has to respect it.
  final int minOrder;

  /// Seller badges, already filtered to the ones that mean something.
  final List<String> sellerIdentities;

  /// e.g. "58.33%". Shown only when it is a real figure -- the feed sends "0%"
  /// for sellers with no repeat data, and displaying that reads as a warning
  /// about a seller nobody has bought from twice yet.
  final String? repurchaseRate;

  /// The seller's 1688 score out of 5, e.g. "5.0".
  final String? tradeScore;

  factory Product.fromJson(Map<String, dynamic> json) {
    final identities = json['seller_identities'];
    final repurchase = asString(json['repurchase_rate']);
    final moq = asInt(json['min_order']) ?? 1;

    return Product(
      numIid: asString(json['num_iid']) ?? '',
      title: asString(json['title']) ?? '',
      imageUrl: asString(json['pic_url']) ?? asString(json['image_url']),
      displayPrice: asNum(json['display_price']),
      sales: asInt(json['sales']),
      rating: asNum(json['rating'])?.toDouble(),
      categoryCid: asString(json['category_cid']),
      categoryName: asString(json['category_name']),
      parentCategoryName: asString(json['parent_category_name']),
      minOrder: moq > 0 ? moq : 1,
      sellerIdentities: identities is List
          ? identities
              .map(asString)
              .whereType<String>()
              .where(_meaningfulBadges.contains)
              .toList(growable: false)
          : const [],
      repurchaseRate:
          repurchase == null || repurchase.startsWith('0%') ? null : repurchase,
      tradeScore: asString(json['trade_score']),
    );
  }

  /// The badges worth showing. The feed also sends `yx` and a handful of
  /// internal flags that mean nothing to a shopper in Nepal, so they are
  /// dropped rather than rendered as mystery chips.
  static const _meaningfulBadges = {
    'powerful_merchant',
    'powerful_merchants',
    'tp_member',
    'super_factory',
  };

  String? get sellerBadge {
    for (final id in sellerIdentities) {
      switch (id) {
        case 'super_factory':
          return 'Verified factory';
        case 'powerful_merchant':
        case 'powerful_merchants':
          return 'Top seller';
        case 'tp_member':
          return 'Trade assured';
      }
    }
    return null;
  }

  /// A rough popularity line for the card. Exact counts in the tens of
  /// thousands are noise; the order of magnitude is the useful part.
  String? get salesLabel {
    final n = sales;
    if (n == null || n < 50) return null;
    if (n >= 100000) return '${(n / 100000).floor() * 100}k+ sold';
    if (n >= 1000) return '${(n / 1000).floor()}k+ sold';
    return '$n sold';
  }
}

/// Enough of a product to render a card, for the offline-first cache.
///
/// Deliberately not the whole payload: the feed row carries a 500-character
/// referral URL and a relevance score, and writing those to disk on every load
/// would cost far more than it saves.
extension ProductCache on Product {
  Map<String, dynamic> toJson() => {
        'num_iid': numIid,
        'title': title,
        'pic_url': imageUrl,
        'display_price': displayPrice,
        'sales': sales,
        'rating': rating,
        'category_cid': categoryCid,
        'category_name': categoryName,
        'parent_category_name': parentCategoryName,
        'min_order': minOrder,
        'seller_identities': sellerIdentities,
        'repurchase_rate': repurchaseRate,
        'trade_score': tradeScore,
      };
}

/// Round-trips a product list through the cache.
List<Map<String, dynamic>> encodeProducts(List<Product> products) =>
    products.map((p) => p.toJson()).toList(growable: false);

List<Product> decodeProducts(Object json) => json is List
    ? json
        .whereType<Map>()
        .map((m) => Product.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false)
    : const [];

/// The little that a saved or recently-viewed entry remembers, as a catalogue
/// row good enough to open the product page with.
///
/// The page fetches the real record on open; this only has to carry the id and
/// enough to paint the first frame.
Product productStub({
  required String numIid,
  required String title,
  String? imageUrl,
  num? displayPrice,
}) =>
    Product(
      numIid: numIid,
      title: title,
      imageUrl: imageUrl,
      displayPrice: displayPrice,
    );

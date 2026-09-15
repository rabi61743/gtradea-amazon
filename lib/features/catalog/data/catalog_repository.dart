import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import 'product.dart';

/// How a result list is ordered. These are the only values the server parses;
/// anything else is silently ignored, which reads as "the sort did nothing".
enum ProductSort {
  relevance('relevance', 'Relevance'),
  sales('sales', 'Best selling'),
  priceAsc('price_asc', 'Price: low to high'),
  priceDesc('price_desc', 'Price: high to low'),
  newest('newest', 'Newest');

  const ProductSort(this.wire, this.label);

  final String wire;
  final String label;
}

/// A department. The tree is two levels: top-level departments and their
/// children.
class Category {
  const Category({
    required this.cid,
    required this.name,
    this.parentCid,
    this.imageUrl,
    this.isLeaf = false,
    this.sortOrder = 0,
    this.children = const [],
  });

  final String cid;
  final String name;
  final String? parentCid;
  final String? imageUrl;
  final bool isLeaf;
  final int sortOrder;
  final List<Category> children;

  Category withChildren(List<Category> kids) => Category(
    cid: cid,
    name: name,
    parentCid: parentCid,
    imageUrl: imageUrl,
    isLeaf: isLeaf,
    sortOrder: sortOrder,
    children: kids,
  );

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    cid: asString(json['cid']) ?? '',
    name: asString(json['name']) ?? '',
    parentCid: asString(json['parent_cid']),
    imageUrl: asString(json['image_url']),
    isLeaf: asBool(json['is_leaf']),
    sortOrder: asInt(json['sort_order']) ?? 0,
  );
}

/// A merchandising banner set by an admin.
class HeroBanner {
  const HeroBanner({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.buttonText,
    this.buttonLink,
    this.promoCode,
    this.headlinePercent,
    this.promoAmount,
    this.showTextOverlay = true,
    this.validUntil,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? buttonText;
  final String? buttonLink;
  final String? promoCode;

  /// The percentage off this campaign is advertising, and the flat amount off
  /// where it is money rather than a percentage.
  ///
  /// Both are part of the backend's own promotion model and both are null on
  /// every live banner today. They are parsed anyway, so the flash sale shows a
  /// real discount the moment somebody sets one rather than needing a release.
  final int? headlinePercent;
  final num? promoAmount;

  /// Some banners are artwork with the words already in the image. Drawing the
  /// title over those again gives you the headline twice.
  final bool showTextOverlay;

  final DateTime? validUntil;

  bool get isExpired =>
      validUntil != null && validUntil!.isBefore(DateTime.now());

  factory HeroBanner.fromJson(Map<String, dynamic> json) => HeroBanner(
    id: asString(json['id']) ?? '',
    title: asString(json['title']) ?? '',
    subtitle: asString(json['subtitle']),
    imageUrl:
        asString(json['background_image_url']) ??
        asString(json['product_image_url']),
    buttonText: asString(json['button_text']),
    buttonLink: asString(json['button_link']),
    promoCode: asString(json['promo_code']),
    headlinePercent: asInt(json['promo_headline_percent']),
    promoAmount: asNum(json['promo_amount']),
    showTextOverlay: asBool(json['show_text_overlay'], orElse: true),
    validUntil: asDate(json['promo_valid_until']),
  );
}

/// The catalogue.
///
/// Every call here is public: they go out with `skipAuth`, so browsing works
/// signed out and a guest session never carries a credential it has no use for.
class CatalogRepository {
  CatalogRepository._();

  static final CatalogRepository instance = CatalogRepository._();

  Dio get _dio => ApiClient.http;

  /// The main feed. What the home page and the browse tab are built from.
  Future<List<Product>> discover({int pageSize = 20, int offset = 0}) {
    return guarded(() async {
      final res = await _dio.get(
        '/feed/discover',
        queryParameters: {'page_size': pageSize, 'page_offset': offset},
        options: guestCall,
      );
      return _products(res.data);
    });
  }

  /// How deep a random pick is allowed to reach into the discover feed.
  ///
  /// Measured, not guessed: `page_offset=5000` still returns a full page and
  /// `7000` returns nothing, so the feed holds somewhere between five and seven
  /// thousand rows today. Four thousand keeps every draw comfortably inside
  /// that, and [randomPicks] falls back to the top of the feed anyway if a draw
  /// ever comes back empty -- so a catalogue that shrinks makes this section
  /// less varied, never blank.
  static const _randomDepth = 4000;

  /// A handful of products from across the whole catalogue, in no fixed order.
  ///
  /// Built on `/feed/discover`, which is the one endpoint that is not scoped to
  /// a department: a single page of twelve came back carrying twelve different
  /// categories -- tissues, induction cookers, endoscopy, umbrellas. Every
  /// other product endpoint here needs a category or a query, so drawing from
  /// them would be picking a category and calling it random.
  ///
  /// Randomness is a random **offset**, then a shuffle of what comes back. The
  /// offset is what makes two loads different at all; the shuffle only stops
  /// the page from being the server's ordering with a different heading.
  ///
  /// [random] is injectable so the tests can pin the draw. Nothing else passes
  /// it.
  Future<List<Product>> randomPicks({int limit = 12, math.Random? random}) {
    return guarded(() async {
      final dice = random ?? math.Random();
      final offset = dice.nextInt(_randomDepth);

      // Asked for more than are shown, so the shuffle has something to choose
      // between rather than just reordering the exact set that came back.
      var rows = await discover(pageSize: limit * 2, offset: offset);

      // A draw past the end of the feed. Not an error and not worth surfacing:
      // the top of the feed is a perfectly good answer, and the alternative is
      // an empty section for no reason a shopper could understand.
      if (rows.isEmpty) rows = await discover(pageSize: limit * 2);

      final shuffled = [...rows]..shuffle(dice);
      // Short answers are returned as they are. Fewer products than asked for
      // is a smaller rail, which the carousel draws without complaint.
      return shuffled.take(limit).toList(growable: false);
    });
  }

  /// Best sellers inside one department. The rails on the home page are these.
  Future<List<Product>> trending({
    required String categoryCid,
    int limit = 12,
  }) {
    return guarded(() async {
      final res = await _dio.get(
        '/feed/trending-products',
        // Required, not optional -- without it the endpoint answers 400.
        queryParameters: {'category_cid': categoryCid, 'limit': limit},
        options: guestCall,
      );
      return _products(res.data);
    });
  }

  Future<List<Product>> categoryProducts(
    String cid, {
    ProductSort sort = ProductSort.sales,
    int pageSize = 20,
    int offset = 0,
  }) {
    return guarded(() async {
      final res = await _dio.get(
        '/categories/$cid/products',
        queryParameters: {
          'sort': sort.wire,
          // `page_size`, not `limit`. The handler does not parse `limit`, so
          // sending it silently returns the server default instead.
          'page_size': pageSize,
          'page_offset': offset,
        },
        options: guestCall,
      );
      return _products(res.data);
    });
  }

  /// Offers from one **1688** category.
  ///
  /// Not the same id space as [categoryProducts], and that is the whole reason
  /// this exists. A record from `/api/1688/product` carries `category_id` -- a
  /// 1688 leaf category, `122698007` for electric water heaters -- while
  /// `/categories/{cid}/products` indexes the storefront's own cids, the
  /// `1032607` kind. Handing one id to the other endpoint is answered with
  /// `200 []` rather than an error, so the "more like this" rail on any
  /// product opened from search was quietly never drawn.
  ///
  /// A cid the keyword endpoint cannot read is refused here rather than sent
  /// anyway: it drops an unparseable `category_id` and answers with whatever
  /// an empty query returns, and a shelf of unrelated products under "More in
  /// Electric water heater" is worse than no shelf.
  Future<List<Product>> categoryOffers(String cid) {
    if (_numericCid(cid) == null) return Future.value(const []);
    return _keywordSearch('', categoryCid: cid, offset: 0);
  }

  /// Search.
  ///
  /// Two endpoints, because neither one does the whole job and using the wrong
  /// one is what made searching "shoes" return a shoe *box* and a shoe-cabinet
  /// air freshener above any footwear.
  ///
  /// * **`/api/1688/search`** searches the live 1688 catalogue by keyword and
  ///   ranks it properly: "shoes" returns sneakers, "saree" returns sarees,
  ///   "wireless earbuds" returns earbuds. It reads `q`, `page`, `page_size`,
  ///   **`category_id`, `price_min` and `price_max`** -- and genuinely ignores
  ///   `sort`, which is the one control it cannot serve.
  /// * **`/search/products`** is the gateway's *cached* index. It honours the
  ///   same filters under different names and can sort, but it covers a
  ///   fraction of the catalogue, and its ordering ignores its own
  ///   `relevance_score`: rows scoring 0.61 come back above rows scoring 0.83,
  ///   and `sort=relevance` and `sort=sales` return byte-identical lists.
  ///
  /// **The filter names are the whole point of this note, because getting them
  /// wrong was a bug.** This comment used to say the keyword endpoint ignored
  /// category and price "measured, not assumed" -- and it had been measured,
  /// under the gateway's names. The keyword endpoint wants `category_id`,
  /// `price_min` and `price_max`; sending it `category`, `min_price` and
  /// `max_price` does nothing, which is what "ignores them" actually meant.
  ///
  /// The cost was false empties. Believing the keyword endpoint could not
  /// filter, every filtered keyword search went to the cached index instead --
  /// and that index does not contain most of the catalogue. Measured: "geyser",
  /// "saree" and "kurta" each return **fifty** products from the keyword
  /// endpoint and **nothing at all** from the cached one. So a search that had
  /// just found fifty results reported "No results" the moment a price band or
  /// a department was applied to it.
  ///
  /// So: a keyword search stays on the keyword endpoint, filters and all, and
  /// only a **chosen sort** falls back to the cached index -- because sort is
  /// the one thing the keyword endpoint really does ignore, and silently
  /// dropping a control the shopper set is the rule this screen is built on.
  Future<List<Product>> search({
    String query = '',
    String? categoryCid,
    num? minPrice,
    num? maxPrice,
    ProductSort sort = ProductSort.relevance,
    int pageSize = 24,
    int offset = 0,

    /// Abandons the request when the caller no longer wants the answer.
    ///
    /// The typeahead is why this exists. `/api/1688/search` takes between one
    /// and a half and two and a half seconds and answers with about forty
    /// kilobytes, so somebody typing "shoes" had five of those in flight at
    /// once. Dropping the result on arrival -- which a generation counter
    /// already did -- still left them competing for the connection, and on a
    /// phone that is what made the last one, the only one anybody wanted, the
    /// slowest to land.
    CancelToken? cancelToken,
  }) {
    // Trimmed once, here, so a query with stray spaces is the same query
    // whichever endpoint answers it and whichever cache remembers it.
    final q = query.trim();

    // What the keyword endpoint cannot express, it must not be asked to.
    //
    // Sort, always -- it ignores it. And a category whose cid is not numeric:
    // it wants the 1688 cid, so anything else would be dropped on the way out,
    // and a filter that vanishes silently is worse than a slower answer. Those
    // go to the cached index, which can express both.
    final keywordCanServe =
        sort == ProductSort.relevance &&
        (categoryCid == null || _numericCid(categoryCid) != null);

    if (q.isNotEmpty && keywordCanServe) {
      return _keywordSearch(
        q,
        categoryCid: categoryCid,
        minPrice: minPrice,
        maxPrice: maxPrice,
        offset: offset,
        cancelToken: cancelToken,
      );
    }

    return guarded(() async {
      final res = await _dio.get(
        '/search/products',
        queryParameters: {
          if (q.isNotEmpty) 'q': q,
          'category': ?categoryCid,
          'min_price': ?minPrice,
          'max_price': ?maxPrice,
          'sort': sort.wire,
          'page_size': pageSize,
          'page_offset': offset,
        },
        options: guestCall,
      );
      return _products(res.data);
    });
  }

  /// Keyword search against the live catalogue.
  ///
  /// Pages are a fixed fifty and addressed by number, not by offset -- the
  /// endpoint ignores `page_size` entirely, which was measured rather than
  /// assumed. So this returns the page holding [offset] whole, rather than
  /// slicing it down to the caller's [pageSize]: slicing meant asking for
  /// offset 24 re-read page one, and a caller that then advanced by 24 would
  /// walk the same page forever.
  ///
  /// A caller wanting fewer takes fewer. The typeahead does.
  static const keywordPageSize = 50;

  /// The cid if it is all digits, else null.
  static String? _numericCid(String? cid) {
    if (cid == null || cid.isEmpty) return null;
    return RegExp(r'^\d+$').hasMatch(cid) ? cid : null;
  }

  Future<List<Product>> _keywordSearch(
    String query, {
    required int offset,
    String? categoryCid,
    num? minPrice,
    num? maxPrice,
    CancelToken? cancelToken,
  }) {
    return guarded(() async {
      final res = await _dio.get(
        '${Env.apiBaseUrl}/api/1688/search',
        queryParameters: {
          'q': query,
          'page': offset ~/ keywordPageSize + 1,
          'page_size': keywordPageSize,
          // The names this endpoint actually reads. They are not the gateway's
          // -- see the note on [search] -- and getting them wrong is what sent
          // filtered keyword searches to an index that could not answer them.
          //
          // Digits only for the category, which is what the storefront does:
          // the tree also holds uuid-shaped ids, and this endpoint wants the
          // numeric 1688 cid.
          'category_id': ?_numericCid(categoryCid),
          'price_min': ?minPrice,
          'price_max': ?maxPrice,
        },
        options: guestCall,
        cancelToken: cancelToken,
      );

      final rows = asRows(res.data, key: 'items')
          // The field is `min_order_quantity` here and `min_order` on the
          // catalogue feed. Same number, two names, and the cart respects it --
          // so it is normalised on the way in rather than in the model, which
          // would then have to know which endpoint it came from.
          .map(
            (row) => {
              ...row,
              if (row['min_order'] == null && row['min_order_quantity'] != null)
                'min_order': row['min_order_quantity'],
            },
          )
          .map(Product.fromJson)
          .where((p) => p.numIid.isNotEmpty && p.title.isNotEmpty)
          .toList(growable: false);

      return rows;
    });
  }

  /// The whole department tree, in two calls.
  ///
  /// The top level first, then every child of every top-level department at
  /// once. A per-department call would be forty-eight round trips for one
  /// screen.
  ///
  /// The bulk call is not capped: all forty-eight parents in one request
  /// answers with every one of the eleven hundred subcategories. This used to
  /// be wrapped in a bare catch on the belief that it was, which meant a real
  /// failure -- no connection, a 500 -- produced a tree of departments that
  /// each claimed to contain nothing. A shopper cannot tell that apart from an
  /// empty catalogue, so it is no longer swallowed: the error travels up and
  /// the screen offers a retry.
  Future<List<Category>> categoryTree() {
    return guarded(() async {
      final tops = await _categories({'parent_cid': 'null'});
      if (tops.isEmpty) return const <Category>[];

      final kids = await _categories({
        'parent_cids': tops.map((c) => c.cid).join(','),
      });

      final byParent = <String, List<Category>>{};
      for (final kid in kids) {
        final parent = kid.parentCid;
        if (parent != null) {
          byParent.putIfAbsent(parent, () => []).add(kid);
        }
      }

      final tree = tops.map((top) {
        // A copy, and never the const empty list: a handful of departments
        // genuinely have no subcategories, and sorting an unmodifiable list
        // throws.
        final kids = [...?byParent[top.cid]]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return top.withChildren(kids);
      }).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return tree;
    });
  }

  /// One category's own children, fetched on demand.
  ///
  /// [categoryTree] stops at two levels -- the departments and their
  /// subcategories -- because that is what the home page and the browse screen
  /// need and it is already an eleven-hundred-row answer. The tree goes
  /// deeper: "Antenna" has six children of its own, "Capacitor" twelve. This
  /// is how a screen asks for the next level down without pulling the whole
  /// catalogue.
  ///
  /// Sorted the way every other level is, so the order on screen is the order
  /// the storefront chose rather than whatever the database returned.
  ///
  /// An empty list is a real answer: plenty of categories are leaves. The
  /// caller decides what to do about it, and does not have to guess whether it
  /// meant "none" or "failed" -- a failure throws.
  Future<List<Category>> subcategories(String cid) {
    return guarded(() async {
      final kids = await _categories({'parent_cids': cid});
      return kids.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });
  }

  Future<List<Category>> _categories(Map<String, dynamic> query) async {
    final res = await _dio.get(
      '/alibaba-categories',
      queryParameters: query,
      options: guestCall,
    );
    return asRows(res.data)
        .map(Category.fromJson)
        .where((c) => c.cid.isNotEmpty && c.name.isNotEmpty)
        .toList(growable: false);
  }

  /// One request for everyone who asks while it is running.
  ///
  /// Two parts of the home page read the banners at the same moment on a cold
  /// start -- the carousel through [CatalogStore.banners], and the flash sale,
  /// which looks for a live promo among them -- and each used to send its own
  /// `/hero-banners`. They now share whichever request is already in flight.
  /// Once it settles the next call asks again, so nothing is held past the
  /// answer it was waiting for.
  Future<List<HeroBanner>>? _heroBannersInFlight;

  Future<List<HeroBanner>> heroBanners() {
    final pending = _heroBannersInFlight;
    if (pending != null) return pending;

    final request = guarded(() async {
      final res = await _dio.get('/hero-banners', options: guestCall);
      return asRows(res.data)
          .map(HeroBanner.fromJson)
          .where((b) => b.title.isNotEmpty && !b.isExpired)
          .toList(growable: false);
    });
    _heroBannersInFlight = request;
    request
        .whenComplete(() {
          if (identical(_heroBannersInFlight, request)) {
            _heroBannersInFlight = null;
          }
        })
        // The callers await `request` itself and see its error there; this
        // side branch only clears the slot.
        .ignore();
    return request;
  }

  /// The brand names the shop has on file, active ones only.
  ///
  /// `GET /brands` is public and answers 25 rows today -- Adidas, Apple, Dell
  /// and so on, every one `is_active: true`.
  ///
  /// **Nothing in the live catalogue can be filtered by them**, and the filter
  /// sheet says so. They belong to the shop's own products table, which
  /// `GET /products` answers for with an empty array; the catalogue actually
  /// sold from is the 1688 feed, whose rows carry no brand field at all and
  /// whose search endpoint returns byte-identical results with and without a
  /// `brand=` parameter. Both measured.
  ///
  /// Fetched anyway, because the sheet shows the brand control switched off and
  /// the names on it have to be the shop's real ones. A hardcoded list of
  /// plausible brands would be invented data on a page that has none.
  Future<List<String>> brands() {
    return guarded(() async {
      final res = await _dio.get('/brands', options: guestCall);
      return asRows(res.data)
          .where((row) => asBool(row['is_active'], orElse: true))
          .map((row) => asString(row['name']))
          .whereType<String>()
          .toList(growable: false);
    });
  }

  List<Product> _products(Object? data) =>
      asRows(data)
          .map(Product.fromJson)
          .where((p) => p.numIid.isNotEmpty && p.title.isNotEmpty)
          .toList(growable: false);
}

/// Cache round-trips for the department tree, which changes rarely and is worth
/// showing instantly on a cold start.
Map<String, dynamic> _categoryToJson(Category c) => {
  'cid': c.cid,
  'name': c.name,
  'parent_cid': c.parentCid,
  'image_url': c.imageUrl,
  'is_leaf': c.isLeaf,
  'sort_order': c.sortOrder,
  'children': c.children.map(_categoryToJson).toList(growable: false),
};

List<Map<String, dynamic>> encodeCategories(List<Category> categories) =>
    categories.map(_categoryToJson).toList(growable: false);

List<Category> decodeCategories(Object json) {
  if (json is! List) return const [];
  return json
      .whereType<Map>()
      .map((raw) {
        final map = raw.cast<String, dynamic>();
        return Category.fromJson(map).withChildren(
          decodeCategories(
            map['children'] is List ? map['children'] as List : const [],
          ),
        );
      })
      .toList(growable: false);
}

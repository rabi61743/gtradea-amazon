import 'package:dio/dio.dart';

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
        imageUrl: asString(json['background_image_url']) ??
            asString(json['product_image_url']),
        buttonText: asString(json['button_text']),
        buttonLink: asString(json['button_link']),
        promoCode: asString(json['promo_code']),
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

  /// Search.
  ///
  /// Only these filters reach the server. There is deliberately no rating or
  /// on-sale filter: the endpoint ignores both, and a filter that visibly
  /// changes nothing is worse than one that is not offered.
  Future<List<Product>> search({
    String query = '',
    String? categoryCid,
    num? minPrice,
    num? maxPrice,
    ProductSort sort = ProductSort.relevance,
    int pageSize = 24,
    int offset = 0,
  }) {
    return guarded(() async {
      final q = query.trim();
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

  /// The whole department tree, in two calls.
  ///
  /// The top level first, then every child of every top-level department at
  /// once. A per-department call would be twenty round trips for one screen.
  Future<List<Category>> categoryTree() {
    return guarded(() async {
      final tops = await _categories({'parent_cid': 'null'});
      if (tops.isEmpty) return const <Category>[];

      final byParent = <String, List<Category>>{};
      try {
        final kids = await _categories({
          'parent_cids': tops.map((c) => c.cid).join(','),
        });
        for (final kid in kids) {
          final parent = kid.parentCid;
          if (parent != null) {
            byParent.putIfAbsent(parent, () => []).add(kid);
          }
        }
      } on Object {
        // The bulk query is capped server-side and can refuse a long list.
        // Departments with no subcategories still beat an empty screen.
      }

      final tree = tops.map((top) {
        // A copy, and never the const empty list: most departments come back
        // with no children -- the bulk query is capped server-side -- and
        // sorting an unmodifiable list throws.
        final kids = [...?byParent[top.cid]]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return top.withChildren(kids);
      }).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return tree;
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

  Future<List<HeroBanner>> heroBanners() {
    return guarded(() async {
      final res = await _dio.get('/hero-banners', options: guestCall);
      return asRows(res.data)
          .map(HeroBanner.fromJson)
          .where((b) => b.title.isNotEmpty && !b.isExpired)
          .toList(growable: false);
    });
  }

  List<Product> _products(Object? data) => asRows(data)
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
  return json.whereType<Map>().map((raw) {
    final map = raw.cast<String, dynamic>();
    return Category.fromJson(map).withChildren(decodeCategories(
      map['children'] is List ? map['children'] as List : const [],
    ));
  }).toList(growable: false);
}

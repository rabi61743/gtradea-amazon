import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved product, stored flat so the wishlist can render without refetching.
///
/// Denormalised on purpose: a shopper opening their list on a bad connection
/// should see what they saved, not four spinners.
@immutable
class SavedProduct {
  const SavedProduct({
    required this.id,
    required this.title,
    required this.price,
    this.imageUrl,
    this.listPrice,
    this.sellerBadge,
    this.salesLabel,
    this.category,
    this.minOrder = 1,
  });

  final String id;
  final String title;
  final num price;
  final num? listPrice;
  final String? imageUrl;

  /// What the seller is vouched for, in the catalogue's own words. Null when
  /// the listing carries no badge -- most do not.
  final String? sellerBadge;

  /// Units sold, already rounded to an order of magnitude.
  ///
  /// This catalogue publishes no ratings, so this is the only popularity
  /// signal there is. Showing stars here would mean inventing them.
  final String? salesLabel;

  /// Carried so a category-restricted coupon still knows what this is when it
  /// goes into the cart.
  final String? category;

  /// The seller's minimum order. Adding one of a listing that sells in tens
  /// would be refused, so the wishlist adds the minimum.
  final int minOrder;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'price': price,
        'listPrice': listPrice,
        'imageUrl': imageUrl,
        'sellerBadge': sellerBadge,
        'salesLabel': salesLabel,
        'category': category,
        'minOrder': minOrder,
      };

  /// Tolerant: a blob written by an older build may be missing fields, and a
  /// half-readable entry beats dropping the whole list.
  static SavedProduct? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String) return null;
    return SavedProduct(
      id: id,
      title: title,
      price: json['price'] is num ? json['price'] as num : 0,
      listPrice: json['listPrice'] is num ? json['listPrice'] as num : null,
      imageUrl: json['imageUrl'] is String ? json['imageUrl'] as String : null,
      sellerBadge:
          json['sellerBadge'] is String ? json['sellerBadge'] as String : null,
      salesLabel:
          json['salesLabel'] is String ? json['salesLabel'] as String : null,
      category: json['category'] is String ? json['category'] as String : null,
      minOrder: json['minOrder'] is int && (json['minOrder'] as int) >= 1
          ? json['minOrder'] as int
          : 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SavedProduct && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// The wishlist, shared across screens.
///
/// A [ChangeNotifier] singleton rather than a state-management package: this
/// app has no container wired up, and one notifier keeps the heart on a
/// product card, the detail page and the Saved tab showing the same thing.
///
/// Writes are fire-and-forget. A failed write costs persistence across a
/// restart, never the toggle the shopper just made.
class WishlistStore extends ChangeNotifier {
  WishlistStore._();

  static final instance = WishlistStore._();

  static const _key = 'gtradea_wishlist';

  final List<SavedProduct> _items = [];
  bool _loaded = false;

  List<SavedProduct> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isLoaded => _loaded;

  bool contains(String id) => _items.any((item) => item.id == id);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map>()
                  .map((e) => SavedProduct.fromJson(e.cast<String, dynamic>()))
                  .whereType<SavedProduct>(),
            );
        }
      }
    } catch (_) {
      // Unreadable store: start empty rather than blocking the app behind it.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Returns true when the product ends up saved.
  bool toggle(SavedProduct product) {
    final wasSaved = contains(product.id);
    if (wasSaved) {
      _items.removeWhere((item) => item.id == product.id);
    } else {
      // Newest first: the list is a shortlist, and the thing just saved is
      // the thing most likely to be acted on.
      _items.insert(0, product);
    }
    notifyListeners();
    unawaited(_persist());
    return !wasSaved;
  }

  void remove(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
    unawaited(_persist());
  }

  /// Puts a removed product back where it was, for undo.
  ///
  /// Position matters: dropping it back at the top would reorder a shortlist
  /// the shopper built, which is not what undoing a removal means.
  void restore(SavedProduct product, int index) {
    if (contains(product.id)) return;
    _items.insert(index.clamp(0, _items.length), product);
    notifyListeners();
    unawaited(_persist());
  }

  void clear() {
    _items.clear();
    notifyListeners();
    unawaited(_persist());
  }

  /// Test seam: drops in-memory state so each test starts clean.
  @visibleForTesting
  void resetForTest() {
    _items.clear();
    _loaded = false;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(_items.map((item) => item.toJson()).toList()),
      );
    } catch (_) {
      // See the class doc: persistence is best effort.
    }
  }
}


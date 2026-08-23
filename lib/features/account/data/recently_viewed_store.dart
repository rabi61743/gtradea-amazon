import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../wishlist/data/wishlist_store.dart' show SavedProduct;

/// Products the shopper has opened, most recent first.
///
/// Stores [SavedProduct] rather than declaring its own snapshot type: it needs
/// exactly the same flat fields, and a second near-identical class is the kind
/// of duplication that drifts apart the first time one of them gains a field.
///
/// Capped, and deliberately small. This is a way back to something half-looked
/// at, not a browsing history -- an unbounded list would grow forever in
/// SharedPreferences and bury the thing the shopper actually wants.
class RecentlyViewedStore extends ChangeNotifier {
  RecentlyViewedStore._();

  static final instance = RecentlyViewedStore._();

  static const _key = 'gtradea_recently_viewed';

  /// Enough to cover a session of browsing, few enough to stay scannable.
  static const maxEntries = 12;

  final List<SavedProduct> _items = [];
  bool _loaded = false;

  List<SavedProduct> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            final product = SavedProduct.fromJson(entry.cast<String, dynamic>());
            if (product == null) continue;
            if (_items.any((item) => item.id == product.id)) continue;
            _items.add(product);
          }
        }
      }
    } catch (_) {
      // Unreadable history: start empty. Nothing here is worth blocking on.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Records a visit, moving an already-seen product back to the front.
  ///
  /// Re-opening something is a stronger signal than opening it once, so it
  /// moves rather than being ignored or duplicated.
  void record(SavedProduct product) {
    final existingIndex = _items.indexWhere((item) => item.id == product.id);
    if (existingIndex == 0) return; // Already at the front: nothing changes.

    if (existingIndex > 0) _items.removeAt(existingIndex);
    _items.insert(0, product);
    if (_items.length > maxEntries) _items.removeRange(maxEntries, _items.length);

    notifyListeners();
    unawaited(_persist());
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _items.clear();
    _loaded = false;
  }

  Future<void> _persist() {
    final payload = jsonEncode(_items.map((item) => item.toJson()).toList());
    return _write(payload);
  }

  Future<void> _write(String payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, payload);
    } catch (_) {
      // Best effort, like the other stores.
    }
  }
}

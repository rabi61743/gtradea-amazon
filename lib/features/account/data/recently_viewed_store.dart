import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';
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
///
/// One list per account, and one for a guest. What somebody looked at is
/// theirs: with two accounts on a device, each sees only its own.
class RecentlyViewedStore extends ChangeNotifier {
  RecentlyViewedStore._();

  static final instance = RecentlyViewedStore._();

  static const _key = 'gtradea_recently_viewed';

  /// Where [accountId]'s list lives. A guest's is the original key.
  static String storageKeyFor(String? accountId) =>
      (accountId == null || accountId.isEmpty) ? _key : '${_key}_$accountId';

  /// Enough to cover a session of browsing, few enough to stay scannable.
  static const maxEntries = 12;

  final List<SavedProduct> _items = [];
  bool _loaded = false;

  /// The account whose list is held; null for a guest.
  String? _scope;
  bool _bound = false;

  List<SavedProduct> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isLoaded => _loaded;

  /// Follows the active account for the rest of the app's life.
  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    (auth ?? AuthStore.instance).addListener(_onIdentityChanged);
  }

  Future<void> load() async {
    if (_loaded) return;
    _scope = AuthStore.instance.account?.id;
    await _readInto(storageKeyFor(_scope), migrateLegacy: true);
    _loaded = true;
    notifyListeners();
  }

  void _onIdentityChanged() {
    final id = AuthStore.instance.account?.id;
    if (id == _scope && _loaded) return;
    _scope = id;
    _items.clear();
    // Cleared at once, read after: another account's history must not stay
    // on screen for the length of a disk read.
    notifyListeners();
    unawaited(() async {
      // The first account seen after an update may find its history still
      // under the device-wide key, read before sign-in was known. It becomes
      // this account's, once, only if it has none of its own yet.
      await _readInto(storageKeyFor(id), migrateLegacy: true);
      if (_scope != id) return;
      _loaded = true;
      notifyListeners();
    }());
  }

  Future<void> _readInto(String key, {bool migrateLegacy = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(key);
      // Before lists were kept per account there was one, and it was the
      // history of whoever was signed in. It becomes that account's.
      if (migrateLegacy && raw == null && key != _key) {
        raw = prefs.getString(_key);
        if (raw != null) {
          await prefs.setString(key, raw);
          await prefs.remove(_key);
        }
      }
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            final product = SavedProduct.fromJson(
              entry.cast<String, dynamic>(),
            );
            if (product == null) continue;
            if (_items.any((item) => item.id == product.id)) continue;
            _items.add(product);
          }
        }
      }
    } catch (_) {
      // Unreadable history: start empty. Nothing here is worth blocking on.
    }
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
    if (_items.length > maxEntries) {
      _items.removeRange(maxEntries, _items.length);
    }

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
    _scope = null;
  }

  Future<void> _persist() {
    final payload = jsonEncode(_items.map((item) => item.toJson()).toList());
    return _write(storageKeyFor(_scope), payload);
  }

  Future<void> _write(String key, String payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, payload);
    } catch (_) {
      // Best effort, like the other stores.
    }
  }
}

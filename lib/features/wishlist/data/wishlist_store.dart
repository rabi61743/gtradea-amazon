import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/audio/app_sound.dart';
import '../../../core/audio/app_sounds.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../auth/data/auth_store.dart';
import 'wishlist_repository.dart';

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
    this.serverId,
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

  /// The row this is on the server, once it has one.
  ///
  /// Null for a guest's list and for a save that has not reached the account
  /// yet. Removal addresses this id, because the server keys its rows by it.
  final String? serverId;

  SavedProduct copyWith({String? serverId}) => SavedProduct(
    id: id,
    title: title,
    price: price,
    listPrice: listPrice,
    imageUrl: imageUrl,
    sellerBadge: sellerBadge,
    salesLabel: salesLabel,
    category: category,
    minOrder: minOrder,
    serverId: serverId ?? this.serverId,
  );

  /// What the account stores about this product, as the storefront writes it.
  Map<String, dynamic> get snapshot => {
    'name': title,
    'price': price,
    'image': ?imageUrl,
    'source': '1688',
    'category': ?category,
  };

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
    'serverId': serverId,
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
      sellerBadge: json['sellerBadge'] is String
          ? json['sellerBadge'] as String
          : null,
      salesLabel: json['salesLabel'] is String
          ? json['salesLabel'] as String
          : null,
      category: json['category'] is String ? json['category'] as String : null,
      minOrder: json['minOrder'] is int && (json['minOrder'] as int) >= 1
          ? json['minOrder'] as int
          : 1,
      serverId: json['serverId'] is String ? json['serverId'] as String : null,
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

  /// Where [email]'s list lives on the device. A guest's is the original key.
  ///
  /// One list per account: with two accounts on a device, each list is its
  /// own, and the reconcile that follows a sign-in only ever pushes the list
  /// that belongs to the account being signed in to.
  static String storageKeyFor(String? email) =>
      (email == null || email.isEmpty) ? _key : '${_key}_$email';

  /// The account whose list is held; null for a guest.
  String? _scope;
  bool _bound = false;

  /// Bumped on every change of account, so an answer to a request made for
  /// one account is never applied to the next one's list.
  int _epoch = 0;

  /// Follows the active account for the rest of the app's life.
  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    (auth ?? AuthStore.instance).addListener(_onIdentityChanged);
  }

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  /// Swaps to [email]'s list.
  ///
  /// A guest's list is carried into the first account signed in to, as it
  /// always was. One account's list is never carried into another's: the
  /// list switched away from stays on the device under its own key.
  Future<void> _switchTo(String? email) async {
    if (email == _scope && _loaded) return;
    _epoch++;
    final epoch = _epoch;
    final wasGuest = _scope == null || _scope!.isEmpty;
    final carried = wasGuest
        ? List<SavedProduct>.from(_items)
        : const <SavedProduct>[];

    _scope = email;
    _items.clear();
    _removedServerIds.clear();
    _syncError = null;
    _syncing = false;
    // Emptied at once: another account's list must not stay on screen for
    // the length of a disk read.
    notifyListeners();

    final stored = await _readList(storageKeyFor(email));
    if (epoch != _epoch) return;
    _items.addAll(stored);

    if (email != null && carried.isNotEmpty) {
      for (final item in carried) {
        if (!contains(item.id)) _items.add(item);
      }
      unawaited(_removeKey(_key));
    }
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
    if (email != null) unawaited(sync());
  }

  Future<List<SavedProduct>> _readList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => SavedProduct.fromJson(e.cast<String, dynamic>()))
          .whereType<SavedProduct>()
          .toList();
    } catch (_) {
      // Unreadable store: start empty rather than blocking the app behind it.
      return const [];
    }
  }

  Future<void> _removeKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      // Best effort.
    }
  }

  /// Sounded when a product is saved.
  ///
  /// Here rather than on the buttons: every heart in the app -- the product
  /// page, the search results, the rails, the department feed -- saves through
  /// [toggle], so one call covers all of them and none of them can be missed
  /// or get it subtly wrong.
  static AppSound get sound => AppSounds.wishlist;

  final List<SavedProduct> _items = [];
  bool _loaded = false;

  /// True while a reconcile is in flight.
  bool _syncing = false;

  /// Set when the list on screen has not made it to the account.
  ///
  /// Surfaced rather than swallowed, as the cart does: a shopper who saves
  /// three things on a train should not silently find one missing later.
  ApiError? _syncError;

  ApiError? get syncError => _syncError;
  bool get isSyncing => _syncing;

  /// True when this list lives only on the device.
  bool get isGuestList => !AuthStore.instance.isSignedIn;

  List<SavedProduct> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isLoaded => _loaded;

  bool contains(String id) => _items.any((item) => item.id == id);

  /// Reads the device's copy, then reconciles it with the account.
  ///
  /// The local list is what the shopper can see immediately; the server's is
  /// what they left there, possibly on another device. Reconcile rather than a
  /// queue of deltas -- the same reasoning as the cart's, and comparing two
  /// lists cannot save the same product twice.
  Future<void> sync() async {
    await load();
    if (isGuestList || _syncing) return;
    _syncing = true;
    notifyListeners();

    // The account this reconcile is for. After a switch, nothing it learns
    // is applied, and nothing more is pushed: the next account's list is
    // not this one's to fill.
    final epoch = _epoch;
    try {
      final server = await WishlistRepository.instance.list();
      if (epoch != _epoch) return;
      final remaining = {for (final row in server) row.id: row};

      // What this device holds and the account does not.
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        final match = _matchOnServer(item, remaining.values);
        if (match == null) {
          final created = await WishlistRepository.instance.add(
            source: '1688',
            sourceProductId: item.id,
            category: item.category,
            productData: item.snapshot,
          );
          if (epoch != _epoch) return;
          _items[i] = item.copyWith(serverId: created.id);
          continue;
        }
        remaining.remove(match.id);
        if (item.serverId != match.id) {
          _items[i] = item.copyWith(serverId: match.id);
        }
      }

      // And what the account holds that this device has not seen: adopted
      // rather than deleted, because it is the shopper's own list from
      // somewhere else.
      for (final row in remaining.values) {
        _items.add(_fromServer(row));
      }

      _syncError = null;
    } on ApiError catch (e) {
      // The list on screen is still what the shopper saved; it just is not
      // stored yet. Kept, not rolled back.
      _syncError = e;
    } finally {
      _syncing = false;
      notifyListeners();
      unawaited(_persist());
    }
  }

  /// Finds the row that stands for [item], by id first and by product second.
  ServerWishlistItem? _matchOnServer(
    SavedProduct item,
    Iterable<ServerWishlistItem> rows,
  ) {
    for (final row in rows) {
      if (item.serverId != null && row.id == item.serverId) return row;
    }
    for (final row in rows) {
      if (row.key == item.id) return row;
    }
    return null;
  }

  SavedProduct _fromServer(ServerWishlistItem row) => SavedProduct(
    id: row.key,
    title: asString(row.productData['name']) ?? '',
    price: asNum(row.productData['price']) ?? 0,
    imageUrl: asString(row.productData['image']),
    category: row.category,
    serverId: row.id,
  );

  Future<void> load() async {
    if (_loaded) return;
    final email = AuthStore.instance.account?.email;
    _scope = email;
    final epoch = _epoch;
    var stored = await _readList(storageKeyFor(email));

    // Before lists were kept per account there was one, and it was synced to
    // whoever was signed in. It becomes that account's list, once.
    var migrated = false;
    if (stored.isEmpty && email != null && email.isNotEmpty) {
      final legacy = await _readList(_key);
      if (legacy.isNotEmpty) {
        stored = legacy;
        migrated = true;
        unawaited(_removeKey(_key));
      }
    }

    // A switch that landed while this was reading owns the list now.
    if (epoch != _epoch || _loaded) return;

    // Merged, not replaced: something saved before this read finished is
    // what the shopper just did, and the disk copy cannot know about it.
    final pending = _items.isNotEmpty;
    for (final item in stored) {
      if (!contains(item.id)) _items.add(item);
    }
    _loaded = true;
    notifyListeners();
    if (migrated || pending) unawaited(_persist());
  }

  /// Returns true when the product ends up saved.
  bool toggle(SavedProduct product) {
    final wasSaved = contains(product.id);
    if (wasSaved) {
      _items.removeWhere((item) => item.id == product.id);
      unawaited(AppSounds.removed.play());
    } else {
      // Newest first: the list is a shortlist, and the thing just saved is
      // the thing most likely to be acted on.
      _items.insert(0, product);
      // Saving only; the branch above sounds the removal instead.
      //
      // Not awaited, and it cannot throw: the save has already happened by
      // the time this is called, so nothing about the sound can undo it.
      unawaited(AppSounds.wishlist.play());
    }
    notifyListeners();
    unawaited(_persist());
    unawaited(_pushToggle(product, saved: !wasSaved));
    return !wasSaved;
  }

  /// Writes one save or removal to the account.
  ///
  /// Fire and forget, like the local write: a failed call costs the account
  /// copy until the next [sync], never the toggle the shopper just made.
  Future<void> _pushToggle(SavedProduct product, {required bool saved}) async {
    if (isGuestList) return;
    final epoch = _epoch;
    try {
      if (saved) {
        final created = await WishlistRepository.instance.add(
          source: '1688',
          sourceProductId: product.id,
          category: product.category,
          productData: product.snapshot,
        );
        // Saved to the account it was tapped in. If that is no longer the
        // list on screen, its server id means nothing here.
        if (epoch != _epoch) return;
        final at = _items.indexWhere((item) => item.id == product.id);
        if (at >= 0) {
          _items[at] = _items[at].copyWith(serverId: created.id);
          notifyListeners();
          unawaited(_persist());
        }
        return;
      }
      final id = product.serverId;
      if (id != null) await WishlistRepository.instance.remove(id);
    } on ApiError catch (e) {
      _syncError = e;
      notifyListeners();
    }
  }

  /// Takes a product off the list.
  ///
  /// [announce] is false where the removal is not the point of what the
  /// shopper did -- moving a product to the cart takes it off the list, but
  /// the event is the arrival in the cart, and two sounds for one tap is one
  /// too many.
  void remove(String id, {bool announce = true}) {
    final before = _items.length;
    for (final item in _items) {
      if (item.id == id && item.serverId != null) {
        _removedServerIds[id] = item.serverId!;
      }
    }
    _items.removeWhere((item) => item.id == id);
    if (_items.length == before) return;
    if (announce) unawaited(AppSounds.removed.play());
    notifyListeners();
    unawaited(_persist());
    unawaited(_pushRemoval(id));
  }

  Future<void> _pushRemoval(String id) async {
    if (isGuestList) return;
    try {
      final row = _removedServerIds.remove(id);
      if (row != null) await WishlistRepository.instance.remove(row);
    } on ApiError catch (e) {
      _syncError = e;
      notifyListeners();
    }
  }

  /// Puts a removed product back where it was, for undo.
  ///
  /// Position matters: dropping it back at the top would reorder a shortlist
  /// the shopper built, which is not what undoing a removal means.
  ///
  /// Sounded as an undo, not as a save: taking something back is its own
  /// event, and [AppSounds.wishlist] would claim the shopper had just chosen
  /// the product again.
  void restore(SavedProduct product, int index) {
    if (contains(product.id)) return;
    _items.insert(index.clamp(0, _items.length), product);
    unawaited(AppSounds.undo.play());
    notifyListeners();
    unawaited(_persist());
  }

  void clear() {
    _items.clear();
    notifyListeners();
    unawaited(_persist());
  }

  /// Server rows for products already taken off the local list, so the
  /// account can be told about a removal the shopper has already seen happen.
  final Map<String, String> _removedServerIds = {};

  /// Test seam: drops in-memory state so each test starts clean.
  @visibleForTesting
  void resetForTest() {
    _items.clear();
    _removedServerIds.clear();
    _loaded = false;
    _syncError = null;
    _syncing = false;
    _scope = null;
    // Anything still in flight from the last test belongs to nobody now.
    _epoch++;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKeyFor(_scope),
        jsonEncode(_items.map((item) => item.toJson()).toList()),
      );
    } catch (_) {
      // See the class doc: persistence is best effort.
    }
  }
}

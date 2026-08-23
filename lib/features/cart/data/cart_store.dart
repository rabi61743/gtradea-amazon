import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';

/// One line of the cart: a product in a chosen variant, with a quantity.
///
/// Denormalised like SavedProduct: the price, title and photo are snapshotted
/// when the line is added, so the cart renders on a dead connection and so the
/// shopper is charged the price they agreed to rather than one that moved
/// underneath them.
@immutable
class CartLine {
  const CartLine({
    required this.productId,
    required this.title,
    required this.unitPrice,
    this.variantLabel,
    this.listPrice,
    this.imageUrl,
    this.quantity = 1,
    this.minOrder = 1,
    this.freeDelivery = false,
  });

  final String productId;

  /// Null when the product has no options at all. Two colourways of the same
  /// product are two different physical goods, so they are two lines.
  final String? variantLabel;

  final String title;
  final num unitPrice;
  final num? listPrice;
  final String? imageUrl;
  final int quantity;
  final int minOrder;
  final bool freeDelivery;

  /// Identity of a line. Product plus variant, because adding the blush pink
  /// after the ivory must not silently overwrite the ivory.
  ///
  /// Separated by NUL, and never parsed back apart. The product id here is the
  /// product title, which can contain any printable character -- a visible
  /// delimiter like `|` could appear in a title and make two different
  /// products collide onto one line.
  String get key => CartStore.keyOf(productId, variantLabel);

  num get lineTotal => unitPrice * quantity;

  /// Saving on this line, or null when there is nothing honest to claim --
  /// the same rule the product cards and detail page already apply.
  num? get lineSaving {
    final list = listPrice;
    if (list == null || list <= unitPrice) return null;
    return (list - unitPrice) * quantity;
  }

  /// VAT already inside [lineTotal], back-solved at 13%. Never added on top:
  /// the displayed price includes it, and adding it again would double-charge.
  num get vatIncluded => lineTotal * 13 / 113;

  CartLine copyWith({int? quantity}) => CartLine(
        productId: productId,
        variantLabel: variantLabel,
        title: title,
        unitPrice: unitPrice,
        listPrice: listPrice,
        imageUrl: imageUrl,
        quantity: quantity ?? this.quantity,
        minOrder: minOrder,
        freeDelivery: freeDelivery,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'variantLabel': variantLabel,
        'title': title,
        'unitPrice': unitPrice,
        'listPrice': listPrice,
        'imageUrl': imageUrl,
        'quantity': quantity,
        'minOrder': minOrder,
        'freeDelivery': freeDelivery,
      };

  /// Tolerant: a blob written by an older build may be missing fields, and one
  /// half-readable line beats dropping the whole cart.
  static CartLine? fromJson(Map<String, dynamic> json) {
    final id = json['productId'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String) return null;

    final rawMin = json['minOrder'];
    final minOrder = (rawMin is int && rawMin >= 1) ? rawMin : 1;
    final rawQuantity = json['quantity'];
    final quantity = rawQuantity is int ? rawQuantity : minOrder;

    return CartLine(
      productId: id,
      variantLabel: json['variantLabel'] is String
          ? json['variantLabel'] as String
          : null,
      title: title,
      unitPrice: json['unitPrice'] is num ? json['unitPrice'] as num : 0,
      listPrice: json['listPrice'] is num ? json['listPrice'] as num : null,
      imageUrl: json['imageUrl'] is String ? json['imageUrl'] as String : null,
      // Clamped on the way in: a corrupt or hand-edited zero would otherwise
      // become an invisible line that still counted toward the total.
      quantity: quantity.clamp(minOrder, CartStore.maxPerLine),
      minOrder: minOrder,
      freeDelivery: json['freeDelivery'] == true,
    );
  }
}

/// What is owed, computed in one place.
///
/// A value type rather than getters scattered across screens: the cart summary
/// and the checkout summary must never be able to disagree about the total.
@immutable
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.savings,
    required this.delivery,
    required this.vatIncluded,
    required this.itemCount,
    required this.lineCount,
  });

  final num subtotal;

  /// Total struck off against list prices. Zero when nothing is discounted.
  final num savings;

  final num delivery;

  /// Already inside [subtotal]; shown as a note, never added.
  final num vatIncluded;

  /// Units, not lines: three of one jacket is three items.
  final int itemCount;

  final int lineCount;

  num get total => subtotal + delivery;

  bool get isEmpty => lineCount == 0;

  static const empty = CartTotals(
    subtotal: 0,
    savings: 0,
    delivery: 0,
    vatIncluded: 0,
    itemCount: 0,
    lineCount: 0,
  );
}

/// The cart, shared across screens.
///
/// A [ChangeNotifier] singleton like WishlistStore and AuthStore, so the nav
/// badge, the detail page and the cart screen cannot drift apart.
///
/// Carts are scoped to whoever is shopping: a guest cart under one key, and a
/// cart per signed-in account. Signing in merges the guest cart into the
/// account's own, which is what every real storefront does -- filling a cart
/// and then signing in must not throw the cart away.
class CartStore extends ChangeNotifier {
  CartStore._();

  static final instance = CartStore._();

  static const _guestKey = 'gtradea_cart';

  /// Flat fee when anything in the cart is not free-delivery. One figure rather
  /// than per-item shipping: this storefront quotes a single delivery charge
  /// per order, and the detail page already promises free delivery per product.
  static const deliveryFee = 100;

  /// Upper bound per line. Not a stock rule -- a guard against a stuck finger
  /// on the stepper turning into a four-figure order.
  static const maxPerLine = 99;

  final List<CartLine> _lines = [];
  String? _scope;
  bool _loaded = false;
  bool _bound = false;
  Future<void>? _loading;

  List<CartLine> get lines => List.unmodifiable(_lines);

  /// Units in the cart. The badge counts these rather than lines, because a
  /// shopper who added three of something expects the badge to say three.
  int get count => _lines.fold(0, (sum, line) => sum + line.quantity);

  int get lineCount => _lines.length;
  bool get isEmpty => _lines.isEmpty;
  bool get isLoaded => _loaded;

  /// Which storage key the current shopper's cart lives under.
  static String storageKeyFor(String? email) =>
      (email == null || email.isEmpty) ? _guestKey : 'gtradea_cart_$email';

  static String keyOf(String productId, String? variantLabel) =>
      variantLabel == null ? productId : '$productId\u0000$variantLabel';

  bool contains(String productId, [String? variantLabel]) =>
      _lines.any((line) => line.key == keyOf(productId, variantLabel));

  CartLine? lineFor(String productId, [String? variantLabel]) =>
      _lineByKey(keyOf(productId, variantLabel));

  /// Everything owed, derived from the lines. The single source of truth for
  /// money in this app -- the cart screen and the checkout screen both read it
  /// rather than each adding things up their own way.
  CartTotals get totals {
    if (_lines.isEmpty) return CartTotals.empty;

    num subtotal = 0;
    num savings = 0;
    num vat = 0;
    var items = 0;
    var everythingFree = true;

    for (final line in _lines) {
      subtotal += line.lineTotal;
      savings += line.lineSaving ?? 0;
      vat += line.vatIncluded;
      items += line.quantity;
      if (!line.freeDelivery) everythingFree = false;
    }

    return CartTotals(
      subtotal: subtotal,
      savings: savings,
      delivery: everythingFree ? 0 : deliveryFee,
      vatIncluded: vat,
      itemCount: items,
      lineCount: _lines.length,
    );
  }

  /// Follows the signed-in account for the rest of the app's life.
  ///
  /// Bound once at startup rather than called from each sign-in site, so there
  /// is exactly one place that decides what happens to a cart when identity
  /// changes.
  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    (auth ?? AuthStore.instance).addListener(_onIdentityChanged);
  }

  /// Reads the stored cart, merging rather than replacing.
  ///
  /// Three screens call this from initState, and a shopper can add something
  /// before the first read comes back. So the disk copy is folded into what is
  /// already in memory instead of being appended blindly -- appending would
  /// duplicate every line, and replacing would lose the thing just added.
  /// Concurrent callers share one read.
  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _scope = AuthStore.instance.account?.email;

    // Anything already in memory got there by a mutation that raced the read,
    // and its _persist() has already overwritten the stored cart with a partial
    // one. That makes the union authoritative and the disk copy stale.
    final hadPending = _lines.isNotEmpty;

    final stored = <CartLine>[];
    await _readInto(stored, storageKeyFor(_scope));

    // In-memory lines win on a key collision -- they are what the shopper just
    // did. The rest of the stored cart is appended behind them.
    for (final line in stored) {
      if (_lines.any((existing) => existing.key == line.key)) continue;
      _lines.add(line);
    }

    _loaded = true;
    _loading = null;
    notifyListeners();

    if (hadPending) unawaited(_persist());
  }

  /// Switches to the cart belonging to [email], merging a guest cart in.
  ///
  /// Exposed for tests and for [bindToAuth]; app code never calls it directly.
  @visibleForTesting
  Future<void> switchIdentity(String? email) => _switchTo(email);

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  Future<void> _switchTo(String? email) async {
    if (email == _scope) return;

    final wasGuest = _scope == null || _scope!.isEmpty;
    final carried =
        wasGuest ? List<CartLine>.from(_lines) : const <CartLine>[];

    _scope = email;
    _lines.clear();
    await _readInto(_lines, storageKeyFor(email));

    // Signing in with a guest cart: merge rather than replace. Quantities add
    // up for a line already in the account's cart, which is what a shopper who
    // added the same thing on two devices means. Signing out does the reverse
    // of nothing -- the account cart stays on disk under its own key, and the
    // guest cart is whatever was there before.
    if (email != null && carried.isNotEmpty) {
      for (final line in carried) {
        _mergeIn(line);
      }
      unawaited(_clearStored(_guestKey));
      unawaited(_persist());
    }

    _loaded = true;
    notifyListeners();
  }

  /// Adds [line] to the cart, or raises the quantity of a matching line.
  ///
  /// Returns the resulting quantity so the caller can say what actually
  /// happened rather than guessing.
  int add(CartLine line) {
    final resulting = _mergeIn(line);
    notifyListeners();
    unawaited(_persist());
    return resulting;
  }

  int _mergeIn(CartLine line) {
    final index = _lines.indexWhere((existing) => existing.key == line.key);
    if (index == -1) {
      // Newest first: the thing just added is the thing most likely to be
      // adjusted or regretted.
      final clamped = line.quantity.clamp(line.minOrder, maxPerLine);
      _lines.insert(0, line.copyWith(quantity: clamped));
      return clamped;
    }
    final existing = _lines[index];
    final merged =
        (existing.quantity + line.quantity).clamp(existing.minOrder, maxPerLine);
    _lines[index] = existing.copyWith(quantity: merged);
    return merged;
  }

  /// Sets an exact quantity, clamped to the line's floor and [maxPerLine].
  ///
  /// Does not remove at zero: removal is an explicit, undoable action, and a
  /// stepper that deletes the row out from under the finger is how shoppers
  /// lose things by accident.
  void setQuantity(String key, int quantity) {
    final index = _lines.indexWhere((line) => line.key == key);
    if (index == -1) return;
    final line = _lines[index];
    final next = quantity.clamp(line.minOrder, maxPerLine);
    if (next == line.quantity) return;
    _lines[index] = line.copyWith(quantity: next);
    notifyListeners();
    unawaited(_persist());
  }

  void increment(String key) {
    final line = _lineByKey(key);
    if (line != null) setQuantity(key, line.quantity + 1);
  }

  void decrement(String key) {
    final line = _lineByKey(key);
    if (line != null) setQuantity(key, line.quantity - 1);
  }

  void remove(String key) {
    final before = _lines.length;
    _lines.removeWhere((line) => line.key == key);
    if (_lines.length == before) return;
    notifyListeners();
    unawaited(_persist());
  }

  /// Puts a removed line back where it was, for undo.
  void restore(CartLine line, int index) {
    if (_lines.any((existing) => existing.key == line.key)) return;
    _lines.insert(index.clamp(0, _lines.length), line);
    notifyListeners();
    unawaited(_persist());
  }

  int indexOf(String key) => _lines.indexWhere((line) => line.key == key);

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
    unawaited(_persist());
  }

  CartLine? _lineByKey(String key) {
    for (final line in _lines) {
      if (line.key == key) return line;
    }
    return null;
  }

  @visibleForTesting
  void resetForTest() {
    _lines.clear();
    _scope = null;
    _loaded = false;
    _bound = false;
  }

  Future<void> _readInto(List<CartLine> target, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      target.addAll(
        decoded
            .whereType<Map>()
            .map((e) => CartLine.fromJson(e.cast<String, dynamic>()))
            .whereType<CartLine>(),
      );
    } catch (_) {
      // Unreadable cart: start empty rather than blocking the app behind it.
    }
  }

  /// Writes the current cart under the current shopper's key.
  ///
  /// Both the key and the payload are captured synchronously, before the first
  /// await. Reading them afterwards would let a write scheduled for the guest
  /// cart land under an account key that the shopper switched to in between --
  /// silently overwriting that account's cart with someone else's.
  Future<void> _persist() {
    final key = storageKeyFor(_scope);
    final payload = jsonEncode(_lines.map((line) => line.toJson()).toList());
    return _write(key, payload);
  }

  Future<void> _write(String key, String payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, payload);
    } catch (_) {
      // Best effort, like the other stores: a failed write costs persistence
      // across a restart, never the change just made.
    }
  }

  Future<void> _clearStored(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      // See _persist.
    }
  }
}

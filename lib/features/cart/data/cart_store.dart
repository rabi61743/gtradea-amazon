import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/audio/app_sounds.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../auth/data/auth_store.dart';
import '../../logistics/data/shipping_mode_store.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../promo/data/coupon_store.dart';
import '../../product/data/product_detail_content.dart'
    show QuantityTier, quantityTiersFrom, quantityTiersJson, tierPriceAt;
import 'cart_repository.dart';

/// One line of the cart: a product in a chosen variant, with a quantity.
///
/// Denormalised like SavedProduct: the price, title and photo are snapshotted
/// when the line is added, so the cart renders on a dead connection and so the
/// shopper is charged the price they agreed to rather than one that moved
/// underneath them.
///
/// Except where the price is meant to move: a product sold on a quantity
/// ladder carries the ladder with it, and the line's price is the rung its
/// quantity reaches. See [unitPrice].
@immutable
class CartLine {
  const CartLine({
    required this.productId,
    required this.title,
    required num unitPrice,
    this.variantLabel,
    this.listPrice,
    this.imageUrl,
    this.quantity = 1,
    this.minOrder = 1,
    this.freeDelivery = false,
    this.category,
    this.categoryCid,
    this.source = 'local',
    this.skuId,
    this.specId,
    this.serverId,
    this.tiers = const [],
  }) : basePrice = unitPrice;

  final String productId;

  /// Null when the product has no options at all. Two colourways of the same
  /// product are two different physical goods, so they are two lines.
  final String? variantLabel;

  final String title;

  /// The price the line was added at, or last confirmed at by the server.
  /// What [unitPrice] falls back to below the ladder's first rung, and all it
  /// is when there is no ladder.
  final num basePrice;

  /// The product's quantity ladder, from its record. Empty when the price does
  /// not step with quantity: an option the seller prices on its own, or a line
  /// added somewhere that did not carry the ladder.
  final List<QuantityTier> tiers;

  /// What one piece costs at this line's quantity.
  ///
  /// The rung the quantity reaches, read the same way the product page reads
  /// it and the way the server reprices this row: crossing a boundary in the
  /// cart changes the price there and then, not on the next reload.
  num get unitPrice =>
      tiers.isEmpty ? basePrice : tierPriceAt(tiers, basePrice, quantity);

  /// Where the rung being charged starts -- "50+" -- when the product has a
  /// ladder worth naming. Null for a single price.
  int? get appliedTierFrom {
    if (tiers.length < 2) return null;
    int? from;
    for (final tier in tiers) {
      if (quantity >= tier.minQuantity) from = tier.minQuantity;
    }
    return from;
  }

  final num? listPrice;
  final String? imageUrl;
  final int quantity;
  final int minOrder;
  final bool freeDelivery;

  /// What department this came from, so a coupon can be restricted to one.
  /// Null on a line saved before categories existed, which simply means no
  /// category-restricted coupon matches it.
  final String? category;

  /// The catalogue's own id for that category, where the product carried one.
  ///
  /// Kept beside [category] rather than instead of it: the name is what a
  /// coupon rule reads and what a shopper would recognise, and the id is what
  /// the catalogue can actually be queried with. Recommending from a cart line
  /// used to mean matching [category] against the department tree by name, and
  /// most of this catalogue's labels -- "Display rack", "flange" -- are leaves
  /// the tree does not carry, so the match failed silently and the shelf fell
  /// back to a general feed.
  ///
  /// Null for a line added before this existed, or from a source that keeps no
  /// id (the history screens). Those still fall back to the name.
  final String? categoryCid;

  /// Which catalogue the product came from. The server routes an order for an
  /// imported product differently from a local one.
  final String source;

  /// The exact SKU chosen, and the spec hash that goes with it. The order the
  /// server places upstream is against a SKU, not against a colour name.
  final String? skuId;
  final String? specId;

  /// The id of this line's row on the server, once it has one.
  ///
  /// Null for a guest line, and for a line added while offline that has not
  /// been pushed yet -- which is exactly how the sync tells the two apart.
  final String? serverId;

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

  /// The same line with a new quantity -- whose price then follows the ladder
  /// by itself -- or with the price the server confirmed for it.
  CartLine copyWith({
    int? quantity,
    String? serverId,
    num? basePrice,
    List<QuantityTier>? tiers,
  }) => CartLine(
    productId: productId,
    variantLabel: variantLabel,
    title: title,
    unitPrice: basePrice ?? this.basePrice,
    listPrice: listPrice,
    imageUrl: imageUrl,
    quantity: quantity ?? this.quantity,
    minOrder: minOrder,
    freeDelivery: freeDelivery,
    category: category,
    categoryCid: categoryCid,
    source: source,
    skuId: skuId,
    specId: specId,
    serverId: serverId ?? this.serverId,
    tiers: tiers ?? this.tiers,
  );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variantLabel': variantLabel,
    'title': title,
    'unitPrice': basePrice,
    if (tiers.isNotEmpty) 'quantityTiers': quantityTiersJson(tiers),
    'listPrice': listPrice,
    'imageUrl': imageUrl,
    'quantity': quantity,
    'minOrder': minOrder,
    'freeDelivery': freeDelivery,
    'category': category,
    'categoryCid': categoryCid,
    'source': source,
    'skuId': skuId,
    'specId': specId,
    'serverId': serverId,
  };

  /// Tolerant: a blob written by an older build may be missing fields, and one
  /// half-readable line beats dropping the whole cart.
  static CartLine? fromJson(Map<String, dynamic> json) {
    final id = json['productId'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String) return null;

    // Stricter than the wishlist, which defaults a missing price to zero. A
    // saved product can survive rendering Rs. 0; a cart line cannot, because
    // that number is what the shopper is asked to pay. Drop it instead.
    final price = json['unitPrice'];
    if (price is! num || price <= 0) return null;

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
      unitPrice: price,
      listPrice: json['listPrice'] is num ? json['listPrice'] as num : null,
      imageUrl: json['imageUrl'] is String ? json['imageUrl'] as String : null,
      // Clamped on the way in: a corrupt or hand-edited zero would otherwise
      // become an invisible line that still counted toward the total.
      quantity: quantity.clamp(minOrder, CartStore.maxPerLine),
      minOrder: minOrder,
      freeDelivery: json['freeDelivery'] == true,
      category: json['category'] is String ? json['category'] as String : null,
      // Absent from every cart written before this field existed, which is the
      // ordinary case on an upgrade: the line still loads and simply falls
      // back to matching by name.
      categoryCid: json['categoryCid'] is String
          ? json['categoryCid'] as String
          : null,
      source: json['source'] is String ? json['source'] as String : 'local',
      skuId: json['skuId'] is String ? json['skuId'] as String : null,
      specId: json['specId'] is String ? json['specId'] as String : null,
      serverId: json['serverId'] is String ? json['serverId'] as String : null,
      tiers: quantityTiersFrom(json['quantityTiers']),
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
    this.discount = 0,
    this.couponCode,
    this.deliveryQuoted = true,
  });

  final num subtotal;

  /// Total struck off against list prices. Zero when nothing is discounted.
  final num savings;

  final num delivery;

  /// Whether [delivery] is a figure somebody actually quoted.
  ///
  /// False means "not priced yet", which is **not** the same as free, and the
  /// summary must not render it as such. Freight is quoted by the server
  /// against the basket and its destination, so a cart with no address yet has
  /// a delivery of zero that nobody has promised.
  final bool deliveryQuoted;

  /// Taken off by a coupon. Separate from [savings], which is what the shop was
  /// already knocking off the list price -- conflating the two would let one
  /// order claim the same rupee twice.
  final num discount;

  /// The code that produced [discount], for showing on the summary and for
  /// freezing onto the order.
  final String? couponCode;

  /// Already inside what is actually charged; shown as a note, never added.
  final num vatIncluded;

  /// Units, not lines: three of one jacket is three items.
  final int itemCount;

  final int lineCount;

  num get total => subtotal - discount + delivery;

  bool get isEmpty => lineCount == 0;

  static const empty = CartTotals(
    subtotal: 0,
    savings: 0,
    delivery: 0,
    vatIncluded: 0,
    itemCount: 0,
    lineCount: 0,
  );

  /// The one place money is added up.
  ///
  /// A past order passes [delivery] and [discount] so its figures stay whatever
  /// was agreed at the time; changing a rule or expiring a coupon must not
  /// silently rewrite what an old order cost. Everything else derives from the
  /// lines, whose prices were snapshotted when they were added.
  static CartTotals of(
    Iterable<CartLine> lines, {
    num? delivery,
    num discount = 0,
    String? couponCode,
  }) {
    if (lines.isEmpty) {
      return delivery == null || delivery == 0
          ? empty
          : CartTotals(
              subtotal: 0,
              savings: 0,
              delivery: delivery,
              vatIncluded: 0,
              itemCount: 0,
              lineCount: 0,
            );
    }

    num subtotal = 0;
    num savings = 0;
    var items = 0;
    var lineCount = 0;
    var everythingFree = true;

    for (final line in lines) {
      subtotal += line.lineTotal;
      savings += line.lineSaving ?? 0;
      items += line.quantity;
      lineCount++;
      if (!line.freeDelivery) everythingFree = false;
    }

    // A discount can never exceed what is being bought. Guards a stale coupon
    // frozen on an old order as much as a live one.
    final applied = discount.clamp(0, subtotal);

    return CartTotals(
      subtotal: subtotal,
      savings: savings,
      discount: applied,
      couponCode: applied > 0 ? couponCode : null,
      // The server's figure, or nothing at all.
      //
      // There is no client-side fallback on purpose. Delivery here is freight:
      // the server prices it on the weight and volume of what is in the basket
      // and where it is going, and no number this app could substitute would
      // match what checkout goes on to charge. Until the quote lands, the cart
      // shows that it is being worked out rather than a figure that will move.
      delivery:
          delivery ??
          (everythingFree ? 0 : (CartStore.instance.deliveryQuote?.total ?? 0)),
      // Quoted when a past order froze one, when nothing in the basket is
      // chargeable, or when the server has actually answered.
      deliveryQuoted:
          delivery != null ||
          everythingFree ||
          CartStore.instance.deliveryQuote != null,
      // Back-solved from what is actually charged for goods, not from the
      // subtotal: a discount reduces the VAT inside it, and quoting the
      // pre-discount figure would overstate the tax on the receipt.
      vatIncluded: (subtotal - applied) * 13 / 113,
      itemCount: items,
      lineCount: lineCount,
    );
  }
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

  /// The server's delivery quote for what is in the cart right now.
  ///
  /// Null until one has been fetched, or where the storefront has freight
  /// pricing switched off. A null here means the cart says the charge is still
  /// being worked out -- it does not mean zero, and it must never be replaced
  /// by a figure calculated on the device.
  ///
  /// This replaced `static const deliveryFee = 100`, a flat charge added to
  /// every order regardless of what was in it. Two polo shirts to Lalitpur by
  /// air were measured at Rs. 551.18 against that Rs. 100, so the flat figure
  /// understated some orders, overstated others, and matched what checkout
  /// actually charged only by accident.
  DeliveryQuote? get deliveryQuote => _deliveryQuote;
  DeliveryQuote? _deliveryQuote;

  /// True while a quote is in flight, so the cart can say so.
  bool get quotingDelivery => _quoting;
  bool _quoting = false;

  /// Which cart the held quote was for. A quote is only good for the basket it
  /// was asked about, so changing a quantity invalidates it rather than leaving
  /// a stale figure under a different total.
  String? _quotedFor;

  /// A cheap identity for the current basket and destination.
  String _basketKey(String district) => [
    district,
    for (final line in _lines) '${line.productId}:${line.quantity}',
  ].join('|');

  /// Asks the server what delivery costs for this cart.
  ///
  /// Needs a district: freight is priced to a destination, so with no address
  /// chosen there is nothing to ask about and the cart says the charge is set
  /// at checkout rather than inventing one.
  Future<void> refreshDeliveryQuote({required String? district}) async {
    if (district == null || district.trim().isEmpty || _lines.isEmpty) {
      if (_deliveryQuote != null) {
        _deliveryQuote = null;
        _quotedFor = null;
        notifyListeners();
      }
      return;
    }

    final key = _basketKey(district);
    if (key == _quotedFor || _quoting) return;

    _quoting = true;
    notifyListeners();
    try {
      // The checkout repository's own call, not a second one: it already owns
      // this endpoint, already parses the freight VAT out of the breakdown, and
      // already returns null for a storefront with freight pricing switched
      // off. A parallel copy here would be a second answer to one question.
      final quote = await CheckoutRepository.instance.deliveryCharge(
        district: district,
        // What the shopper chose on the product page, so the freight the
        // cart quotes is the freight for the way they asked it to come.
        shippingMode: ShippingModeStore.instance.checkoutMode,
        guestLines: List.unmodifiable(_lines),
      );
      // The basket can change while the request is out; a quote for a cart
      // nobody has any more is worse than none.
      if (_basketKey(district) != key) return;
      _deliveryQuote = quote;
      _quotedFor = quote == null ? null : key;
    } on ApiError {
      // Left as it was. The cart says the charge is worked out at checkout,
      // which is true, rather than showing a number nothing stands behind.
      _deliveryQuote = null;
      _quotedFor = null;
    } finally {
      _quoting = false;
      notifyListeners();
    }
  }

  /// Upper bound per line. Not a stock rule -- a sanity guard, and the same
  /// ceiling the storefront applies.
  ///
  /// It was 99, which made every quantity ladder rung from 100 up unreachable
  /// in the cart -- a wholesale listing priced for 350, 960 or 1,000 pieces
  /// could not be ordered at that price, and a larger quantity chosen on the
  /// product page was cut to 99 without a word. Four figures is a deliberate
  /// wholesale order, not a stuck finger.
  static const maxPerLine = 9999;

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
  /// Everything owed, including whatever coupon is on the basket.
  ///
  /// The coupon is read here rather than passed in so every screen showing a
  /// total gets the same one -- a cart that shows the discount and a badge
  /// that does not would be two answers to one question.
  CartTotals get totals => CartTotals.of(
    _lines,
    discount: CouponStore.instance.discountFor(_lines),
    couponCode: CouponStore.instance.applied?.code,
  );

  /// Follows the signed-in account for the rest of the app's life.
  ///
  /// Bound once at startup rather than called from each sign-in site, so there
  /// is exactly one place that decides what happens to a cart when identity
  /// changes.
  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    final store = auth ?? AuthStore.instance;
    store.addListener(_onIdentityChanged);
    // A change of quantity still inside the debounce belongs to the account
    // it was made in. Sent now, while requests still go out as that account,
    // rather than landing in whichever one is active when the timer fires.
    store.addBeforeAccountChange(() async {
      if (_syncDebounce?.isActive ?? false) await syncNow();
    });
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

    // On a cold start the account wins: what is in it is what the shopper left
    // there, possibly from another device. Anything added on this device in
    // the meantime is pushed by the reconcile that follows.
    if (!isGuestCart) {
      if (hadPending) {
        await _reconcile();
      } else {
        await refreshFromServer();
      }
    }
  }

  /// Switches to the cart belonging to [email], merging a guest cart in.
  ///
  /// Exposed for tests and for [bindToAuth]; app code never calls it directly.
  @visibleForTesting
  Future<void> switchIdentity(String? email) => _switchTo(email);

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  /// Bumped on every change of account.
  ///
  /// A request started for one account can answer after the shopper has
  /// switched to another. Everything that awaits the server notes this first
  /// and drops its answer if it has moved -- otherwise one account's cart
  /// would land in the next one's.
  int _epoch = 0;

  Future<void> _switchTo(String? email) async {
    if (email == _scope) return;
    _epoch++;
    // Nothing owed to the last account is sent as this one.
    _syncDebounce?.cancel();
    _syncDebounce = null;
    _syncing = false;
    _syncError = null;
    _rejected = const {};

    final wasGuest = _scope == null || _scope!.isEmpty;
    final carried = wasGuest ? List<CartLine>.from(_lines) : const <CartLine>[];

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

    if (email != null) {
      // Signing in with things in a guest cart: push them, which the reconcile
      // does by adding every local line the account does not already have.
      // Signing in with an empty one: just take the account's cart.
      if (carried.isNotEmpty) {
        await _reconcile();
      } else {
        await refreshFromServer();
      }
    }
  }

  /// Adds [line] to the cart, or raises the quantity of a matching line.
  ///
  /// Returns the resulting quantity so the caller can say what actually
  /// happened rather than guessing.
  int add(CartLine line) {
    final resulting = _mergeIn(line);
    // The add has already happened. Not awaited and it cannot throw, so
    // nothing about the sound can cost the shopper the line.
    unawaited(AppSounds.addToCart.play());
    notifyListeners();
    unawaited(_persist());
    _scheduleSync();
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
    final merged = (existing.quantity + line.quantity).clamp(
      existing.minOrder,
      maxPerLine,
    );
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
    _scheduleSync();
  }

  void increment(String key) {
    final line = _lineByKey(key);
    if (line != null) setQuantity(key, line.quantity + 1);
  }

  void decrement(String key) {
    final line = _lineByKey(key);
    if (line != null) setQuantity(key, line.quantity - 1);
  }

  /// Swaps a line for the same product in a different variant.
  ///
  /// A colourway is a different physical good, so this is not an edit of a
  /// line -- it is one line out and another in, which is exactly what the
  /// account sees: the old row is deleted and a new one created by the next
  /// reconcile. [serverId] is dropped for that reason; keeping it would have
  /// the sync update the old row in place and the shopper would end up with a
  /// row on the server that says one thing and a line here that says another.
  ///
  /// The quantity and the line's place in the list are kept: the shopper
  /// changed which one they want, not how many or where it sits.
  ///
  /// If the cart already holds the variant being switched to, the two are one
  /// line and the quantities add up -- the same rule [add] follows.
  ///
  /// Returns the resulting line, or null when there was nothing to change.
  CartLine? changeVariant(
    String key, {
    required String? variantLabel,
    String? skuId,
    String? specId,
    num? unitPrice,
    num? listPrice,
    String? imageUrl,
  }) {
    final index = _lines.indexWhere((line) => line.key == key);
    if (index == -1) return null;
    final line = _lines[index];

    final next = CartLine(
      productId: line.productId,
      title: line.title,
      // The variant's own price when the seller prices them apart, and the
      // line's when they do not. A null here would quote nothing.
      unitPrice: unitPrice ?? line.basePrice,
      variantLabel: variantLabel,
      listPrice: listPrice ?? line.listPrice,
      imageUrl: imageUrl ?? line.imageUrl,
      quantity: line.quantity,
      minOrder: line.minOrder,
      freeDelivery: line.freeDelivery,
      category: line.category,
      source: line.source,
      skuId: skuId,
      specId: specId,
      // An option with a price of its own is off the ladder; one priced from
      // the listing stays on it.
      tiers: unitPrice == null ? line.tiers : const [],
    );

    if (next.key == line.key &&
        next.unitPrice == line.unitPrice &&
        next.skuId == line.skuId &&
        next.imageUrl == line.imageUrl) {
      return null;
    }

    if (next.key == line.key) {
      // The same variant with fresher figures: the row on the server still
      // stands for it, so its id is kept.
      _lines[index] = CartLine(
        productId: next.productId,
        title: next.title,
        unitPrice: next.unitPrice,
        variantLabel: next.variantLabel,
        listPrice: next.listPrice,
        imageUrl: next.imageUrl,
        quantity: next.quantity,
        minOrder: next.minOrder,
        freeDelivery: next.freeDelivery,
        category: next.category,
        source: next.source,
        skuId: next.skuId,
        specId: next.specId,
        serverId: line.serverId,
      );
    } else {
      final existing = _lines.indexWhere((other) => other.key == next.key);
      _lines.removeAt(index);
      if (existing == -1) {
        _lines.insert(index, next);
      } else {
        // Merged into the line that is already there, wherever it sits.
        final at = existing > index ? existing - 1 : existing;
        final merged = (_lines[at].quantity + next.quantity).clamp(
          _lines[at].minOrder,
          maxPerLine,
        );
        _lines[at] = _lines[at].copyWith(quantity: merged);
      }
    }

    notifyListeners();
    unawaited(_persist());
    _scheduleSync();
    return _lineByKey(next.key);
  }

  /// Takes a line out of the cart.
  ///
  /// [announce] is false where the line is being removed by the app rather
  /// than by the shopper -- checkout clears the ordered rows, and an undo puts
  /// a moved product back. Neither is somebody deleting something.
  void remove(String key, {bool announce = true}) {
    final before = _lines.length;
    _lines.removeWhere((line) => line.key == key);
    if (_lines.length == before) return;
    if (announce) unawaited(AppSounds.removed.play());
    notifyListeners();
    unawaited(_persist());
    _scheduleSync();
  }

  /// Puts a removed line back where it was, for undo.
  void restore(CartLine line, int index) {
    if (_lines.any((existing) => existing.key == line.key)) return;
    _lines.insert(index.clamp(0, _lines.length), line);
    // After the line is back, and only when one actually went back: an undo
    // of something already restored is not an undo.
    unawaited(AppSounds.undo.play());
    notifyListeners();
    unawaited(_persist());
    _scheduleSync();
  }

  int indexOf(String key) => _lines.indexWhere((line) => line.key == key);

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
    unawaited(_persist());
    _scheduleSync();
  }

  // ---------------------------------------------------------------------
  // Server sync
  //
  // The rule is: the shopper's most recent intent wins, and the server is
  // made to match it. A tap on the stepper takes effect on screen at once and
  // the network catches up, because a cart that waits for a round trip before
  // showing a number feels broken on a Nepali mobile connection.
  //
  // The exception is a cold start, where the server wins: whatever is in the
  // account is what the shopper left there, possibly on another device.
  // ---------------------------------------------------------------------

  /// True while a reconcile is in flight.
  bool _syncing = false;

  /// Set when the cart on screen has not made it to the account.
  ///
  /// Surfaced rather than swallowed. A shopper who adds three things on a train
  /// and later opens the app on a laptop should not silently find one of them.
  ApiError? _syncError;

  ApiError? get syncError => _syncError;

  /// The lines the account refused, by [CartLine.key], with the reason each
  /// was refused.
  ///
  /// Empty when the failure was not about particular lines -- no connection,
  /// or a session the server would not accept -- which is what tells the
  /// banner whether it can name the item.
  Map<String, ApiError> _rejected = const {};

  Map<String, ApiError> get rejected => Map.unmodifiable(_rejected);
  bool get isSyncing => _syncing;

  /// True when this cart lives only on the device.
  bool get isGuestCart => !AuthStore.instance.isSignedIn;

  /// Pushes local state to the server and adopts what comes back.
  ///
  /// Reconcile rather than a queue of deltas: a queue has to survive being
  /// killed mid-flight, and replaying it wrong charges someone for two of
  /// something. Comparing the two lists cannot double-add.
  Future<void> _reconcile() async {
    if (isGuestCart || _syncing) return;
    _syncing = true;
    notifyListeners();

    // Which account this reconcile is for. Checked after every answer: once
    // the shopper has switched, the rest of it belongs to nobody.
    final epoch = _epoch;
    final rejected = <String, ApiError>{};

    try {
      final server = await CartRepository.instance.list();
      if (epoch != _epoch) return;
      final remaining = {for (final item in server.items) item.id: item};

      for (var i = 0; i < _lines.length; i++) {
        final line = _lines[i];
        final match = _matchOnServer(line, remaining.values);

        // Each line stands or falls on its own. One product the account will
        // not take used to abort this whole loop: every line after it was
        // never even attempted, no removal was carried out, and the banner
        // then said the cart was not saved to the account -- about nineteen
        // lines that were fine and two that had already been written.
        try {
          if (match == null) {
            final created = await CartRepository.instance.add(
              quantity: line.quantity,
              source: line.source,
              sourceProductId: line.source == 'local' ? null : line.productId,
              productId: line.source == 'local' ? line.productId : null,
              variantLabel: line.variantLabel,
              productData: _snapshotOf(line),
            );
            // Switched away while that was in flight: the lines on screen are
            // another account's now, and none of this loop is theirs.
            if (epoch != _epoch) return;
            _lines[i] = line.copyWith(serverId: created.id);
            continue;
          }

          remaining.remove(match.id);
          if (match.quantity != line.quantity) {
            await CartRepository.instance.setQuantity(match.id, line.quantity);
            if (epoch != _epoch) return;
          }
          if (line.serverId != match.id) {
            _lines[i] = line.copyWith(serverId: match.id);
          }
        } on ApiError catch (e) {
          // A refused session is not a refused product: nothing here can be
          // saved, so stop instead of asking twenty more times and reporting
          // twenty rejections for one expired token.
          if (e.statusCode == 401 || e.statusCode == 403) rethrow;
          rejected[line.key] = e;
        }
      }

      // Rows the shopper removed on this device. Removed one at a time because
      // there is no batch delete.
      for (final orphan in remaining.values) {
        // These rows were read from the account this began in. Once the
        // shopper has switched, removing them would be removing from nobody's
        // cart on screen -- and the requests would go out as the new one.
        if (epoch != _epoch) return;
        try {
          await CartRepository.instance.remove(orphan.id);
        } on ApiError catch (e) {
          if (e.statusCode == 401 || e.statusCode == 403) rethrow;
          // A row that will not delete is not a line the shopper is holding,
          // so there is nothing on screen to report it against. The next
          // reconcile tries again.
        }
      }
      if (epoch != _epoch) return;

      // What the server now charges for each row. It reprices a row to its
      // own ladder when the quantity changes, so a quantity pushed just now
      // is read back rather than assumed: the cart shows the figure checkout
      // will charge, not the one this device last worked out.
      try {
        final confirmed = await CartRepository.instance.list();
        if (epoch != _epoch) return;
        _adoptServerPrices(confirmed);
      } on ApiError catch (e) {
        // The pushes stood; only the read-back failed. A refused session is
        // still a refused session, and the rest waits for the next read.
        if (e.statusCode == 401 || e.statusCode == 403) rethrow;
      }

      _rejected = rejected;
      // Only what was actually refused. The first reason stands for the
      // banner; [rejected] says exactly which lines it was.
      _syncError = rejected.isEmpty ? null : rejected.values.first;
    } on ApiError catch (e) {
      // The account could not be reached, or would not talk to us at all --
      // as opposed to taking most of the cart and refusing one line. The cart
      // on screen is still what the shopper wants; it just is not saved yet.
      // Kept, not rolled back.
      if (epoch == _epoch) {
        _syncError = e;
        _rejected = const {};
      }
    } finally {
      // After a switch the new account's cart owns these; this reconcile has
      // nothing left to say about it.
      if (epoch == _epoch) {
        _syncing = false;
        notifyListeners();
        unawaited(_persist());
      }
    }
  }

  /// Finds the row that stands for [line], by id first and by product second.
  ///
  /// The fallback matters on the first sync after signing in, when the account
  /// already holds the same product added from the web and the local line has
  /// no server id yet -- without it that product would be added twice.
  ServerCartItem? _matchOnServer(CartLine line, Iterable<ServerCartItem> rows) {
    for (final row in rows) {
      if (row.id == line.serverId) return row;
    }
    for (final row in rows) {
      if (row.key == line.productId && row.variantLabel == line.variantLabel) {
        return row;
      }
    }
    return null;
  }

  /// What the server stores so the line still renders when the upstream
  /// listing changes or disappears.
  Map<String, dynamic> _snapshotOf(CartLine line) => {
    'name': line.title,
    'price': line.unitPrice,
    'image': ?line.imageUrl,
    'category': ?line.category,
    'moq': line.minOrder,
    'skuId': ?line.skuId,
    'specId': ?line.specId,
    'variantLabel': ?line.variantLabel,
    // The ladder, in the product record's shape and under the name the
    // storefront stores it by, so a line rebuilt from the account keeps
    // repricing as its quantity changes.
    if (line.tiers.isNotEmpty) 'quantityTiers': quantityTiersJson(line.tiers),
  };

  /// Replaces the cart with the account's, keeping local snapshots for the
  /// rows the server sends back thin.
  void _adoptServerCart(ServerCart cart) {
    final known = {for (final line in _lines) line.key: line};

    // Lines added on this device that have not been pushed yet. Dropping them
    // would lose something the shopper added while the account's cart was
    // still loading -- a race that happens on every sign-in, because the tap
    // and the fetch overlap.
    final unpushed = _lines.where((line) => line.serverId == null).toList();

    final adopted = cart.items
        .map((item) => _lineFromServer(item, known))
        .toList(growable: true);
    final adoptedKeys = adopted.map((line) => line.key).toSet();

    _lines
      ..clear()
      ..addAll(adopted)
      ..addAll(unpushed.where((line) => !adoptedKeys.contains(line.key)));

    if (_lines.length != adopted.length) _scheduleSync();
  }

  CartLine _lineFromServer(ServerCartItem item, Map<String, CartLine> known) {
    final data = item.productData;
    final cached = known[keyOf(item.key, item.variantLabel)];

    final price =
        asNum(data['price']) ??
        asNum(data['display_price']) ??
        cached?.unitPrice ??
        0;

    // The ladder the row was stored with, or this device's copy of it.
    final ladder = quantityTiersFrom(data['quantityTiers']);
    final tiers = _ladderAgreeing(
      ladder.isNotEmpty ? ladder : (cached?.tiers ?? const []),
      price,
      item.quantity,
    );

    return CartLine(
      tiers: tiers,
      productId: item.key,
      variantLabel: item.variantLabel,
      title:
          asString(data['name']) ??
          asString(data['title']) ??
          cached?.title ??
          'Item',
      unitPrice: price,
      imageUrl:
          asString(data['image']) ??
          asString(data['pic_url']) ??
          asString(data['image_url']) ??
          cached?.imageUrl,
      quantity: item.quantity,
      minOrder: asInt(data['moq']) ?? cached?.minOrder ?? 1,
      category: asString(data['category']) ?? cached?.category,
      source: item.source,
      skuId: asString(data['skuId']) ?? cached?.skuId,
      specId: asString(data['specId']) ?? cached?.specId,
      serverId: item.id,
    );
  }

  /// [ladder] when it charges [price] at [quantity], and nothing when it
  /// does not.
  ///
  /// The server's price for a row is the price. A ladder that disagrees with
  /// it -- the seller moved a rung since this device stored it -- would
  /// reprice the row to a figure nobody will charge, so it is dropped and the
  /// server's price stands until the next sync brings a fresh one.
  static List<QuantityTier> _ladderAgreeing(
    List<QuantityTier> ladder,
    num price,
    int quantity,
  ) {
    if (ladder.isEmpty || price <= 0) return const [];
    return tierPriceAt(ladder, price, quantity) == price ? ladder : const [];
  }

  /// Takes the server's own price for each row this device holds.
  ///
  /// The server reprices a row to its ladder when the quantity changes
  /// (measured: 1 to 50 moved a row to its 50+ price, and back again), so
  /// after a quantity is pushed this reads the row back rather than assuming.
  /// Nothing else about a line changes, and a row it cannot match is left as
  /// it is.
  void _adoptServerPrices(ServerCart cart) {
    final byId = {for (final item in cart.items) item.id: item};
    var changed = false;
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final row = byId[line.serverId];
      if (row == null) continue;
      final price =
          asNum(row.productData['price']) ??
          asNum(row.productData['display_price']);
      if (price == null || price <= 0 || price == line.unitPrice) continue;
      _lines[i] = line.copyWith(
        basePrice: price,
        tiers: _ladderAgreeing(line.tiers, price, line.quantity),
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Asks the server again and takes its answer.
  ///
  /// Used on a cold start and by pull-to-refresh: what is in the account is
  /// what the shopper left there, and this device's cache may be older than
  /// another device's changes.
  Future<void> refreshFromServer() async {
    if (isGuestCart) return;
    _syncing = true;
    notifyListeners();
    // The account this cart is asked for. One that answers after a switch is
    // somebody else's cart, and is dropped.
    final epoch = _epoch;
    try {
      final cart = await CartRepository.instance.list();
      if (epoch != _epoch) return;
      _adoptServerCart(cart);
      _syncError = null;
      _rejected = const {};
    } on ApiError catch (e) {
      // Keep whatever is cached. An empty cart shown because the network
      // failed reads as "we lost your things".
      if (epoch == _epoch) _syncError = e;
    } finally {
      if (epoch == _epoch) {
        _syncing = false;
        notifyListeners();
        unawaited(_persist());
      }
    }
  }

  /// Retries after a failed sync, from the cart screen's banner.
  Future<void> retrySync() => _reconcile();

  /// Runs the pending sync now instead of waiting out the debounce.
  ///
  /// For anything that has to be able to say whether the account took a change
  /// -- a variant swap reports its own success or failure where it happened,
  /// and cannot do that while the write is six hundred milliseconds away.
  ///
  /// A guest has no account to write to and returns immediately, which is not
  /// a failure: their cart is already where it lives.
  Future<void> syncNow() async {
    _syncDebounce?.cancel();
    _syncDebounce = null;
    await _reconcile();
  }

  /// The same thing, under the name the tests already call it by.
  ///
  /// Waiting on a wall-clock timer makes them flaky the moment the machine is
  /// busy, and a flaky test about money is worse than no test.
  @visibleForTesting
  Future<void> flushSyncForTest() => syncNow();

  /// Schedules a reconcile, coalescing a burst of stepper taps into one.
  void _scheduleSync() {
    if (isGuestCart) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_reconcile());
    });
  }

  Timer? _syncDebounce;

  CartLine? _lineByKey(String key) {
    for (final line in _lines) {
      if (line.key == key) return line;
    }
    return null;
  }

  @visibleForTesting
  void resetForTest() {
    _lines.clear();
    // Anything still in flight from the last test belongs to nobody now.
    _epoch++;
    _scope = null;
    _loaded = false;
    _bound = false;
    _syncing = false;
    _syncError = null;
    _rejected = const {};
    _syncDebounce?.cancel();
    _syncDebounce = null;
    // The quote belongs to a basket. Leaving it behind when the basket is
    // cleared means the next one starts with a freight figure that was priced
    // for goods nobody has any more.
    _deliveryQuote = null;
    _quotedFor = null;
    _quoting = false;
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

  /// Writes run one after another, in the order they were asked for.
  ///
  /// Without the chain, two mutations in quick succession -- a shopper tapping
  /// the stepper twice -- are two concurrent writes whose completion order is
  /// not guaranteed, so the older quantity can land last and the newer one is
  /// silently lost on the next read.
  Future<void> _writes = Future<void>.value();

  Future<void> _write(String key, String payload) {
    return _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, payload);
      } catch (_) {
        // Best effort, like the other stores: a failed write costs persistence
        // across a restart, never the change just made.
      }
    });
  }

  Future<void> _clearStored(String key) {
    return _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {
        // See _persist.
      }
    });
  }
}

import '../../../core/network/api_error.dart';
import '../../cart/data/cart_variant_catalogue.dart';
import '../../cart/data/cart_store.dart';
import '../../product/data/product_detail_content.dart';
import '../../product/data/product_repository.dart';

/// What the catalogue says about one line of an old order, today.
///
/// The order is the record of what somebody bought; it is not evidence about
/// what is for sale now. A price moves, a colourway is withdrawn, a seller
/// raises their minimum, a listing disappears entirely -- and an order from
/// last month knows none of it. So every line is asked about again, and what
/// comes back is one of these.
///
/// Deliberately not an "is it ok" boolean. A shopper reordering three things
/// where one has gone up and one has gone needs to be told which is which,
/// and a single flag cannot say that.
enum ReorderStatus {
  /// For sale, in stock, at the same price. Nothing to say.
  available,

  /// For sale, but not at the figure on the order.
  ///
  /// Cheaper counts too. A price that fell is still a price that changed, and
  /// a shopper who budgeted for the old one should see the new one either way.
  priceChanged,

  /// The exact variant that was bought is out of stock, or the seller does not
  /// have as many as were ordered.
  outOfStock,

  /// The listing answered, but the colourway on the order is no longer among
  /// its options. The product can still be bought; that version of it cannot.
  variantGone,

  /// The listing itself is gone -- withdrawn, delisted, or never returned.
  unavailable,

  /// The catalogue could not be reached for this line.
  ///
  /// Emphatically not [unavailable]. A dead connection is not a discontinued
  /// product, and telling somebody their goods no longer exist because the
  /// wifi dropped is the worst answer this screen can give.
  unknown,
}

/// One line of an old order, checked against the catalogue as it is now.
///
/// Holds both sides: what was bought ([ordered]) and what can be bought
/// ([line], null when nothing can). Keeping the original is what lets the
/// review sheet say "was Rs. 1,505, now Rs. 1,620" rather than just showing a
/// number and hoping nobody remembers.
class ReorderItem {
  const ReorderItem({
    required this.ordered,
    required this.status,
    this.line,
    this.available,
    this.message,
  });

  /// The line exactly as it appears on the order. Never modified.
  final CartLine ordered;

  final ReorderStatus status;

  /// What would go in the cart: the same product and variant, repriced, with
  /// the live SKU and ladder attached. Null when there is nothing to add.
  ///
  /// This is the only line that ever reaches the cart. The ordered one is
  /// history and is never added -- that was the bug in the old reorder.
  final CartLine? line;

  /// How many the seller says are left, where they said and where it is a real
  /// constraint. Null means they did not say, which is not zero.
  final int? available;

  /// The server's own words, when it gave any. Shown verbatim rather than
  /// replaced with a guess.
  final String? message;

  /// Whether this line can go in the cart at all.
  bool get isBuyable => line != null;

  /// True when something about it differs from the order and the shopper
  /// should look before continuing.
  bool get needsAttention =>
      status != ReorderStatus.available && status != ReorderStatus.unknown;

  /// What one piece costs now, or what it cost then when nothing is for sale.
  num get currentPrice => line?.unitPrice ?? ordered.unitPrice;

  /// What one piece cost on the order.
  num get orderedPrice => ordered.basePrice;

  /// The difference, positive when it has gone up. Null when there is no
  /// current price to compare against.
  num? get priceDelta =>
      line == null ? null : line!.basePrice - ordered.basePrice;

  ReorderItem copyWith({int? quantity}) {
    if (quantity == null || line == null) return this;
    return ReorderItem(
      ordered: ordered,
      status: status,
      line: line!.copyWith(quantity: quantity),
      available: available,
      message: message,
    );
  }
}

/// Checks an old order against the catalogue before any of it is bought again.
///
/// One request per distinct product, through [ProductRepository.detail], which
/// de-duplicates and caches on its own -- so an order holding two variants of
/// one listing costs one call, not two.
///
/// Nothing here decides anything the server has not said. Stock, price, the
/// minimum order and the variant list all come off the live record; what this
/// adds is the comparison with what was bought, which is the one thing the
/// server cannot do because it never saw the old order.
class ReorderValidator {
  ReorderValidator._();

  static final ReorderValidator instance = ReorderValidator._();

  /// Overridable so a test can drive the validator without a widget tree.
  Future<Map<String, dynamic>> Function(String numIid) fetch =
      ProductRepository.instance.detail;

  /// Validates every line of an order, in order.
  ///
  /// Lines for the same product share one fetch. Failures are per line: one
  /// unreachable product does not fail the other five, because a reorder of
  /// six things where one is unknown is still a reorder of five.
  Future<List<ReorderItem>> validate(List<CartLine> lines) async {
    final byProduct = <String, Future<ProductDetail?>>{};
    final failures = <String, ApiError>{};

    Future<ProductDetail?> detailFor(String productId) {
      return byProduct[productId] ??= _detail(productId, failures);
    }

    // Started together, awaited together: six lines is six round trips, and
    // running them one after another is six times the wait for no benefit.
    final details = await Future.wait([
      for (final line in lines) detailFor(line.productId),
    ]);

    return [
      for (var i = 0; i < lines.length; i++)
        _check(lines[i], details[i], failures[lines[i].productId]),
    ];
  }

  /// Validates a single line, for the per-item action.
  Future<ReorderItem> validateOne(CartLine line) async {
    final results = await validate([line]);
    return results.first;
  }

  Future<ProductDetail?> _detail(
    String productId,
    Map<String, ApiError> failures,
  ) async {
    try {
      final body = await fetch(productId);
      // The 1688 service reports a missing product two ways: a 404, and an
      // HTTP 200 carrying {success: false}. Only the first arrives as an
      // ApiError, so the second is checked here -- without it a withdrawn
      // listing decodes into an empty record and reads as "available".
      if (body['success'] == false) {
        failures[productId] = ApiError.fromEnvelope(body, status: 404);
        return null;
      }
      final detail = ProductDetail.fromApi(body, fallback: null);
      // A record with no id is not a record. The envelope decodes tolerantly
      // by design, so an empty body becomes a ProductDetail full of defaults
      // rather than throwing, and that must not pass for a live listing.
      if (detail.numIid.isEmpty && detail.title.isEmpty) {
        failures[productId] = const ApiError(
          statusCode: 404,
          message: 'This product is no longer listed.',
        );
        return null;
      }
      return detail;
    } on ApiError catch (e) {
      failures[productId] = e;
      return null;
    }
  }

  /// Compares one ordered line against the live record.
  ReorderItem _check(CartLine ordered, ProductDetail? detail, ApiError? error) {
    if (detail == null) {
      // A 404 is the shop saying this is gone. Anything else -- a timeout, a
      // 500, no connection at all -- is this app failing to ask, and saying
      // "discontinued" on the strength of it would be a claim nobody made.
      final gone = error?.isNotFound ?? false;
      return ReorderItem(
        ordered: ordered,
        status: gone ? ReorderStatus.unavailable : ReorderStatus.unknown,
        message: error?.message,
      );
    }

    // The variant that was bought, found again in today's options. By label,
    // because that is all an order item carries -- the server's order rows
    // have no SKU column, so the SKU is *recovered* here rather than restored.
    final wanted = ordered.variantLabel;
    final variant = wanted == null || wanted.isEmpty
        ? null
        : variantForLine(detail.variants, skuId: ordered.skuId, label: wanted);

    if (wanted != null && wanted.isNotEmpty && variant == null) {
      // The listing is alive but this colourway is not. The product is still
      // offered -- the shopper picks again on the product page -- so this is
      // not "unavailable", and it must not silently become the base product.
      return ReorderItem(
        ordered: ordered,
        status: ReorderStatus.variantGone,
        message: 'This option is no longer offered.',
      );
    }

    // The seller's floor now, which can be higher than it was. Ordering below
    // it would be refused at checkout, so the quantity is raised to meet it
    // and the sheet shows the change rather than hiding it.
    final minOrder = detail.minOrder > 0 ? detail.minOrder : 1;
    final quantity = ordered.quantity < minOrder ? minOrder : ordered.quantity;

    final stock = variant?.stock;
    final inStock = variant?.inStock ?? true;

    if (!inStock) {
      return ReorderItem(
        ordered: ordered,
        status: ReorderStatus.outOfStock,
        available: stock,
      );
    }

    // Enough of them. Null stock is "the seller did not say" and is not a
    // reason to refuse -- see ProductVariant.stock.
    if (stock != null && stock < quantity) {
      return ReorderItem(
        ordered: ordered,
        status: ReorderStatus.outOfStock,
        available: stock,
        // Still buyable, but only up to what is left. Offered at that quantity
        // so "continue with what is available" means something concrete.
        line: stock >= minOrder
            ? _lineFor(ordered, detail, variant, stock)
            : null,
      );
    }

    final line = _lineFor(ordered, detail, variant, quantity);
    final changed = line.basePrice != ordered.basePrice;

    return ReorderItem(
      ordered: ordered,
      status: changed ? ReorderStatus.priceChanged : ReorderStatus.available,
      line: line,
      available: stock,
    );
  }

  /// The line that would go in the cart: today's price, today's SKU, today's
  /// ladder, the original product and variant.
  ///
  /// Built the same way the product page builds it -- see the `_cartLine`
  /// getter there -- so a reordered line and one added by hand from the
  /// product page are the same line, and the cart cannot tell them apart.
  CartLine _lineFor(
    CartLine ordered,
    ProductDetail detail,
    ProductVariant? variant,
    int quantity,
  ) {
    // A variant priced on its own is not on the ladder, exactly as the product
    // page has it.
    final onLadder = variant?.price == null;
    final price = variant?.price ?? detail.price;

    return CartLine(
      productId: ordered.productId,
      variantLabel: variant?.label ?? ordered.variantLabel,
      title: detail.title.isEmpty ? ordered.title : detail.title,
      unitPrice: price,
      imageUrl: variant?.imageUrl.isNotEmpty ?? false
          ? variant!.imageUrl
          : (detail.images.isEmpty ? ordered.imageUrl : detail.images.first),
      quantity: quantity,
      minOrder: detail.minOrder > 0 ? detail.minOrder : 1,
      freeDelivery: detail.freeDelivery,
      category: detail.category ?? ordered.category,
      categoryCid: detail.categoryCid ?? ordered.categoryCid,
      source: ordered.source,
      // Recovered from today's catalogue, not carried from the order -- the
      // order never had them. This is what makes the reordered line orderable
      // upstream rather than a colour name the server cannot fulfil.
      skuId: variant?.skuId ?? ordered.skuId,
      specId: variant?.specId ?? ordered.specId,
      tiers: onLadder ? detail.tiers : const [],
    );
  }
}

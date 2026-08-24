import 'checkout_repository.dart';

/// Every figure on the checkout screen, worked out in one place.
///
/// Ported from the web storefront's arithmetic rather than re-derived, because
/// the server computes the amount it actually charges the same way. Any
/// divergence here shows the shopper one number and takes another, which is
/// the single worst failure this screen has.
///
/// The order of operations is load-bearing and each step says why.
class OrderSummary {
  const OrderSummary({
    required this.subtotal,
    required this.modeDiscount,
    required this.promoDiscount,
    required this.productTotal,
    required this.productVat,
    required this.logisticTotal,
    required this.logisticVat,
    required this.totalOrder,
    required this.vatPercent,
    this.promoCode,
    this.logisticIsFree = false,
  });

  /// The selected lines only, at the prices that were shown.
  final num subtotal;

  /// Taken off for choosing a slower shipping mode.
  final num modeDiscount;

  /// Taken off by a promo code, after its cap.
  final num promoDiscount;

  /// What the goods come to. VAT-inclusive: catalogue prices already carry it.
  final num productTotal;

  /// The VAT already inside [productTotal]. Shown as a note, never added.
  final num productVat;

  final num logisticTotal;
  final num logisticVat;

  /// Goods plus delivery.
  final num totalOrder;

  final num vatPercent;
  final String? promoCode;

  /// True when a promo waived delivery entirely -- the whole leg, not just its
  /// tax.
  final bool logisticIsFree;

  num get productExVat {
    final ex = productTotal - productVat;
    return ex < 0 ? 0 : ex;
  }

  num get totalSaved => modeDiscount + promoDiscount;

  static const empty = OrderSummary(
    subtotal: 0,
    modeDiscount: 0,
    promoDiscount: 0,
    productTotal: 0,
    productVat: 0,
    logisticTotal: 0,
    logisticVat: 0,
    totalOrder: 0,
    vatPercent: 13,
  );

  /// Works the whole thing out.
  ///
  /// [subtotal] is the sum of the selected lines. It is deliberately not the
  /// server's cart subtotal, which covers every line and would over-quote an
  /// order placed for part of the basket.
  static OrderSummary compute({
    required num subtotal,
    ServerPromo? promo,
    DeliveryQuote? delivery,
    num modeDiscountPercent = 0,
  }) {
    // Step 1. The shipping-mode discount, the only figure rounded to paisa.
    final modeDiscount = _round2(subtotal * modeDiscountPercent / 100);

    // Step 2. The promo, computed on the ORIGINAL subtotal rather than on what
    // the mode discount left. Applying it to the remainder is the intuitive
    // reading and it under-discounts the shopper against both the web build
    // and the server.
    var promoDiscount = _promoRaw(promo, subtotal);

    // Step 3. But it can never eat more than the mode discount left behind, so
    // the two together cannot exceed the subtotal.
    final ceiling = subtotal - modeDiscount;
    final cap = ceiling < 0 ? 0 : ceiling;
    if (promoDiscount > cap) promoDiscount = cap;

    // Step 4. The goods, VAT included.
    final rawProduct = subtotal - modeDiscount - promoDiscount;
    final productTotal = rawProduct < 0 ? 0 : rawProduct;

    // Step 5. VAT backed OUT of that, never added on top. A catalogue price of
    // 1130 at 13% contains 130 of tax; adding 13% again would charge 1277.
    final vatPercent = delivery?.vatPercent ?? 13;
    final productVat = (productTotal * vatPercent / (100 + vatPercent)).round();

    // Step 6. Delivery. A free-shipping promo zeroes the whole leg, not just
    // its tax, and the freight VAT comes from the server rather than being
    // recomputed -- it is taxed on its own basis.
    final logisticIsFree = promo?.freeShipping ?? false;
    final logisticTotal = logisticIsFree ? 0 : (delivery?.total ?? 0);
    final logisticVat = logisticIsFree ? 0 : (delivery?.vat ?? 0);

    return OrderSummary(
      subtotal: subtotal,
      modeDiscount: modeDiscount,
      promoDiscount: promoDiscount,
      productTotal: productTotal,
      productVat: productVat,
      logisticTotal: logisticTotal,
      logisticVat: logisticVat,
      totalOrder: productTotal + logisticTotal,
      vatPercent: vatPercent,
      promoCode: promo?.code,
      logisticIsFree: logisticIsFree,
    );
  }

  static num _promoRaw(ServerPromo? promo, num subtotal) {
    if (promo == null) return 0;
    var raw = promo.discountType == 'percentage'
        ? subtotal * promo.discountValue / 100
        : promo.discountValue;
    final max = promo.maxDiscountAmount;
    if (max != null && raw > max) raw = max;
    return raw < 0 ? 0 : raw;
  }

  static num _round2(num value) => (value * 100).round() / 100;
}

/// Why a promo code cannot be used, if it cannot.
///
/// A courtesy check so the shopper is told before they reach the gateway. The
/// server decides for real when the order is placed, so a pass here is never
/// treated as final.
enum PromoRefusal {
  unknown('That code was not recognised.'),
  inactive('That code is no longer active.'),
  notYetValid('That code is not valid yet.'),
  expired('That code has expired.'),
  usedUp('That code has reached its usage limit.'),
  belowMinimum('Your order is below the minimum for that code.');

  const PromoRefusal(this.message);

  final String message;
}

/// Checks a promo against a basket, in the order the server checks it.
PromoRefusal? refusePromo(ServerPromo? promo, num subtotal) {
  if (promo == null) return PromoRefusal.unknown;
  if (!promo.isActive) return PromoRefusal.inactive;

  final now = DateTime.now();
  if (promo.validFrom != null && now.isBefore(promo.validFrom!)) {
    return PromoRefusal.notYetValid;
  }
  if (promo.validUntil != null && now.isAfter(promo.validUntil!)) {
    return PromoRefusal.expired;
  }
  if (promo.usageLimit > 0 && promo.usedCount >= promo.usageLimit) {
    return PromoRefusal.usedUp;
  }
  if (promo.minPurchaseAmount > 0 && subtotal < promo.minPurchaseAmount) {
    return PromoRefusal.belowMinimum;
  }
  return null;
}

import '../../cart/data/cart_store.dart';

/// How a coupon takes money off.
enum DiscountKind { percentage, fixed }

/// One offer.
class Coupon {
  const Coupon({
    required this.code,
    required this.headline,
    required this.kind,
    required this.value,
    required this.expiresAt,
    this.minOrder = 0,
    this.maxDiscount,
    this.eligibleCategories = const [],
    this.oncePerShopper = true,
    this.stackable = false,
  });

  /// Typed by the shopper, so it is compared case-insensitively everywhere.
  final String code;

  /// One line saying what it does, for the offers list.
  final String headline;

  final DiscountKind kind;

  /// Percent when [kind] is percentage, rupees when it is fixed.
  final num value;

  final DateTime expiresAt;

  /// Subtotal the order has to reach. Zero means no minimum.
  final num minOrder;

  /// Ceiling on a percentage discount. Null means uncapped.
  final num? maxDiscount;

  /// Empty means the whole shop. Otherwise only lines in these categories
  /// count towards the discount, and an order with none of them is refused.
  final List<String> eligibleCategories;

  final bool oncePerShopper;

  /// Whether it can sit alongside another coupon. Nothing here stacks, but the
  /// rule is stated rather than assumed so a future offer can say otherwise.
  final bool stackable;

  bool get isPercentage => kind == DiscountKind.percentage;

  bool hasExpired([DateTime? now]) =>
      (now ?? DateTime.now()).isAfter(expiresAt);

  /// How the discount reads in a list: "20% off" or "Rs. 200 off".
  String get amountLabel =>
      isPercentage ? '${value.toStringAsFixed(0)}% off' : 'Rs. $value off';

  /// Which lines this coupon actually applies to.
  ///
  /// A category-restricted coupon discounts only the lines in that category,
  /// not the whole basket. Taking 15% off a jacket and a kettle when the offer
  /// said "fashion" would be a different offer.
  List<CartLine> eligibleLines(List<CartLine> lines) {
    if (eligibleCategories.isEmpty) return lines;
    final wanted = eligibleCategories.map((c) => c.toLowerCase()).toSet();
    return lines
        .where((line) => wanted.contains((line.category ?? '').toLowerCase()))
        .toList();
  }

  /// What comes off, given the lines it applies to.
  ///
  /// Never more than the eligible amount: a Rs. 200 coupon on a Rs. 150 basket
  /// takes off 150, not 200, and certainly does not hand back 50.
  num discountFor(List<CartLine> lines) {
    final eligible = eligibleLines(lines);
    if (eligible.isEmpty) return 0;

    final base = eligible.fold<num>(0, (sum, line) => sum + line.lineTotal);
    if (base <= 0) return 0;

    num off;
    if (isPercentage) {
      off = base * value / 100;
      final cap = maxDiscount;
      if (cap != null && off > cap) off = cap;
    } else {
      off = value;
    }

    if (off > base) off = base;
    // Whole rupees. A discount that puts paise on a cash-on-delivery total is
    // a discount the courier cannot take.
    return off.round();
  }
}

/// Why a code was refused, or that it was taken.
///
/// One case per reason because each needs the shopper told something
/// different, and "invalid code" for a basket that is Rs. 40 short is the kind
/// of message that makes people give up.
sealed class CouponOutcome {
  const CouponOutcome();
}

class CouponApplied extends CouponOutcome {
  const CouponApplied(this.coupon, this.discount);
  final Coupon coupon;
  final num discount;
}

class CouponUnknown extends CouponOutcome {
  const CouponUnknown(this.code);
  final String code;
}

class CouponExpired extends CouponOutcome {
  const CouponExpired(this.coupon);
  final Coupon coupon;
}

class CouponAlreadyUsed extends CouponOutcome {
  const CouponAlreadyUsed(this.coupon);
  final Coupon coupon;
}

/// The basket is short. Carries the shortfall, because "spend more" is not
/// nearly as useful as "spend Rs. 240 more".
class CouponBelowMinimum extends CouponOutcome {
  const CouponBelowMinimum(this.coupon, this.shortfall);
  final Coupon coupon;
  final num shortfall;
}

class CouponNotApplicable extends CouponOutcome {
  const CouponNotApplicable(this.coupon);
  final Coupon coupon;
}

/// One is already on, and it does not stack.
class CouponConflict extends CouponOutcome {
  const CouponConflict(this.existing);
  final Coupon existing;
}

/// The catalogue of offers.
///
/// Not const: the expiry dates are relative to when the app started, so the
/// live offers stay live however long this build sits on a phone, and the
/// expired one stays expired. A real build reads these from the server, and
/// this class is the seam.
class CouponContent {
  const CouponContent._();

  static final _now = DateTime.now();

  static final all = <Coupon>[
    Coupon(
      code: 'DASHAIN20',
      headline: '20% off your order this festive season',
      kind: DiscountKind.percentage,
      value: 20,
      maxDiscount: 500,
      minOrder: 1000,
      expiresAt: _now.add(const Duration(days: 21)),
    ),
    Coupon(
      code: 'WELCOME200',
      headline: 'Rs. 200 off when you spend Rs. 2,000',
      kind: DiscountKind.fixed,
      value: 200,
      minOrder: 2000,
      expiresAt: _now.add(const Duration(days: 60)),
    ),
    Coupon(
      code: 'FASHION15',
      headline: '15% off clothing and footwear',
      kind: DiscountKind.percentage,
      value: 15,
      maxDiscount: 300,
      minOrder: 1000,
      eligibleCategories: const ['Fashion'],
      expiresAt: _now.add(const Duration(days: 10)),
    ),
    Coupon(
      code: 'ELECTRO10',
      headline: '10% off electronics',
      kind: DiscountKind.percentage,
      value: 10,
      maxDiscount: 1000,
      minOrder: 3000,
      eligibleCategories: const ['Electronics'],
      expiresAt: _now.add(const Duration(days: 5)),
    ),
    Coupon(
      code: 'TIHAR50',
      headline: 'Rs. 50 off, no minimum',
      kind: DiscountKind.fixed,
      value: 50,
      expiresAt: _now.subtract(const Duration(days: 3)),
    ),
  ];

  static Coupon? byCode(String code) {
    final needle = code.trim().toUpperCase();
    for (final coupon in all) {
      if (coupon.code.toUpperCase() == needle) return coupon;
    }
    return null;
  }
}

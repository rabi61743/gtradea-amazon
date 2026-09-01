import '../../catalog/data/product.dart';

/// One product in a flash sale, at its sale price.
class FlashSaleItem {
  const FlashSaleItem({
    required this.product,
    required this.listPrice,
    required this.salePrice,
    required this.discountPercent,
    this.stock,
    this.soldPercent,
  });

  final Product product;

  /// What it costs outside the sale. This is the number the card strikes
  /// through, so it has to be genuinely higher than [salePrice] or the card is
  /// claiming a saving that is not there.
  final num listPrice;

  final num salePrice;
  final int discountPercent;

  /// Units left, and how much of the batch has gone. Null where nothing knows
  /// -- the card leaves the meter out rather than drawing an invented one.
  final int? stock;
  final int? soldPercent;

  /// True only when the struck-through price is a real saving.
  bool get hasSaving => listPrice > salePrice;
}

/// A time-boxed sale: a headline, a deadline, and the products in it.
class FlashSale {
  const FlashSale({
    required this.id,
    required this.headline,
    required this.endsAt,
    required this.items,
    this.subhead,
    this.discountPercent,
    this.promoCode,
    this.isPlaceholder = false,
  });

  final String id;
  final String headline;
  final String? subhead;

  /// When it stops. Absolute, and compared against the wall clock every tick
  /// rather than counted down -- a decrementing counter drifts, and comes back
  /// from a backgrounded app confidently wrong.
  final DateTime endsAt;

  final int? discountPercent;
  final String? promoCode;
  final List<FlashSaleItem> items;

  /// True when any figure on this sale was made up rather than fetched.
  ///
  /// The backend has no flash-sale endpoint, so today this is always true and
  /// the section is showing a demonstration. It exists so the UI, the tests and
  /// anyone reading a log can tell the difference, and so the day a real
  /// endpoint lands there is one flag to check rather than a guess to make.
  final bool isPlaceholder;

  bool hasEndedAt(DateTime now) => !endsAt.isAfter(now);

  /// Never negative: a sale that ended has no time left, not minus four
  /// seconds.
  Duration remainingAt(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// A duration split into the four units a countdown shows.
///
/// Its own type because the arithmetic is easy to get subtly wrong in a build
/// method -- `inHours` is total hours, not hours-within-the-day, and a sale two
/// days out otherwise reads as "48 Hrs".
class CountdownParts {
  const CountdownParts({
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
  });

  factory CountdownParts.from(Duration remaining) {
    final clamped = remaining.isNegative ? Duration.zero : remaining;
    return CountdownParts(
      days: clamped.inDays,
      hours: clamped.inHours.remainder(24),
      minutes: clamped.inMinutes.remainder(60),
      seconds: clamped.inSeconds.remainder(60),
    );
  }

  final int days;
  final int hours;
  final int minutes;
  final int seconds;

  bool get isZero => days == 0 && hours == 0 && minutes == 0 && seconds == 0;

  /// Two digits, because a countdown that shrinks from "10" to "9" shifts every
  /// digit beside it and reads as a glitch.
  String two(int value) => value.toString().padLeft(2, '0');
}

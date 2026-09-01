/// Every made-up number in the flash sale lives here, and nowhere else.
///
/// The backend has no flash-sale endpoint. It has exactly one time-limited
/// promotion mechanism -- `promo_valid_until`, `promo_headline_percent`,
/// `promo_amount` and `promo_code` on a hero banner -- and every live banner
/// currently has all four set to null. Nothing in the catalogue carries a list
/// price, a discount, a stock level or a sold count.
///
/// So the section you see is a demonstration standing in for data that does not
/// exist yet. That was a deliberate call, and this file is where the cost of it
/// is kept: one import to delete, one flag to flip, and the UI falls back to
/// showing only what the server actually said.
///
/// **Read this before shipping to real shoppers.** The struck-through price is
/// the sharp edge. `listPriceFor` invents a higher "was" figure so the card can
/// show a saving, and a saving that never existed is a false price claim --
/// which is why `toProductItem` in `catalog_visuals.dart` refuses to do the
/// same thing for the ordinary rails. Turning [enabled] off, or giving the
/// backend somewhere to send a real list price, is what makes this honest.
library;

/// Whether the placeholder figures are used at all.
///
/// Off, and the section shows a sale only when a banner carries a real
/// `promo_valid_until`, with no discount badge, no struck price, no stock and
/// no sold meter -- because the server has none of those to give.
const bool enabled = true;

/// How long a demonstration sale runs.
const Duration windowLength = Duration(hours: 6);

/// When the current demonstration sale ends.
///
/// Derived from the clock rather than stored, so it is the same answer on every
/// screen and every restart -- a countdown that resets to six hours each time
/// the app opens is its own kind of lie. Sales land on the next six-hourly
/// boundary, so one always exists and each rolls over into the next.
DateTime windowEnd(DateTime now) {
  final hours = windowLength.inHours;
  final boundary = ((now.hour ~/ hours) + 1) * hours;
  final start = DateTime(now.year, now.month, now.day);
  return start.add(Duration(hours: boundary));
}

/// A stable pseudo-random number for a product, in `[0, range)`.
///
/// Seeded from the catalogue id so a card shows the same discount every time it
/// is built. Anything derived from `Random()` would reshuffle on every scroll,
/// and a stock count that changes as you look at it is worse than no stock
/// count at all.
int _seeded(String id, int salt, int range) {
  var hash = salt;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return range <= 0 ? 0 : hash % range;
}

/// A discount between 20% and 50%, in steps of 5.
int discountFor(String numIid) => 20 + _seeded(numIid, 17, 7) * 5;

/// The "was" price a discount implies.
///
/// Worked backwards from the sale price so the two are at least arithmetically
/// consistent with the badge. It is still a number nobody published.
num listPriceFor(num salePrice, int discountPercent) {
  if (discountPercent <= 0 || discountPercent >= 100) return salePrice;
  return (salePrice * 100 / (100 - discountPercent)).roundToDouble();
}

/// Units left, 8 to 87.
int stockFor(String numIid) => 8 + _seeded(numIid, 53, 80);

/// How much of the batch has gone, 35% to 89%.
///
/// Deliberately never 100: a meter that reads full beside a card you can still
/// buy from is the one number a shopper will notice is wrong.
int soldPercentFor(String numIid) => 35 + _seeded(numIid, 91, 55);

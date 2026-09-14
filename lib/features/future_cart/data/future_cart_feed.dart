// `Category` is the catalogue's department here, not Flutter's diagnostics
// annotation of the same name -- which foundation exports, and which would
// otherwise win the ambiguity and fail the build.
import 'dart:math' as math;

import 'package:flutter/foundation.dart' hide Category;

import '../../../core/network/api_error.dart';
import '../../cart/data/cart_store.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/data/product.dart';
import '../../orders/data/order_store.dart';
import '../../product/data/product_detail_content.dart';
import '../../product/data/product_repository.dart';

/// Why the Future Cart is putting a product in front of the shopper.
///
/// The kind decides the mark beside the sentence, and the sentence is built
/// from the shopper's own history -- never a phrase picked to look clever. See
/// [FutureCartFeed] for where each one comes from.
enum SuggestionKind {
  /// Bought more than once, at a steady spacing: "every 30 days".
  rhythm,

  /// Bought more than once, too close together to call an interval.
  frequent,

  /// Bought once. All that can honestly be said is when.
  lastBought,

  /// Goes with something in the cart right now.
  complement,
}

/// One product, with the reason it is being shown.
@immutable
class Suggestion {
  const Suggestion({
    required this.product,
    required this.label,
    required this.reason,
    required this.kind,
  });

  final Product product;

  /// What kind of suggestion this is, in three or four words: "You Usually
  /// Buy", "Last Purchased", "You Buy This Frequently".
  ///
  /// Split from [reason] so the card can lead with the label and follow with
  /// the figure, which is what lets both sit in the two lines the pill already
  /// had -- the card carries the label without growing a point taller.
  final String label;

  /// The figure under the label: "Every 30 days", "28 days ago". Derived from
  /// real orders or the real cart, and never shown without the fact behind it.
  ///
  /// Empty where the label is the whole fact, as it is for a habit -- there is
  /// no number in "You Buy This Frequently". The label then takes both lines.
  final String reason;

  final SuggestionKind kind;
}

/// A product this shopper has actually bought, and when.
///
/// Built from [OrderStore] -- the same orders the account's history screen
/// shows -- so every figure here is something that really happened.
@immutable
class BoughtProduct {
  const BoughtProduct({required this.line, required this.dates});

  /// The line as it was ordered: title, picture, category, and the price that
  /// was charged. The catalogue is asked for the current price separately;
  /// this is what the card falls back to when that request fails.
  final CartLine line;

  /// When it was bought, newest first. One entry per order it appeared in.
  final List<DateTime> dates;

  int get purchases => dates.length;

  int daysSinceLast(DateTime now) => now.difference(dates.first).inDays;

  /// The mean gap between consecutive purchases, in whole days.
  ///
  /// Null below two purchases -- one purchase is a fact, not a rhythm -- and
  /// null when several orders landed the same day, which is one shopping trip
  /// rather than a repeat.
  int? get averageIntervalDays {
    if (dates.length < 2) return null;
    final span = dates.first.difference(dates.last).inDays;
    if (span <= 0) return null;
    final mean = (span / (dates.length - 1)).round();
    return mean > 0 ? mean : null;
  }
}

/// What the Future Cart offers, read from what this shopper did.
///
/// Two sources, both real:
///
///   * **Often Bought Again** is [OrderStore] -- products that appear in past
///     orders, with the rhythm worked out from the dates on those orders. The
///     current price comes from the catalogue's own record for that exact
///     product id, so a card never quotes a price the shop has moved on from.
///   * **Complements** is the catalogue, asked about the departments the cart
///     is buying from right now. The same ladder the cart's own shelf climbs:
///     the sub-category ids the lines carry, then the departments behind them,
///     then the line's own label as a search.
///
/// Nothing here invents a product, a price or a reason. Where a fact is
/// missing the suggestion is dropped rather than filled in.
abstract final class FutureCartFeed {
  /// How many cards a section shows.
  static const shown = 6;

  /// Whether the repeats section falls back to stand-in cards when this
  /// account has never ordered.
  ///
  /// On by request, so the section can be seen on a device with no purchase
  /// history. It puts sentences on cards that are not true of this shopper --
  /// see [sampleRepeats] -- so it is a switch rather than something woven in:
  /// set it false and the page tells the truth again, with no other change.
  static const usePlaceholderRepeats = true;

  /// How many a carousel shows, which is more.
  ///
  /// A grid is bounded by the page: six cards fill two rows and the reader
  /// sees all of them. A rail is bounded by patience instead -- it exists to
  /// be swiped, and stopping after six makes the swipe end almost before it
  /// starts. Fourteen is what the pool can honestly supply: the ladder below
  /// asks three sub-categories for twelve rows each before the departments
  /// behind them, so this is drawn from products that came back, never padded
  /// out to reach a number.
  static const carouselShown = 14;

  /// How many of the cart's sub-categories get asked about, and how many
  /// departments behind them. The cart's own shelf uses the same two numbers
  /// for the same reason: the whole basket would be a request per line.
  static const subCategories = 3;
  static const departments = 2;

  // ── Often bought again ───────────────────────────────────────────────────

  /// Products from past orders, the strongest repeat signal first.
  ///
  /// Excludes anything already in the cart: a shopper looking at this page has
  /// the cart open behind it, and offering to add what is already in there is
  /// noise.
  static Future<List<Suggestion>> oftenBoughtAgain({
    DateTime? now,
    int limit = shown,
  }) async {
    await OrderStore.instance.load();
    await CartStore.instance.load();
    final clock = now ?? DateTime.now();

    final bought = _purchaseHistory();
    if (bought.isEmpty) return const [];

    // What is in the cart is *not* filtered out any more.
    //
    // It used to be, on the reasoning that offering what is already in the
    // basket is noise. That was true when the card could only say "Add to
    // Cart" -- but the card now shows the line's own quantity with fewer,
    // more and remove, so a product in the cart is not a duplicate offer, it
    // is the same product with its state on it.
    //
    // Filtering also had a bug behind it: the feed is built on load, so a
    // product added from this page kept its card until the next refresh and
    // then vanished mid-scroll. Keeping it is both the simpler rule and the
    // one that does not make cards disappear.
    final ranked = bought.toList()
      ..sort((a, b) {
        final byCount = b.purchases.compareTo(a.purchases);
        return byCount != 0 ? byCount : b.dates.first.compareTo(a.dates.first);
      });

    final out = <Suggestion>[];
    for (final candidate in ranked.take(limit)) {
      final product = await _currentRecordFor(candidate.line);
      // No price, no card: the reference's card is a price and an Add button,
      // and neither can be drawn for a product the shop cannot price.
      if (!product.hasPrice) continue;
      if (isAdult(product)) continue;
      final (label, detail, kind) = _repeatReason(candidate, clock);
      out.add(
        Suggestion(product: product, label: label, reason: detail, kind: kind),
      );
    }
    return out;
  }

  /// Stand-in repeats for an account with no order history.
  ///
  /// **The cards are real; the reasons on them are not.** The products come
  /// from [CatalogRepository.randomPicks] -- real listings, real ids, real
  /// prices, so the Add button adds something that exists at a price the shop
  /// will honour. What is invented is the sentence: "You Usually Buy / Every
  /// 30 days" on a product nobody here has ever bought.
  ///
  /// That is a false statement in a shipping app, and it is here only because
  /// it was asked for, to see the section filled on a device whose account has
  /// never ordered. [usePlaceholderRepeats] is the switch: turn it off and the
  /// section goes back to appearing only when there are real purchases behind
  /// it. Nothing else reads this -- real repeats always win, because the
  /// caller only falls back when [oftenBoughtAgain] comes back empty.
  static Future<List<Suggestion>> sampleRepeats({
    int limit = carouselShown,
    math.Random? random,
  }) async {
    await CartStore.instance.load();

    final picks = await CatalogRepository.instance.randomPicks(
      limit: limit * 2,
      random: random,
    );

    final out = <Suggestion>[];
    for (final product in picks) {
      if (out.length >= limit) break;
      if (!product.hasPrice) continue;
      // What is in the cart stays on the shelf, for the reason recorded in
      // [oftenBoughtAgain]: the card carries its own quantity now.
      if (isAdult(product)) continue;
      // Rotated so all three treatments are on the page: the design is the
      // point of the placeholder, and one repeated label would show a third
      // of it.
      final (label, detail, kind) = _sampleReason(out.length);
      out.add(
        Suggestion(product: product, label: label, reason: detail, kind: kind),
      );
    }
    return out;
  }

  /// The three repeat treatments, in turn. Invented figures -- see
  /// [sampleRepeats].
  static (String, String, SuggestionKind) _sampleReason(int i) =>
      switch (i % 3) {
        0 => ('You Usually Buy', 'Every 30 days', SuggestionKind.rhythm),
        1 => ('Last Purchased', '28 days ago', SuggestionKind.lastBought),
        _ => ('You Buy This Frequently', '', SuggestionKind.frequent),
      };

  /// Every product in this account's orders, with the dates it was bought on.
  static List<BoughtProduct> _purchaseHistory() {
    final dates = <String, List<DateTime>>{};
    final lines = <String, CartLine>{};

    // Newest first, which [OrderStore] guarantees, so the first line recorded
    // for a product is the most recent one it was ordered as.
    for (final order in OrderStore.instance.orders) {
      for (final line in order.lines) {
        if (line.productId.isEmpty) continue;
        (dates[line.productId] ??= []).add(order.placedAt);
        lines.putIfAbsent(line.productId, () => line);
      }
    }

    return [
      for (final entry in dates.entries)
        if (lines[entry.key] case final line?)
          BoughtProduct(
            line: line,
            dates: entry.value..sort((a, b) => b.compareTo(a)),
          ),
    ];
  }

  /// The label for a repeat, the figure under it, and the mark beside them.
  static (String, String, SuggestionKind) _repeatReason(
    BoughtProduct bought,
    DateTime now,
  ) {
    final every = bought.averageIntervalDays;

    // Four or more purchases is a habit whatever the spacing says, and
    // "every 9 days" from four scattered orders reads as a promise the data
    // does not support. No figure, so the label carries it alone.
    if (bought.purchases >= 4) {
      return ('You Buy This Frequently', '', SuggestionKind.frequent);
    }
    if (every != null) {
      return ('You Usually Buy', 'Every $every days', SuggestionKind.rhythm);
    }
    if (bought.purchases > 1) {
      return ('You Buy This Frequently', '', SuggestionKind.frequent);
    }

    final days = bought.daysSinceLast(now);
    final when = switch (days) {
      <= 0 => 'Today',
      1 => 'Yesterday',
      _ => '$days days ago',
    };
    return ('Last Purchased', when, SuggestionKind.lastBought);
  }

  /// The catalogue's record for a product that was bought before.
  ///
  /// The price on an order line is the price that was *charged*, frozen on
  /// purpose so an old order keeps its own total. Putting that on a card
  /// offering to sell the thing again would quote a price the shop may no
  /// longer honour, so the live record is asked for by product id.
  ///
  /// A failed request falls back to the order line rather than dropping the
  /// card: the shopper really did buy this, and the last price they paid is a
  /// real figure -- it is simply an older one.
  static Future<Product> _currentRecordFor(CartLine line) async {
    final snapshot = productStub(
      numIid: line.productId,
      title: line.title,
      imageUrl: line.imageUrl,
      displayPrice: line.basePrice,
    );

    try {
      final body = await ProductRepository.instance.detail(line.productId);
      final detail = ProductDetail.fromApi(body, fallback: snapshot);
      return Product(
        numIid: line.productId,
        title: detail.title.isEmpty ? line.title : detail.title,
        imageUrl: detail.images.isEmpty ? line.imageUrl : detail.images.first,
        displayPrice: detail.price > 0 ? detail.price : line.basePrice,
        sales: detail.soldCount,
        categoryCid: detail.categoryCid ?? line.categoryCid,
        categoryName: detail.category ?? line.category,
        minOrder: detail.minOrder > 0 ? detail.minOrder : line.minOrder,
      );
    } on ApiError {
      return snapshot;
    }
  }

  // ── Complements ──────────────────────────────────────────────────────────

  /// Products that go with what is in the cart right now.
  ///
  /// The ladder is the cart shelf's own, for the reason recorded there: the
  /// sub-category ids a line carries are the sharp signal, the department
  /// behind them is the blunt one, and a label the department tree has never
  /// heard of -- most of this catalogue's leaves -- falls through to a search
  /// on the line's own words.
  static Future<List<Suggestion>> complements({int limit = shown}) async {
    await CartStore.instance.load();
    final lines = CartStore.instance.lines;
    if (lines.isEmpty) return const [];

    final pool = <Product>[];
    final reasons = <String, String>{};

    void remember(Iterable<Product> found, CartLine about) {
      for (final product in found) {
        pool.add(product);
        reasons.putIfAbsent(
          product.numIid,
          // Short because the pill is: measured on the phone it takes about
          // ten characters a line and holds two, so "Goes well with your
          // mobile." wanted three lines and lost the last one to an ellipsis.
          // The heading above already says these go with the cart; the card
          // only has to name what they go with.
          // The line's department, not its title, when it has one.
          //
          // The title is keyword soup written for a sourcing index, and
          // skipping the trade filler in "New Spot Grafted Eyelash Tweezers"
          // lands on "grafted" -- a complete sentence naming an adjective.
          // The department is what actually chose this suggestion, so it is
          // both the more accurate word and the more readable one.
          () => _shortTitle(about.category ?? about.title),
        );
      }
    }

    // Sharpest first: the exact sub-categories the basket is buying from.
    for (final line in _byWeight(lines).take(subCategories)) {
      final cid = line.categoryCid?.trim();
      if (cid == null || cid.isEmpty) continue;
      try {
        remember(
          await CatalogRepository.instance.categoryProducts(
            cid,
            sort: ProductSort.sales,
            pageSize: 12,
          ),
          line,
        );
      } on ApiError {
        // One sub-category drawing a blank leaves the others their turn.
      }
    }

    // Then the departments those lines sit in, for anything whose
    // sub-category the catalogue could not answer for.
    if (pool.length < limit) {
      final tree = await _departmentIds();
      for (final line in _byWeight(lines).take(departments)) {
        final cid = tree[line.category?.toLowerCase().trim()];
        if (cid == null) continue;
        try {
          remember(
            await CatalogRepository.instance.trending(
              categoryCid: cid,
              limit: 12,
            ),
            line,
          );
        } on ApiError {
          // As above.
        }
      }
    }

    // And last, the line's own words, which is what answers for the lines
    // whose label the department tree does not carry.
    if (pool.isEmpty) {
      for (final line in _byWeight(lines).take(departments)) {
        try {
          remember(
            await CatalogRepository.instance.search(
              query: _shortTitle(line.title),
              sort: ProductSort.sales,
              pageSize: 12,
            ),
            line,
          );
        } on ApiError {
          // As above.
        }
      }
    }

    final seen = <String>{};
    final out = <Suggestion>[];
    for (final product in pool) {
      if (out.length == limit) break;
      if (!product.hasPrice) continue;
      if (isAdult(product)) continue;
      // A product already in the cart is still shown, with its own quantity
      // on it -- see [oftenBoughtAgain]. Only the duplicate *card* is barred.
      if (!seen.add(product.numIid)) continue;
      out.add(
        Suggestion(
          product: product,
          label: 'Pairs With',
          reason: reasons[product.numIid] ?? 'your cart',
          kind: SuggestionKind.complement,
        ),
      );
    }
    return out;
  }

  /// Cart lines, the one with most units first. The same weighting the cart's
  /// shelf uses: three of something says more than one of it.
  static List<CartLine> _byWeight(List<CartLine> lines) =>
      lines.toList()..sort((a, b) => b.quantity.compareTo(a.quantity));

  // ── Department chips ─────────────────────────────────────────────────────

  /// The best sellers in the real departments whose names match [keywords].
  ///
  /// The departments are resolved against the catalogue's own tree rather than
  /// against a list of ids written down here: the chips have to point at
  /// departments the shop actually has, and a hardcoded id is a chip that
  /// silently empties the day the tree is reorganised. Keywords that match
  /// nothing yield nothing, and the chip says so rather than inventing
  /// something to fill itself with.
  ///
  /// Every card carries a reason, so these carry the only one that is true of
  /// them: the request is the department's own listing ordered by sales, which
  /// is what makes "Popular in Kidswear" a fact rather than a slogan. The
  /// department is named from the tree, never from the keyword that found it.
  static Future<List<Suggestion>> departmentSuggestions(
    List<String> keywords, {
    int limit = shown,
  }) async {
    await CartStore.instance.load();
    final matched = [
      for (final category in await _tree())
        if (keywords.any(category.name.toLowerCase().contains)) category,
    ];
    if (matched.isEmpty) return const [];

    final seen = <String>{};
    final out = <Suggestion>[];

    for (final category in matched) {
      if (out.length >= limit) break;
      try {
        final found = await CatalogRepository.instance.categoryProducts(
          category.cid,
          sort: ProductSort.sales,
          pageSize: 12,
        );
        for (final product in found) {
          if (out.length >= limit) break;
          if (!product.hasPrice) continue;
          // These two rails are For Home and For Kids. A department whose
          // best sellers include adult goods must not put them on a page
          // that names children in the heading above.
          if (isAdult(product)) continue;
          // What is in the cart keeps its card here too, carrying its own
          // quantity -- see [oftenBoughtAgain] for why it is no longer cut.
          if (!seen.add(product.numIid)) continue;
          out.add(
            Suggestion(
              product: product,
              // The department's first word only, for the pill's sake:
              // "Home" rather than "Home Textile Furniture", which truncates
              // to nothing worth reading.
              label: 'Popular In',
              reason: category.name.split(' ').first,
              kind: SuggestionKind.complement,
            ),
          );
        }
      } on ApiError {
        // One department failing is not the chip failing.
      }
    }
    return out;
  }

  static Future<List<Category>> _tree() async {
    try {
      await CatalogStore.instance.categories.load();
    } catch (_) {
      return const [];
    }
    return CatalogStore.instance.categories.value ?? const [];
  }

  /// Department name to id, for the whole tree.
  static Future<Map<String, String>> _departmentIds() async {
    final byName = <String, String>{};
    void walk(Category category) {
      byName.putIfAbsent(
        category.name.toLowerCase().trim(),
        () => category.cid,
      );
      for (final child in category.children) {
        walk(child);
      }
    }

    for (final category in await _tree()) {
      walk(category);
    }
    return byName;
  }

  /// One word naming what a cart line actually is.
  ///
  /// **One, not two or three.** Both were measured on the phone and both
  /// truncated the pill to "Goes well with your..." -- the half of the
  /// sentence that carries nothing. The reference fits because its reasons
  /// name a short noun: "your shampoo". A card 127 points wide has room for
  /// about that and no more.
  ///
  /// **And not simply the first word.** These titles are keyword soup written
  /// for a sourcing index -- "New Spot Small Thickened...", "Source Factory
  /// Customized..." -- so the opening words are trade filler. Taking the first
  /// one would put "Goes well with your new." on the card, which is worse than
  /// saying nothing. The filler is skipped, and a title that is nothing but
  /// filler falls back to naming the cart rather than guessing.
  @visibleForTesting
  static String shortTitleOf(String title) => _shortTitle(title);

  /// Words that describe how a listing is sold rather than what it is.
  ///
  /// Two kinds live here. The first is trade filler -- how the listing is
  /// sold. The second is qualifiers: words that describe the thing rather
  /// than name it. Those were added because the card said "Pairs With
  /// handsome", off a polo shirt whose title runs "...Summer Handsome Light
  /// Mature Style...". An adjective can be as long as a noun, so no rule
  /// about length can tell them apart; they have to be named.
  static const _filler = {
    // How it is sold.
    'new', 'spot', 'hot', 'sale', 'wholesale', 'custom', 'customized',
    'customised', 'source', 'factory', 'direct', 'supply', 'cross', 'border',
    'upgraded', 'quality', 'free', 'product', 'products', 'style', 'the',
    'and', 'for', 'with', 'set', 'sets', 'piece', 'pieces', 'item', 'items',
    'ins', 'pcs',
    // What it is like. The card names the thing, never the adjective.
    'high', 'large', 'small', 'mini', 'big', 'long', 'short', 'light',
    'heavy', 'thick', 'thickened', 'thin', 'soft', 'hard', 'warm', 'cool',
    'handsome', 'trendy', 'trend', 'vintage', 'mature', 'stable', 'elegant',
    'luxury', 'premium', 'fashion', 'fashionable', 'casual', 'cute', 'lovely',
    'pretty', 'beautiful', 'simple', 'classic', 'modern', 'durable',
    'portable', 'delicate', 'fine', 'good', 'best', 'top', 'super', 'ultra',
    'sleeved', 'sleeve', 'summer', 'winter', 'autumn', 'spring', 'false',
    'full', 'auto', 'natural', 'pure', 'smart', 'creative', 'special',
  };

  static String _shortTitle(String title) {
    final words = title
        // Hyphens split rather than survive: "Kong-style" used to come
        // through whole, a ten-character token that is not a word anyone
        // would say, and it beat every real noun in the title on length.
        .replaceAll(RegExp(r'[^A-Za-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .map((word) => word.toLowerCase())
        // Long enough to be a word, short enough to fit the pill.
        .where((word) => word.length > 2 && word.length <= 10)
        // "2022" is in half these titles and names nothing.
        .where((word) => !RegExp(r'^\d+$').hasMatch(word))
        .where((word) => !_filler.contains(word))
        .toList();
    if (words.isEmpty) return 'cart';

    // The last word, not the longest.
    //
    // English noun phrases are head-final: the thing being named comes last
    // and everything before it describes it. "Floral shirt" is a shirt,
    // "False eyelashes" are eyelashes, "Home Textile Furniture" is furniture.
    //
    // Length was the previous rule and it is not a signal at all -- it only
    // looked like one because this catalogue's qualifiers happened to be
    // short. "Handsome" is eight letters and "shoulder" is eight letters, and
    // on that tie the card named the adjective. Position is the real rule;
    // the stop-list above handles the titles that trail off in adjectives,
    // so "...Ruffian handsome coat trendy" still lands on "coat".
    return words.last;
  }

  /// Whether a product is adult goods, and so not something to put on a page
  /// of unbidden suggestions.
  ///
  /// This page never asks for such a category: its sections are what the
  /// shopper repeats, what goes with the cart, and two departments -- home
  /// and kids. So nothing here is "explicitly browsing" adult goods and the
  /// guard applies throughout. A shopper who searches for these products in
  /// the catalogue still finds them; this only governs what is offered
  /// unasked, on a page that sits two rows above a Kidswear rail.
  ///
  /// Matched on the title and the category together, because this catalogue's
  /// categories are unreliable and the titles are explicit.
  @visibleForTesting
  static bool isAdult(Product product) {
    final haystack = [
      product.title,
      product.categoryName ?? '',
      product.parentCategoryName ?? '',
    ].join(' ').toLowerCase();
    return _adult.any(haystack.contains);
  }

  /// Substrings rather than words: these appear inside compounds as often as
  /// alone, and "masturbation" has to catch "masturbator" too.
  static const _adult = {
    'masturbat',
    'vibrator',
    'dildo',
    'sex toy',
    'sexual',
    'erotic',
    'fetish',
    'bdsm',
    'anal plug',
    'butt plug',
    'condom',
    'lubricant',
    'penis',
    'vagina',
    'adult toy',
    'adult product',
    'sex ',
  };
}

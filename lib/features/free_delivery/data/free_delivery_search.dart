import '../../catalog/data/product.dart';

/// One row of the free-delivery collection, with the words it can be found by.
///
/// The catalogue [Product] carries what a card draws -- title, picture, price.
/// The collection row carries more than that, and two of its fields are worth
/// searching: the category the seller filed it under, and the brand where one
/// is set. They live here rather than on [Product] so that nothing outside
/// this collection changes shape.
class FreeDeliveryListing {
  const FreeDeliveryListing({required this.product, this.category, this.brand});

  final Product product;

  /// `item.category_name`, e.g. "Refrigerator storage box". Often absent.
  final String? category;

  /// `item.brand`. Absent on most of this collection.
  final String? brand;
}

/// Folds a term to the form matching compares.
///
/// Case goes, accents fold to their plain letters, and anything that is not a
/// letter or a digit becomes a space -- so "Men's" finds "mens", "T-Shirt"
/// finds "t shirt", and a stray comma does not stop a match. Letters and
/// digits are kept by Unicode class rather than by ASCII range, because a good
/// half of this collection is filed under Chinese seller text.
String normalizeSearch(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    buffer.writeCharCode(_fold[rune] ?? rune);
  }
  return buffer
      .toString()
      // Apostrophes vanish rather than splitting a word, so "Men's" folds to
      // "mens" and is found by it. Everything else that is not a letter or a
      // digit becomes a space.
      .replaceAll(_apostrophes, '')
      .replaceAll(_separators, ' ')
      .trim()
      .replaceAll(_runs, ' ');
}

final _apostrophes = RegExp("['\u2018\u2019]");
final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _runs = RegExp(r'\s+');

/// The accents this shop actually sees, folded to plain letters.
const _fold = <int, int>{
  0xE0: 0x61,
  0xE1: 0x61,
  0xE2: 0x61,
  0xE3: 0x61,
  0xE4: 0x61,
  0xE5: 0x61,
  0xE7: 0x63,
  0xE8: 0x65,
  0xE9: 0x65,
  0xEA: 0x65,
  0xEB: 0x65,
  0xEC: 0x69,
  0xED: 0x69,
  0xEE: 0x69,
  0xEF: 0x69,
  0xF1: 0x6E,
  0xF2: 0x6F,
  0xF3: 0x6F,
  0xF4: 0x6F,
  0xF5: 0x6F,
  0xF6: 0x6F,
  0xF9: 0x75,
  0xFA: 0x75,
  0xFB: 0x75,
  0xFC: 0x75,
  0xFD: 0x79,
  0xFF: 0x79,
};

/// A prepared search over one free-delivery collection.
///
/// **It searches this collection and nothing else.** There is no fallback to
/// the catalogue: a product the shop sells but does not deliver free has no
/// row here, so it cannot be returned, and that is a property of where the
/// rows come from rather than of a filter that could be got wrong.
///
/// The whole collection is already in memory -- `GET /free-delivery` ignores
/// every parameter it is sent and answers with all 557 rows, so the screen
/// holds them all whether or not anybody searches. Matching them here costs no
/// request at all, which is the fastest this can be made. Each row's words are
/// folded **once**, when the index is built, rather than on every keystroke:
/// that is what keeps a keystroke to a scan of prepared strings.
class FreeDeliveryIndex {
  FreeDeliveryIndex(List<FreeDeliveryListing> listings)
    : _entries = [
        for (var i = 0; i < listings.length; i++)
          _Entry(
            listing: listings[i],
            order: i,
            title: normalizeSearch(listings[i].product.title),
            category: normalizeSearch(listings[i].category ?? ''),
            brand: normalizeSearch(listings[i].brand ?? ''),
          ),
      ];

  final List<_Entry> _entries;

  /// Everything in the collection, in the order the curator set.
  List<Product> get all => [
    for (final entry in _entries) entry.listing.product,
  ];

  /// The free-delivery products matching [query], best first.
  ///
  /// Every word typed has to appear somewhere -- title, category or brand --
  /// so a second word narrows rather than widens. An empty query is not a
  /// search: it gives the collection back untouched.
  List<Product> search(String query) {
    final terms = _terms(query);
    if (terms.isEmpty) return all;

    final hits = <_Hit>[];
    for (final entry in _entries) {
      final score = entry.score(terms);
      if (score > 0) hits.add(_Hit(entry, score));
    }
    // Best match first, and the curator's own order to break a tie -- two
    // equally good matches should come back in the order the collection puts
    // them, not in whichever order the scan happened to find them.
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.entry.order.compareTo(b.entry.order);
    });
    return [for (final hit in hits) hit.entry.listing.product];
  }

  /// What to offer as the shopper types, drawn only from this collection.
  ///
  /// Categories and brands first: they are short, they are the words somebody
  /// is most likely to have half-typed, and each stands for a group of
  /// products rather than one. Product titles fill what is left, so a specific
  /// thing is still one tap away.
  List<String> suggest(String query, {int limit = 6}) {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];

    final categories = <String>[];
    final brands = <String>[];
    final titles = <String>[];
    final seen = <String>{};

    void offer(List<String> into, String? value, String normalized) {
      if (value == null || value.trim().isEmpty) return;
      if (!terms.every(normalized.contains)) return;
      if (!seen.add(normalized)) return;
      into.add(value.trim());
    }

    for (final entry in _entries) {
      offer(categories, entry.listing.category, entry.category);
      offer(brands, entry.listing.brand, entry.brand);
      if (entry.score(terms) > 0) {
        offer(titles, entry.listing.product.title, entry.title);
      }
      // Enough of everything to fill the list whatever the mix turns out to
      // be; the trim below decides what actually shows.
      if (categories.length + brands.length >= limit &&
          titles.length >= limit) {
        break;
      }
    }

    return [
      ...categories,
      ...brands,
      ...titles,
    ].take(limit).toList(growable: false);
  }

  static List<String> _terms(String query) =>
      normalizeSearch(query)
          .split(' ')
          .where((term) => term.isNotEmpty)
          .toList(growable: false);
}

class _Entry {
  _Entry({
    required this.listing,
    required this.order,
    required this.title,
    required this.category,
    required this.brand,
  });

  final FreeDeliveryListing listing;

  /// Where the curator put it, for tie-breaking.
  final int order;

  final String title;
  final String category;
  final String brand;

  /// How well this row answers [terms], or zero if it does not.
  ///
  /// A word starting a word in the title beats the same letters buried inside
  /// one -- "pol" should find the Polo shirts before it finds a product with
  /// "monopoly" in the description -- and the title outranks the category it
  /// was filed under.
  double score(List<String> terms) {
    var total = 0.0;
    for (final term in terms) {
      final one = _scoreTerm(term);
      // Every word has to land somewhere. Two words that each match half the
      // collection should not return half the collection.
      if (one == 0) return 0;
      total += one;
    }
    return total;
  }

  double _scoreTerm(String term) {
    if (_startsWord(title, term)) return 3;
    if (title.contains(term)) return 2;
    if (_startsWord(category, term)) return 1.5;
    if (category.contains(term)) return 1;
    if (brand.contains(term)) return 1;
    return 0;
  }

  static bool _startsWord(String haystack, String term) {
    if (haystack.startsWith(term)) return true;
    return haystack.contains(' $term');
  }
}

class _Hit {
  const _Hit(this.entry, this.score);

  final _Entry entry;
  final double score;
}

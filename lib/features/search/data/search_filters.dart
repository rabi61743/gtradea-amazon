import 'package:flutter/foundation.dart';

import '../../catalog/data/catalog_repository.dart' show ProductSort;

/// A price window offered as a band.
///
/// Bands rather than a slider: a slider needs a maximum, and this catalogue has
/// none worth naming -- an industrial machine and a phone case sit in the same
/// index, so the handle would spend its whole range in the bottom pixel.
enum PriceBand {
  under500('Under Rs. 500', null, 500),
  midRange('Rs. 500 - 2,000', 500, 2000),
  upper('Rs. 2,000 - 10,000', 2000, 10000),
  over10k('Over Rs. 10,000', 10000, null);

  const PriceBand(this.label, this.low, this.high);

  final String label;
  final num? low;
  final num? high;
}

/// What a chip on the results page removes when it is dismissed.
enum FilterKind { department, category, price, priced }

/// One removable chip: what it says, and enough to undo exactly it.
@immutable
class ActiveFilter {
  const ActiveFilter({required this.kind, required this.label, this.band});

  final FilterKind kind;
  final String label;

  /// Set only for [FilterKind.price], because several price chips can be up at
  /// once and dismissing one must not clear the others.
  final PriceBand? band;
}

/// Everything narrowing the current search, and the query it turns into.
///
/// A value class rather than state scattered across the screen, for one reason
/// that matters here: **every field on it is something the server actually
/// honours**. The endpoint reads `q`, `category`, `min_price`, `max_price` and
/// `sort`, and silently returns 200 for anything else -- so a brand, size,
/// colour or rating control would look like it worked and quietly do nothing.
/// Confirmed by probing production, not by reading the handler.
///
/// It also means filtering is never done on the rows already fetched. The
/// server holds millions and returns a page; narrowing a page locally would
/// hide the rest and claim there was nothing more.
@immutable
class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.departmentCid,
    this.departmentName,
    this.categoryCid,
    this.categoryName,
    this.bands = const {},
    this.customMin,
    this.customMax,
    this.pricedOnly = false,
    this.sort = ProductSort.relevance,
  });

  /// What is being searched for, as `q`.
  ///
  /// Here rather than beside the results screen's other state, because the
  /// filter sheet offers a search box and had no way to hand one back. Keeping
  /// it on the same value class also means the screen's existing "did anything
  /// actually change" check covers the query -- retyping the same word is not a
  /// refetch.
  final String query;

  /// A top-level department -- Men, Women, Kids. The reference's "Gender" pill
  /// is this: the catalogue's first level really is gendered clothing, so the
  /// control is a real category filter rather than an invented attribute.
  final String? departmentCid;
  final String? departmentName;

  /// A subcategory inside [departmentCid]. Wins over the department when set,
  /// since it is the narrower of the two and the server takes one `category`.
  final String? categoryCid;
  final String? categoryName;

  final Set<PriceBand> bands;

  /// A range typed by hand, in rupees. Either end may be null for "no bound".
  ///
  /// Mutually exclusive with [bands], and enforced in [withCustomRange] and
  /// [withBands] rather than left to the sheet: one price rule is ever in
  /// force, so the two controls can never disagree about what is being asked
  /// for. The bands remain because one tap is a better answer to "show me the
  /// cheap ones" than two typed numbers.
  final num? customMin;
  final num? customMax;

  bool get hasCustomRange => customMin != null || customMax != null;

  /// Hides rows the catalogue has not priced yet.
  ///
  /// The nearest honest thing to an availability filter. Roughly half the feed
  /// comes back with `display_price: null` -- real listings whose pricing has
  /// not been worked out -- and they cannot be bought as they stand. Server
  /// side via `min_price=1`, which was measured to drop exactly those rows.
  final bool pricedOnly;

  final ProductSort sort;

  bool get isEmpty =>
      departmentCid == null &&
      categoryCid == null &&
      bands.isEmpty &&
      !hasCustomRange &&
      !pricedOnly;

  /// How many narrowing choices are up. Sort is excluded deliberately: it
  /// reorders results rather than removing any, so counting it would make
  /// "Filters (1)" appear over an unfiltered page.
  int get count =>
      (departmentCid != null ? 1 : 0) +
      (categoryCid != null ? 1 : 0) +
      bands.length +
      (hasCustomRange ? 1 : 0) +
      (pricedOnly ? 1 : 0);

  /// The union of the selected bands.
  ///
  /// A union, not an intersection: picking "Under Rs. 500" and "Over Rs.
  /// 10,000" means someone wants to see both ends, and intersecting them
  /// returns nothing at all.
  (num?, num?) get priceWindow {
    // A typed range wins outright rather than being merged with the bands.
    // Unioning the two would answer a question nobody asked: someone who typed
    // 500-800 over a "Under Rs. 500" chip means the numbers they typed.
    if (hasCustomRange) return (customMin, customMax);
    if (bands.isEmpty) return (null, null);

    num lowest = double.infinity;
    num highest = 0;
    var unbounded = false;

    for (final band in bands) {
      final low = band.low ?? 0;
      if (low < lowest) lowest = low;
      if (band.high == null) {
        unbounded = true;
      } else if (band.high! > highest) {
        highest = band.high!;
      }
    }

    return (lowest <= 0 ? null : lowest, unbounded ? null : highest);
  }

  /// The `min_price` to send, folding [pricedOnly] into the band floor.
  ///
  /// One parameter has to carry both, so the tighter of the two wins. A band
  /// starting at 500 already excludes the unpriced rows, which is why this is
  /// a max rather than an either/or.
  num? get minPrice {
    final (low, _) = priceWindow;
    if (!pricedOnly) return low;
    if (low == null) return 1;
    return low > 1 ? low : 1;
  }

  num? get maxPrice => priceWindow.$2;

  /// The single category the request carries. The narrower wins.
  String? get effectiveCategoryCid => categoryCid ?? departmentCid;

  /// The chips shown above the results, in the order they were applied.
  List<ActiveFilter> get chips => [
    if (departmentName != null)
      ActiveFilter(kind: FilterKind.department, label: departmentName!),
    if (categoryName != null)
      ActiveFilter(kind: FilterKind.category, label: categoryName!),
    // Ordered by the enum rather than by the set, so the chips do not
    // reshuffle themselves each time one is added.
    for (final band in PriceBand.values)
      if (bands.contains(band))
        ActiveFilter(kind: FilterKind.price, label: band.label, band: band),
    // One chip for the typed range, with no band on it -- which is exactly how
    // [without] tells it apart from a band chip and removes the right one.
    if (hasCustomRange)
      ActiveFilter(kind: FilterKind.price, label: customRangeLabel),
    if (pricedOnly)
      const ActiveFilter(kind: FilterKind.priced, label: 'Priced items'),
  ];

  /// How the typed range reads on its chip.
  ///
  /// Says which end is open rather than printing a bound nobody set: "Over Rs.
  /// 500" is true, "Rs. 500 - " is a chip with a hole in it.
  String get customRangeLabel {
    final min = customMin;
    final max = customMax;
    if (min != null && max != null) {
      return 'Rs. ${_plain(min)} - ${_plain(max)}';
    }
    if (min != null) return 'Over Rs. ${_plain(min)}';
    return 'Under Rs. ${_plain(max!)}';
  }

  /// Whole rupees, with no trailing `.0`. These are numbers somebody typed.
  static String _plain(num value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  /// This selection without one chip.
  ///
  /// Dropping a department drops its subcategory too: a child category left
  /// behind on its own would keep narrowing to a department the shopper just
  /// said they no longer wanted, and no chip on screen would explain why.
  SearchFilters without(ActiveFilter filter) => switch (filter.kind) {
    FilterKind.department => withDepartment(null, null),
    FilterKind.category => withCategory(null, null),
    // A price chip carrying no band is the typed range, which is cleared whole
    // -- there is no half of a range to keep.
    FilterKind.price =>
      filter.band == null
          ? withCustomRange(min: null, max: null)
          : withBands({...bands}..remove(filter.band)),
    FilterKind.priced => withPricedOnly(false),
  };

  /// Everything cleared but the sort, which is not a filter and is not what
  /// "clear filters" means to anyone pressing it.
  ///
  /// **The query survives too**, and that is not an oversight. "Clear all" sits
  /// under a row of chips and means "drop these"; the query is not one of them,
  /// it is the words still sitting in the search box above. Emptying that box
  /// from a button the shopper pressed to tidy their filters would throw away
  /// what they came to look for. [withQuery] is how the query is cleared, and
  /// the search box is where anyone would go to do it.
  SearchFilters get cleared => SearchFilters(query: query, sort: sort);

  /// There is deliberately no general `copyWith`. Four of the fields are
  /// nullable ids, and the usual `String? foo` signature cannot tell "leave it
  /// alone" from "clear it" -- so `copyWith(bands: ...)` would silently drop
  /// the selected department. Each change gets a named method instead.
  SearchFilters withSort(ProductSort sort) => SearchFilters(
    query: query,
    departmentCid: departmentCid,
    departmentName: departmentName,
    categoryCid: categoryCid,
    categoryName: categoryName,
    bands: bands,
    customMin: customMin,
    customMax: customMax,
    pricedOnly: pricedOnly,
    sort: sort,
  );

  SearchFilters withQuery(String value) => SearchFilters(
    query: value.trim(),
    departmentCid: departmentCid,
    departmentName: departmentName,
    categoryCid: categoryCid,
    categoryName: categoryName,
    bands: bands,
    customMin: customMin,
    customMax: customMax,
    pricedOnly: pricedOnly,
    sort: sort,
  );

  /// Picking bands drops any typed range, so only one price rule is in force.
  SearchFilters withBands(Set<PriceBand> bands) => SearchFilters(
    query: query,
    departmentCid: departmentCid,
    departmentName: departmentName,
    categoryCid: categoryCid,
    categoryName: categoryName,
    bands: bands,
    pricedOnly: pricedOnly,
    sort: sort,
  );

  /// A range typed by hand, which drops any selected bands for the same reason.
  ///
  /// Everything here is guarded, because these are two boxes a person types
  /// into and every one of these cases has happened to somebody:
  ///
  ///   * a blank box means "no bound", not zero -- a zero floor would quietly
  ///     turn "under 500" into "0 to 500", which is the same thing until the
  ///     day the server treats 0 as a real filter;
  ///   * a negative number is dropped rather than sent, since no price is
  ///     below nothing;
  ///   * a min above a max is **swapped** rather than passed on. Sending
  ///     `min=800&max=500` is a window nothing can sit in, and an empty grid is
  ///     a worse answer than the range they plainly meant.
  SearchFilters withCustomRange({required num? min, required num? max}) {
    var low = (min != null && min >= 0) ? min : null;
    var high = (max != null && max >= 0) ? max : null;
    if (low != null && high != null && low > high) {
      final swap = low;
      low = high;
      high = swap;
    }

    return SearchFilters(
      query: query,
      departmentCid: departmentCid,
      departmentName: departmentName,
      categoryCid: categoryCid,
      categoryName: categoryName,
      customMin: low,
      customMax: high,
      pricedOnly: pricedOnly,
      sort: sort,
    );
  }

  SearchFilters withPricedOnly(bool value) => SearchFilters(
    query: query,
    departmentCid: departmentCid,
    departmentName: departmentName,
    categoryCid: categoryCid,
    categoryName: categoryName,
    bands: bands,
    customMin: customMin,
    customMax: customMax,
    pricedOnly: value,
    sort: sort,
  );

  /// Picking a department clears any subcategory beneath the old one, which
  /// would otherwise keep filtering to a department no longer selected.
  SearchFilters withDepartment(String? cid, String? name) => SearchFilters(
    query: query,
    departmentCid: cid,
    departmentName: name,
    bands: bands,
    customMin: customMin,
    customMax: customMax,
    pricedOnly: pricedOnly,
    sort: sort,
  );

  SearchFilters withCategory(String? cid, String? name) => SearchFilters(
    query: query,
    departmentCid: departmentCid,
    departmentName: departmentName,
    categoryCid: cid,
    categoryName: name,
    bands: bands,
    customMin: customMin,
    customMax: customMax,
    pricedOnly: pricedOnly,
    sort: sort,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.query == query &&
      other.departmentCid == departmentCid &&
      other.categoryCid == categoryCid &&
      setEquals(other.bands, bands) &&
      other.customMin == customMin &&
      other.customMax == customMax &&
      other.pricedOnly == pricedOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    query,
    departmentCid,
    categoryCid,
    Object.hashAllUnordered(bands),
    customMin,
    customMax,
    pricedOnly,
    sort,
  );
}

/// The sorts offered on the results page.
///
/// Not every [ProductSort] the app knows: `sort=rating` was measured returning
/// an empty array from production, and every row in this catalogue has
/// `rating: null`, so a "Best rated" option would be a control that reliably
/// finds nothing. Offering it would be worse than leaving it out.
const kSearchSorts = <ProductSort>[
  ProductSort.relevance,
  ProductSort.sales,
  ProductSort.priceAsc,
  ProductSort.priceDesc,
  ProductSort.newest,
];

/// The attributes shoppers ask for that this catalogue does not publish.
///
/// Named here so the filter sheet can say so plainly rather than leaving a
/// shopper hunting for a size control that was never going to appear. The rows
/// carry no brand, size, colour, stock level, list price or rating -- and the
/// endpoint answers 200 to a `brand=` or `in_stock=` parameter while ignoring
/// it, which is exactly why guessing is not safe here.
const kUnsupportedFacets =
    'Brand, size and colour aren\'t published '
    'for these listings yet.';

/// The minimum-rating tiers the sheet shows, best first.
///
/// **Shown, and deliberately not selectable.** Measured against production
/// rather than assumed, twice over:
///
///   * every row carries `rating: null` -- 190 of them, across
///     `/feed/discover` and `/search/products`, sampled from the top of the
///     feed to four thousand rows deep;
///   * `/search/products` **ignores** `min_rating`. Sending it returns a
///     byte-identical list, so a control wired to it would look like it worked
///     and do nothing.
///
/// There is a `GET /api/v1/products` that does parse `min_rating`, and it
/// answers with an empty array -- that table holds no rows, and this catalogue
/// is served from the 1688 feed instead.
///
/// So the honest states are "absent" or "present and off". Present and off is
/// what was asked for: a shopper can see the filter is understood and is told
/// why it cannot be used, rather than hunting for a control that was never
/// going to appear. The day ratings arrive, this becomes a field on
/// [SearchFilters] and an `onSelected` on the chips.
const kRatingTiers = <int>[4, 3, 2, 1];

/// Why the rating chips cannot be pressed, in the sheet's own words.
const kRatingUnavailable =
    'These listings don\'t carry ratings yet, so this '
    'filter would find nothing. It turns on by itself once ratings arrive.';

/// Why the brand chips cannot be pressed.
///
/// The same story as [kRatingTiers], with its own measurements. `GET /brands`
/// is real and answers twenty-five active rows -- so the names on those chips
/// are the shop's own rather than invented -- but they belong to the shop's
/// products table, which answers `[]`. The catalogue actually sold from is the
/// 1688 feed, and:
///
///   * a row there carries **no brand field at all** -- `num_iid`, `title`,
///     `pic_url`, `price`, `sales`, `rating`, `category_cid`, `category_name`,
///     `parent_category_name`, `detail_url`, `display_price`,
///     `relevance_score`, and nothing else;
///   * `/search/products` returns a byte-identical list with and without
///     `brand=`.
///
/// So every brand would match every product or none, depending on which way the
/// server chose to ignore it. Shown and switched off is the only honest state.
const kBrandUnavailable =
    'These listings don\'t name a brand, so this filter '
    'would find nothing. It turns on by itself once brands arrive.';

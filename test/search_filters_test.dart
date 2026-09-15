import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/search/data/search_filters.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

late FakeApi api;

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _phone(WidgetTester tester, {Size size = const Size(1100, 2400)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Product _product({
  String id = '1',
  String title = 'A product',
  num? price = 300,
  int? sales,
  String? tradeScore,
}) {
  return Product(
    numIid: id,
    title: title,
    displayPrice: price,
    sales: sales,
    tradeScore: tradeScore,
  );
}

void main() {
  group('the price window', () {
    test('is nothing at all when no band is chosen', () {
      const filters = SearchFilters();
      expect(filters.minPrice, isNull);
      expect(filters.maxPrice, isNull);
    });

    test('is the band itself for one band', () {
      const filters = SearchFilters(bands: {PriceBand.midRange});
      expect(filters.minPrice, 500);
      expect(filters.maxPrice, 2000);
    });

    test('unions rather than intersects across bands', () {
      // Picking both ends means someone wants to see both ends. Intersecting
      // them returns nothing, which is not what either chip said.
      const filters = SearchFilters(
        bands: {PriceBand.under500, PriceBand.over10k},
      );
      expect(filters.minPrice, isNull, reason: 'the lower band has no floor');
      expect(filters.maxPrice, isNull, reason: 'the upper band has no ceiling');
    });

    test('an open-ended band removes the ceiling', () {
      const filters = SearchFilters(
        bands: {PriceBand.midRange, PriceBand.over10k},
      );
      expect(filters.minPrice, 500);
      expect(filters.maxPrice, isNull);
    });
  });

  group('priced-only', () {
    test('becomes a floor of one when no band is set', () {
      // min_price=1 is what the server honours; it was measured dropping
      // exactly the rows with a null display price.
      const filters = SearchFilters(pricedOnly: true);
      expect(filters.minPrice, 1);
      expect(filters.maxPrice, isNull);
    });

    test('yields to a band that already excludes the unpriced rows', () {
      // One parameter carries both, so the tighter floor has to win.
      const filters = SearchFilters(
        pricedOnly: true,
        bands: {PriceBand.midRange},
      );
      expect(filters.minPrice, 500);
    });

    test('still floors at one under a band with no floor of its own', () {
      const filters = SearchFilters(
        pricedOnly: true,
        bands: {PriceBand.under500},
      );
      expect(filters.minPrice, 1);
      expect(filters.maxPrice, 500);
    });
  });

  group('the category sent', () {
    test('is the department when only a department is chosen', () {
      const filters = SearchFilters(departmentCid: 'dept-1');
      expect(filters.effectiveCategoryCid, 'dept-1');
    });

    test('is the subcategory when there is one, being the narrower', () {
      const filters = SearchFilters(
        departmentCid: 'dept-1',
        categoryCid: 'dept-1-child-0',
      );
      expect(filters.effectiveCategoryCid, 'dept-1-child-0');
    });
  });

  group('removing a chip', () {
    test('takes the subcategory with the department', () {
      // A child left behind would keep narrowing to a department the shopper
      // just removed, with no chip on screen explaining why.
      const filters = SearchFilters(
        departmentCid: 'dept-1',
        departmentName: 'Men',
        categoryCid: 'child-0',
        categoryName: 'Shirts',
      );
      final after = filters.without(filters.chips.first);

      expect(after.departmentCid, isNull);
      expect(after.categoryCid, isNull);
      expect(after.isEmpty, isTrue);
    });

    test('removes only the one price band it names', () {
      const filters = SearchFilters(
        bands: {PriceBand.under500, PriceBand.over10k},
      );
      final chip = filters.chips.firstWhere(
        (c) => c.band == PriceBand.under500,
      );
      final after = filters.without(chip);

      expect(after.bands, {PriceBand.over10k});
    });

    test('leaves the other filters alone', () {
      const filters = SearchFilters(
        departmentCid: 'dept-1',
        departmentName: 'Men',
        bands: {PriceBand.midRange},
        pricedOnly: true,
      );
      final chip = filters.chips.firstWhere((c) => c.kind == FilterKind.priced);
      final after = filters.without(chip);

      expect(after.pricedOnly, isFalse);
      expect(after.departmentCid, 'dept-1', reason: 'not collateral damage');
      expect(after.bands, {PriceBand.midRange});
    });
  });

  group('clearing', () {
    test('keeps the sort, which is not a filter', () {
      // Nobody pressing "clear filters" means "and put the ordering back".
      const filters = SearchFilters(
        departmentCid: 'dept-1',
        bands: {PriceBand.midRange},
        sort: ProductSort.priceAsc,
      );
      final after = filters.cleared;

      expect(after.isEmpty, isTrue);
      expect(after.sort, ProductSort.priceAsc);
    });

    test('and the count never includes it', () {
      const sorted = SearchFilters(sort: ProductSort.priceDesc);
      expect(sorted.count, 0, reason: '"Filters (1)" over an unfiltered page');
    });
  });

  group('a typed price range', () {
    test('is what the request carries, over any band', () {
      // Someone who typed 500-800 over a "Under Rs. 500" chip means the numbers
      // they typed. Unioning the two would answer a question nobody asked.
      const banded = SearchFilters(bands: {PriceBand.under500});
      final typed = banded.withCustomRange(min: 500, max: 800);

      expect(typed.minPrice, 500);
      expect(typed.maxPrice, 800);
      expect(typed.bands, isEmpty, reason: 'one price rule is ever in force');
    });

    test('and picking a band drops it, so the two cannot disagree', () {
      final typed = const SearchFilters().withCustomRange(min: 500, max: 800);
      final banded = typed.withBands({PriceBand.over10k});

      expect(banded.hasCustomRange, isFalse);
      expect(banded.minPrice, 10000);
    });

    test('an empty box is no bound, not zero', () {
      // A zero floor reads as a real filter the day the server starts treating
      // it as one, and "under 500" would quietly have become "0 to 500".
      final onlyMax = const SearchFilters().withCustomRange(
        min: null,
        max: 800,
      );
      expect(onlyMax.minPrice, isNull);
      expect(onlyMax.maxPrice, 800);

      final onlyMin = const SearchFilters().withCustomRange(
        min: 500,
        max: null,
      );
      expect(onlyMin.minPrice, 500);
      expect(onlyMin.maxPrice, isNull);
    });

    test('a negative bound is dropped rather than sent', () {
      final filters = const SearchFilters().withCustomRange(min: -5, max: 800);
      expect(filters.minPrice, isNull);
      expect(filters.maxPrice, 800);
    });

    test('an inverted range is swapped, not sent as an empty window', () {
      // min=800&max=500 is a window nothing can sit in. An empty grid is a
      // worse answer than the range they plainly meant.
      final filters = const SearchFilters().withCustomRange(min: 800, max: 500);
      expect(filters.minPrice, 500);
      expect(filters.maxPrice, 800);
    });

    test('is one chip, and dismissing it leaves the others up', () {
      final filters = const SearchFilters(
        departmentCid: '18',
        departmentName: 'Sports Outdoors',
        pricedOnly: true,
      ).withCustomRange(min: 500, max: 800);

      final price = filters.chips.where((c) => c.kind == FilterKind.price);
      expect(price, hasLength(1));
      expect(price.first.label, 'Rs. 500 - 800');
      expect(
        price.first.band,
        isNull,
        reason: 'what marks it as the typed one',
      );

      final after = filters.without(price.first);
      expect(after.hasCustomRange, isFalse);
      expect(after.departmentCid, '18');
      expect(after.pricedOnly, isTrue);
    });

    test('says which end is open when only one is set', () {
      final over = const SearchFilters().withCustomRange(min: 500, max: null);
      final under = const SearchFilters().withCustomRange(min: null, max: 800);

      expect(over.customRangeLabel, 'Over Rs. 500');
      expect(under.customRangeLabel, 'Under Rs. 800');
    });

    test('counts as one filter', () {
      final filters = const SearchFilters().withCustomRange(min: 500, max: 800);
      expect(filters.count, 1);
      expect(filters.isEmpty, isFalse);
    });
  });

  group('the query', () {
    test('rides on the filters, so retyping the same word is not a refetch', () {
      // The screen re-runs on `filters != _filters`. The query is on the value
      // class precisely so that check covers it.
      const a = SearchFilters(query: 'bag');
      const b = SearchFilters(query: 'bag');
      expect(a, b);
      expect(const SearchFilters(query: 'shoe'), isNot(a));
    });

    test('is trimmed on the way in', () {
      expect(const SearchFilters().withQuery('  bag  ').query, 'bag');
    });

    test('survives Clear all, because it is not one of the chips', () {
      // "Clear all" sits under a row of chips and means "drop these". The query
      // is the words still in the search box above them; emptying that from a
      // button pressed to tidy filters would throw away what they came for.
      final filters = const SearchFilters(
        query: 'leather bag',
        departmentCid: '18',
        departmentName: 'Sports Outdoors',
      ).withCustomRange(min: 500, max: 800);

      final cleared = filters.cleared;
      expect(cleared.query, 'leather bag');
      expect(cleared.isEmpty, isTrue);
      expect(cleared.hasCustomRange, isFalse);
      expect(cleared.departmentCid, isNull);
    });

    test('and is not counted as a filter chip', () {
      const filters = SearchFilters(query: 'bag');
      expect(filters.count, 0);
      expect(filters.isEmpty, isTrue);
      expect(filters.chips, isEmpty);
    });
  });

  group('the rating tiers', () {
    test('are offered as four, best first', () {
      expect(kRatingTiers, [4, 3, 2, 1]);
    });

    test('and the reason they cannot be used says so plainly', () {
      // The one control on the sheet that does nothing. If it is ever wired up,
      // it has to be because the catalogue started publishing ratings -- this
      // string is what has to stop being true first.
      expect(kRatingUnavailable, contains('ratings'));
      expect(kRatingUnavailable.toLowerCase(), contains('nothing'));
    });

    test('and brand says the same thing, for its own measured reason', () {
      // /brands answers 25 active rows, so the chips carry the shop's real
      // names -- but no listing in the catalogue names a brand and the search
      // endpoint ignores `brand=`. Shown and switched off is the only honest
      // state, exactly as for rating.
      expect(kBrandUnavailable.toLowerCase(), contains('brand'));
      expect(kBrandUnavailable.toLowerCase(), contains('nothing'));
    });

    test('and rating is no longer lumped in with the unpublished facets', () {
      // It has a section of its own now, which says it in the place it matters.
      expect(kUnsupportedFacets.toLowerCase(), isNot(contains('rating')));
      expect(kUnsupportedFacets.toLowerCase(), contains('brand'));
    });
  });

  group('the sorts offered', () {
    test('include no rating option', () {
      // `sort=rating` was measured returning an empty array from production,
      // and every row in this catalogue has a null rating. A "Best rated"
      // control that reliably finds nothing is worse than no control -- so if
      // one is ever added to ProductSort, it must not reach this list by
      // default.
      for (final sort in kSearchSorts) {
        expect(sort.label.toLowerCase(), isNot(contains('rat')));
        expect(sort.wire, isNot('rating'));
      }
      expect(kSearchSorts, contains(ProductSort.relevance));
      expect(kSearchSorts, contains(ProductSort.priceAsc));
      expect(kSearchSorts, contains(ProductSort.newest));
    });
  });

  group('the result card', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      api = stubCatalog();
    });

    testWidgets('says "price on request" rather than Rs. 0', (tester) async {
      // Roughly half the feed comes back unpriced. They are real products, and
      // a zero would be a lie about one.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: SizedBox(
              width: 190,
              child: ProductResultCard(product: _product(price: null)),
            ),
          ),
        ),
      );

      expect(find.text('Price on request'), findsOneWidget);
      expect(find.text('Rs. 0'), findsNothing);
    });

    testWidgets('offers no add-to-cart at an unknown price', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: SizedBox(
              width: 190,
              child: ProductResultCard(
                product: _product(price: null),
                onAddToCart: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Add to cart'), findsNothing);
    });

    testWidgets('badges what the sales figure actually supports', (
      tester,
    ) async {
      _phone(tester, size: const Size(1600, 2400));
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 190,
                  child: ProductResultCard(product: _product(sales: 15000)),
                ),
                SizedBox(
                  width: 190,
                  child: ProductResultCard(
                    product: _product(id: '2', sales: 2000),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: ProductResultCard(
                    product: _product(id: '3', sales: 3),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Best Seller'), findsOneWidget);
      expect(find.text('Popular'), findsOneWidget);
      // Three sales is not a badge. Inventing one would make the label mean
      // nothing on the cards that earned it.
      expect(find.byType(ProductResultCard), findsNWidgets(3));
    });

    testWidgets('names whose score it is showing', (tester) async {
      // Unlabelled, this reads as a product rating -- the one thing this
      // catalogue cannot tell anyone.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: SizedBox(
              width: 190,
              child: ProductResultCard(product: _product(tradeScore: '4.9')),
            ),
          ),
        ),
      );

      expect(find.text('4.9'), findsOneWidget);
      expect(find.text('seller'), findsOneWidget);
    });

    testWidgets('fits the height the grid reserves for it, at any text scale', (
      tester,
    ) async {
      // The grid asks the card how tall it is. If the two ever disagree the
      // cards clip, which is exactly what an aspect ratio guess did.
      for (final scale in [1.0, 1.6, 2.0]) {
        _phone(tester);
        await tester.pumpWidget(
          _wrap(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Builder(
                  builder: (context) => SizedBox(
                    width: 190,
                    height: ProductResultCard.heightFor(context, 190),
                    child: ProductResultCard(
                      product: _product(
                        title:
                            'A title long enough to need both of its lines '
                            'and then some more beyond that',
                        sales: 15000,
                        tradeScore: '4.9',
                      ),
                      onAddToCart: () {},
                      onToggleSaved: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'clipped at $scale x');
      }
    });
  });

  group('the results grid', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      api = stubCatalog();
    });

    testWidgets('gets more columns as the window widens', (tester) async {
      // Columns come from the width a card wants, not from named device sizes,
      // so a split-screen tablet gets the layout that fits.
      expect(ProductResultCard.columnsFor(390), 2);
      expect(ProductResultCard.columnsFor(800), 4);
      expect(ProductResultCard.columnsFor(1400), 6);
      // Never one, however narrow: a single column of these is a list with the
      // wrong card in it.
      expect(ProductResultCard.columnsFor(200), 2);
    });

    test('search sizes its cards for looking at, on every width', () {
      // Phone: two columns, tight gaps, thin padding so the picture is big.
      final phone = ResultGridSpec.search(364);
      expect(phone.columns, 2);
      expect(phone.gap, 8);
      expect(phone.cardPadding, 6);
      expect(phone.cardWidth(364), greaterThan(175));

      // Tablet: more columns, but each card still wider than the standard.
      final tablet = ResultGridSpec.search(776);
      expect(tablet.columns, 3);
      expect(
        tablet.cardWidth(776),
        greaterThan(ResultGridSpec.standard(776).cardWidth(776)),
      );

      // Desktop: bigger cards rather than more of them, and never a sprawl.
      final desktop = ResultGridSpec.search(1358);
      expect(desktop.columns, 5);
      expect(desktop.cardWidth(1358), greaterThan(240));
      expect(ResultGridSpec.search(3000).columns, 6);
    });

    test('the standard grid the other sections use is unchanged', () {
      final spec = ResultGridSpec.standard(800);
      expect(spec.columns, ProductResultCard.columnsFor(800));
      expect(spec.gap, ProductResultCard.gridGap);
      expect(spec.cardWidth(800), ProductResultCard.widthFor(800));
    });

    testWidgets('lays out without overflowing on a narrow phone', (
      tester,
    ) async {
      _phone(tester, size: const Size(720, 1400));
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();

      expect(find.byType(ProductResultCard), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

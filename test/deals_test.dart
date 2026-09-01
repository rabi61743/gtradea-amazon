import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/deals/data/deals_repository.dart';
import 'package:gtradea_amazon/features/deals/presentation/deals_screen.dart';
import 'package:gtradea_amazon/features/flash_sale/data/flash_sale_placeholder.dart'
    as placeholder;
import 'package:gtradea_amazon/features/flash_sale/data/flash_sale_repository.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/flash_deal_card.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/sale_countdown.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

late FakeApi api;

/// A window tall enough that the grid is built, and wide enough that the
/// whole discount strip is on screen -- the chips scroll horizontally, so a
/// narrow harness hides the bands the tests need to tap.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// The query parameters of the most recent search request.
Map<String, dynamic> lastSearch() =>
    api.calls.lastWhere((c) => c.path == '/search/products').query;

int searchCount() =>
    api.calls.where((c) => c.path == '/search/products').length;

/// Catalogue rows with prices, and ids the placeholder will hash predictably.
List<Map<String, dynamic>> rows(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++)
    {
      'num_iid': 'deal-$i',
      'title': 'Deal product $i',
      'display_price': 500 + i,
      'category_cid': '10166',
      'category_name': 'Women',
    },
];

/// Taps a discount chip, scrolling the strip to it first.
///
/// The bands scroll horizontally, so the later ones are off-screen on any
/// realistic window -- which is the point of the strip, and something the test
/// should go through rather than around.
Future<void> tapBand(WidgetTester tester, String label) async {
  final chip = find.text(label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> pumpDeals(WidgetTester tester) async {
  _tall(tester);
  await tester.pumpWidget(_wrap(const DealsScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    api.on('GET', '/search/products', body: rows(24));
  });

  group('what it asks the server for', () {
    testWidgets('opens on best sellers, with no price ceiling', (tester) async {
      await pumpDeals(tester);

      final query = lastSearch();
      expect(query['sort'], 'sales');
      expect(query['page_size'], isNotNull);
      // A floor of 1, always. `sort=price_asc` puts the "price on request"
      // rows first -- hundreds of nulls -- and every one is dropped below as
      // unpriced, so without this the cheapest-first sort returns an empty
      // page. `min_price` is a filter the server genuinely applies.
      expect(query['min_price'], 1);
      // No ceiling until the shopper sets one.
      expect(query.containsKey('max_price'), isFalse);
    });

    testWidgets('sorting cheapest-first still finds priced products', (
      tester,
    ) async {
      // Found on the device: this combination showed "nothing matches these
      // filters" because every row the server returned first was unpriced.
      await pumpDeals(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Best selling'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: low to high'));
      await tester.pumpAndSettle();

      expect(lastSearch()['sort'], 'price_asc');
      expect(lastSearch()['min_price'], 1);
      expect(find.byType(FlashDealCard), findsWidgets);
    });

    testWidgets('a price band becomes a real server filter', (tester) async {
      await pumpDeals(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rs. 500 - 2,000'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Show'));
      await tester.pumpAndSettle();

      expect(lastSearch()['min_price'], 500);
      expect(lastSearch()['max_price'], 2000);
    });

    testWidgets('an open-ended band leaves that end off', (tester) async {
      await pumpDeals(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Over Rs. 10,000'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Show'));
      await tester.pumpAndSettle();

      expect(lastSearch()['min_price'], 10000);
      // A ceiling here would exclude exactly the products the band is for.
      expect(lastSearch().containsKey('max_price'), isFalse);
    });

    testWidgets('changing the sort re-asks rather than reordering locally', (
      tester,
    ) async {
      await pumpDeals(tester);
      final before = searchCount();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Best selling'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: low to high'));
      await tester.pumpAndSettle();

      expect(searchCount(), greaterThan(before));
      expect(lastSearch()['sort'], 'price_asc');
    });

    testWidgets('choosing the sort already in use asks for nothing', (
      tester,
    ) async {
      await pumpDeals(tester);
      final before = searchCount();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Best selling'));
      await tester.pumpAndSettle();
      // .last is the sheet's option; .first is the sort button that opened it.
      await tester.tap(find.text('Best selling').last);
      await tester.pumpAndSettle();

      expect(searchCount(), before, reason: 'nothing was re-fetched');
    });
  });

  group('paging', () {
    testWidgets('scrolling to the end asks for the next rows', (tester) async {
      await pumpDeals(tester);

      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();

      // Offset advances by rows read, not by cards shown.
      expect(lastSearch()['page_offset'], 24);
    });

    testWidgets('a row that comes back twice is only shown once', (
      tester,
    ) async {
      // The catalogue does repeat rows across pages.
      api.on('GET', '/search/products', body: rows(24));
      await pumpDeals(tester);
      final before = tester.widgetList(find.byType(FlashDealCard)).length;

      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();

      expect(tester.widgetList(find.byType(FlashDealCard)).length, before);
    });
  });

  group('the discount band', () {
    testWidgets('drops everything under it', (tester) async {
      await pumpDeals(tester);

      await tapBand(tester, '50% and over');

      final shown = tester.widgetList<FlashDealCard>(
        find.byType(FlashDealCard),
      );
      expect(shown, isNotEmpty);
      for (final card in shown) {
        expect(card.item.discountPercent, greaterThanOrEqualTo(50));
      }
    });

    testWidgets(
      'keeps fetching to fill the page rather than returning a stub',
      (tester) async {
        // A band that rejects most rows would leave two cards on screen if the
        // repository handed back whatever survived one request.
        await pumpDeals(tester);
        final before = searchCount();

        await tapBand(tester, '50% and over');

        expect(
          searchCount(),
          greaterThan(before + 1),
          reason: 'it went back for more',
        );
      },
    );

    test('advances the offset by rows read, not by rows kept', () async {
      api.on('GET', '/search/products', body: rows(24));

      final page = await DealsRepository.instance.page(minDiscount: 50);

      // Paging by the kept count would re-read the rejected rows forever.
      expect(page.rowsConsumed, greaterThan(page.items.length));
      expect(page.rowsConsumed % 24, 0);
    });

    test('a short answer is the end of the catalogue', () async {
      api.on('GET', '/search/products', body: rows(5));

      final page = await DealsRepository.instance.page();
      expect(page.hasMore, isFalse);
      expect(page.filterCutShort, isFalse);
    });

    test('stopping on the round-trip budget is not the end', () async {
      // Every row full-price, so the band rejects all of them and the fetch
      // runs out of budget rather than out of catalogue.
      api.on('GET', '/search/products', body: rows(24));

      final page = await DealsRepository.instance.page(minDiscount: 99);

      expect(page.items, isEmpty);
      expect(page.hasMore, isTrue);
      // The difference matters: one means "that is everything", the other
      // means "there is more, we stopped looking".
      expect(page.filterCutShort, isTrue);
    });

    test('a row with no price is never a deal', () async {
      api.on(
        'GET',
        '/search/products',
        body: [
          {'num_iid': 'a', 'title': 'Priced', 'display_price': 500},
          {'num_iid': 'b', 'title': 'Price on request'},
        ],
      );

      final page = await DealsRepository.instance.page();
      expect(page.items.map((i) => i.product.numIid), ['a']);
    });
  });

  group('failing', () {
    testWidgets('a first page that fails says so and offers a retry', (
      tester,
    ) async {
      api.on(
        'GET',
        '/search/products',
        status: 500,
        body: {'error': 'deals are down'},
      );

      await pumpDeals(tester);

      expect(find.text('deals are down'), findsOneWidget);
      expect(find.text('Try again'), findsWidgets);
    });

    testWidgets('a later page that fails leaves the good rows alone', (
      tester,
    ) async {
      await pumpDeals(tester);
      expect(find.byType(FlashDealCard), findsWidgets);

      api.on(
        'GET',
        '/search/products',
        status: 500,
        body: {'error': 'page two is down'},
      );
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();

      // Replacing a screen of good deals with an error because page four
      // failed would undermine them.
      expect(find.byType(FlashDealCard), findsWidgets);
      expect(find.text('page two is down'), findsNothing);
    });

    testWidgets('an empty catalogue says so rather than spinning', (
      tester,
    ) async {
      api.on('GET', '/search/products', body: const []);

      await pumpDeals(tester);

      expect(find.text('No deals just now'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('filtered to nothing offers a way back', (tester) async {
      await pumpDeals(tester);
      api.on('GET', '/search/products', body: const []);

      await tapBand(tester, '40% and over');

      expect(find.text('Nothing matches these filters'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(lastSearch(), isNotNull);
    });
  });

  group('the cards', () {
    testWidgets('every card opens its own product', (tester) async {
      await pumpDeals(tester);

      final first = tester
          .widgetList<FlashDealCard>(find.byType(FlashDealCard))
          .elementAt(1);
      await tester.tap(find.byWidget(first));
      await tester.pumpAndSettle();

      final opened = tester.widget<ProductDetailScreen>(
        find.byType(ProductDetailScreen),
      );
      expect(opened.product.numIid, first.item.product.numIid);
    });

    testWidgets('the saving is stated in rupees, not left as arithmetic', (
      tester,
    ) async {
      await pumpDeals(tester);

      final card = tester
          .widgetList<FlashDealCard>(find.byType(FlashDealCard))
          .first;
      final saving = card.item.listPrice - card.item.salePrice;
      expect(saving, greaterThan(0));

      expect(find.textContaining('Save Rs.'), findsWidgets);
      expect(
        find.textContaining('-${card.item.discountPercent}%'),
        findsWidgets,
      );
    });
  });

  group('pricing is shared with the flash sale', () {
    test('the two surfaces price the same product identically', () async {
      // The home page section and this screen show the same catalogue rows. A
      // shopper who sees Rs. 2,999 on the home page and something else one tap
      // later has been told two different things about one item -- so both go
      // through dealPricing rather than each doing their own arithmetic.
      api.on('GET', '/search/products', body: rows(4));
      api.on('GET', '/feed/discover', body: rows(4));
      CatalogStore.instance.resetForTest();

      final deals = await DealsRepository.instance.page();
      final sale = await FlashSaleRepository.instance.current();

      expect(sale, isNotNull);
      final onHome = sale!.items.first;
      final onDeals = deals.items.firstWhere(
        (i) => i.product.numIid == onHome.product.numIid,
      );

      expect(onDeals.salePrice, onHome.salePrice);
      expect(onDeals.listPrice, onHome.listPrice);
      expect(onDeals.discountPercent, onHome.discountPercent);
    });

    test('the discount is stable for a product, not per request', () async {
      api.on('GET', '/search/products', body: rows(4));

      final first = await DealsRepository.instance.page();
      final second = await DealsRepository.instance.page();

      expect(
        first.items.first.discountPercent,
        placeholder.discountFor('deal-0'),
      );
      // A discount that changed between the grid and a refresh would look like
      // the price moving while you watched it.
      expect(
        second.items.first.discountPercent,
        first.items.first.discountPercent,
      );
    });
  });

  group('the sale deadline it was opened from', () {
    testWidgets('carries the clock onto the page the clock sent you to', (
      tester,
    ) async {
      // The gap this closes: a shopper taps a card whose whole point is a
      // countdown, and lands on a grid that never mentions the deadline again.
      _tall(tester);
      await pumpDeals(tester);
      await tester.pumpAndSettle();

      expect(find.text('Flash Sales'), findsOneWidget);
      expect(find.byType(SaleCountdown), findsOneWidget);
    });

    testWidgets('asks for the sale itself rather than assuming it is loaded', (
      tester,
    ) async {
      // This screen opens from a department and from the home page, and only
      // one of those has already fetched the sale.
      CatalogStore.instance.resetForTest();
      _tall(tester);
      await pumpDeals(tester);
      await tester.pumpAndSettle();

      expect(CatalogStore.instance.flashSale.value, isNotNull);
      expect(find.byType(SaleCountdown), findsOneWidget);
    });

    testWidgets('says nothing when no sale is running', (tester) async {
      // "Deals" is also where Shop All Deals goes, and most of the time there
      // is no flash sale at all. A header with a dead clock would be worse than
      // no header.
      CatalogStore.instance.resetForTest();
      api.on('GET', '/feed/discover', body: <Map<String, dynamic>>[]);
      _tall(tester);
      await pumpDeals(tester);
      await tester.pumpAndSettle();

      expect(find.text('Flash Sales'), findsNothing);
      expect(find.byType(SaleCountdown), findsNothing);
    });

    testWidgets('pulling down re-reads the deals', (tester) async {
      // Prices and stock move under a sale, and the only way to re-read them
      // was to leave the screen and come back.
      _tall(tester);
      await pumpDeals(tester);
      final before = searchCount();

      // Dragged from the middle of the scroll view the indicator is wrapped
      // around. A drag aimed at the grid starts on a tile near the top of a
      // very tall harness window and never travels far enough to arm it.
      final scroller = find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.dragFrom(tester.getCenter(scroller), const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(searchCount(), greaterThan(before));
    });
  });
}

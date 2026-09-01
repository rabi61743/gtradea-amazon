import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/flash_sale/data/flash_sale.dart';
import 'package:gtradea_amazon/features/flash_sale/data/flash_sale_placeholder.dart'
    as placeholder;
import 'package:gtradea_amazon/features/flash_sale/data/flash_sale_repository.dart';
import 'package:gtradea_amazon/features/deals/presentation/deal_grid.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/flash_deal_card.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/flash_deal_tile.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/flash_sale_section.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/sale_countdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

/// A card at the width the grid actually gives it. Handed the whole window it
/// would draw a square photo as tall as the screen, which is a property of the
/// harness rather than of the card.
Widget _card(FlashSaleItem item) => _wrap(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: 180, child: FlashDealCard(item: item)),
  ),
);

Product _product(String id, {num price = 1000}) =>
    Product(numIid: id, title: 'Product $id', displayPrice: price);

FlashSaleItem _item(
  String id, {
  num sale = 600,
  num list = 1000,
  int off = 40,
}) => FlashSaleItem(
  product: _product(id),
  salePrice: sale,
  listPrice: list,
  discountPercent: off,
);

FlashSale _sale(DateTime endsAt, {List<FlashSaleItem>? items}) => FlashSale(
  id: 'sale',
  headline: 'Flash Sale',
  subhead: 'Unbeatable deals.',
  endsAt: endsAt,
  items: items ?? [_item('a'), _item('b')],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.resetForTest();
  });

  group('splitting a duration', () {
    test('hours are hours within the day, not total hours', () {
      // inHours is cumulative, so a two-day sale read straight off it says
      // "50 Hrs" and the days cell says two -- the same time counted twice.
      final parts = CountdownParts.from(
        const Duration(days: 2, hours: 2, minutes: 3, seconds: 4),
      );

      expect(parts.days, 2);
      expect(parts.hours, 2);
      expect(parts.minutes, 3);
      expect(parts.seconds, 4);
    });

    test('a passed deadline is zero, never negative', () {
      final parts = CountdownParts.from(const Duration(seconds: -90));
      expect(parts.isZero, isTrue);
      expect(parts.minutes, 0);
      expect(parts.seconds, 0);
    });

    test('single digits are padded so the row does not jump', () {
      final parts = CountdownParts.from(const Duration(minutes: 9, seconds: 5));
      expect(parts.two(parts.minutes), '09');
      expect(parts.two(parts.seconds), '05');
    });
  });

  group('the countdown', () {
    testWidgets('counts down in real time', (tester) async {
      var now = DateTime(2026, 8, 25, 12);
      final endsAt = now.add(
        const Duration(hours: 2, minutes: 35, seconds: 41),
      );

      await tester.pumpWidget(
        _wrap(SaleCountdown(endsAt: endsAt, now: () => now)),
      );

      expect(find.text('02'), findsOneWidget);
      expect(find.text('35'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('40'), findsOneWidget);
    });

    testWidgets('reads the clock rather than subtracting a second', (
      tester,
    ) async {
      // What happens across a backgrounded app: no timer callbacks fire for ten
      // minutes. A counter that decremented would still show 2:35; this has to
      // show 2:25, because that is what the time actually is.
      var now = DateTime(2026, 8, 25, 12);
      final endsAt = now.add(const Duration(hours: 2, minutes: 35));

      await tester.pumpWidget(
        _wrap(SaleCountdown(endsAt: endsAt, now: () => now)),
      );
      expect(find.text('35'), findsOneWidget);

      now = now.add(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('25'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
    });

    testWidgets('always shows all four units', (tester) async {
      final now = DateTime(2026, 8, 25, 12);

      await tester.pumpWidget(
        _wrap(
          SaleCountdown(
            endsAt: now.add(const Duration(days: 3, hours: 4)),
            now: () => now,
          ),
        ),
      );
      expect(find.text('Days'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          SaleCountdown(
            endsAt: now.add(const Duration(hours: 4)),
            now: () => now,
          ),
        ),
      );
      // The days cell stays even at zero. Dropping it kept a short sale
      // tighter, but the row changed shape the moment days ticked into hours.
      expect(find.text('Days'), findsOneWidget);
      expect(find.text('00'), findsWidgets);
      expect(find.text('Hrs'), findsOneWidget);
    });

    testWidgets('reports the end once, and only once', (tester) async {
      var now = DateTime(2026, 8, 25, 12);
      var ended = 0;

      await tester.pumpWidget(
        _wrap(
          SaleCountdown(
            endsAt: now.add(const Duration(seconds: 2)),
            now: () => now,
            onEnded: () => ended++,
          ),
        ),
      );
      expect(ended, 0);

      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(ended, 1);

      // Several more ticks' worth of time, and no second announcement.
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(ended, 1);
    });

    testWidgets('a sale that was already over starts at zero', (tester) async {
      final now = DateTime(2026, 8, 25, 12);
      var ended = 0;

      await tester.pumpWidget(
        _wrap(
          SaleCountdown(
            endsAt: now.subtract(const Duration(hours: 1)),
            now: () => now,
            onEnded: () => ended++,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('00'), findsWidgets);
      expect(ended, 1);
    });
  });

  group('the section', () {
    testWidgets('shows the sale, its deadline and its deals', (tester) async {
      final now = DateTime(2026, 8, 25, 12);

      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: FlashSaleSection(
              sale: _sale(now.add(const Duration(hours: 2))),
              now: () => now,
            ),
          ),
        ),
      );

      // One tinted panel now, not a banner over a heading over a grid: the
      // name, the line under it, and the deals in a grid. No clock.
      expect(find.text('Flash Sale'), findsOneWidget);
      expect(find.text('Unbeatable deals.'), findsOneWidget);
      expect(find.byType(SaleCountdown), findsNothing);
      expect(find.byType(FlashDealTile), findsNWidgets(2));
      // No handler was given, so there is no way out to offer -- and an arrow
      // that points nowhere is the thing this app keeps refusing to draw.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('swaps to the ended state when the deadline passes', (
      tester,
    ) async {
      // This is the half of the countdown's job that survived it being removed
      // from the design: it told the section when to swap. Without it a shopper
      // sitting on the home page would be the one person who never sees the
      // sale end, and would go on looking at prices that expired while they
      // read. A single timer for the whole remaining duration does it now, so
      // this pumps that duration rather than one tick of a ticker.
      var now = DateTime(2026, 8, 25, 12);

      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: FlashSaleSection(
              sale: _sale(now.add(const Duration(seconds: 2))),
              now: () => now,
            ),
          ),
        ),
      );
      expect(find.byType(FlashDealTile), findsNWidgets(2));

      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('This flash sale has ended'), findsOneWidget);
      // The grid goes with it. Leaving it up would keep advertising prices
      // that are no longer being offered.
      expect(find.byType(FlashDealTile), findsNothing);
    });

    testWidgets('a sale already over renders ended, never the grid', (
      tester,
    ) async {
      final now = DateTime(2026, 8, 25, 12);

      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: FlashSaleSection(
              sale: _sale(now.subtract(const Duration(minutes: 1))),
              now: () => now,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('This flash sale has ended'), findsOneWidget);
      expect(find.byType(FlashDealTile), findsNothing);
    });
  });

  group('the deal card', () {
    testWidgets('strikes the old price only when it is a real saving', (
      tester,
    ) async {
      await tester.pumpWidget(_card(_item('a', sale: 600, list: 1000)));
      expect(find.text('Rs. 1,000'), findsOneWidget);
      expect(find.text('Rs. 600'), findsOneWidget);
      expect(find.text('-40%'), findsOneWidget);

      // Equal prices are not a discount, and a crossed-out number that saves
      // nothing is a claim the card must not make.
      await tester.pumpWidget(_card(_item('b', sale: 600, list: 600, off: 0)));
      expect(find.text('-0%'), findsNothing);
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => t.style?.decoration == TextDecoration.lineThrough),
        isEmpty,
      );
    });

    testWidgets('leaves the meter out when nothing knows the stock', (
      tester,
    ) async {
      // The real catalogue has no stock or sold figures, so this is the shape
      // a genuine payload arrives in. The card has to look finished.
      await tester.pumpWidget(_card(_item('a')));

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Stock:'), findsNothing);
      expect(find.textContaining('% sold'), findsNothing);
      expect(find.text('Rs. 600'), findsOneWidget);
    });

    testWidgets('draws the meter when the figures are there', (tester) async {
      await tester.pumpWidget(
        _card(
          FlashSaleItem(
            product: _product('a'),
            salePrice: 600,
            listPrice: 1000,
            discountPercent: 40,
            stock: 36,
            soldPercent: 64,
          ),
        ),
      );

      expect(find.text('64% sold'), findsOneWidget);
      expect(find.text('Stock: 36'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(0.64, 0.001),
      );
    });
  });

  group('the cards line up', () {
    /// Titles of wildly different lengths, which is what the real feed sends.
    List<FlashSaleItem> mixed() => [
      FlashSaleItem(
        product: const Product(
          numIid: 'short',
          title: 'Kettle',
          displayPrice: 600,
        ),
        salePrice: 600,
        listPrice: 1000,
        discountPercent: 40,
        stock: 12,
        soldPercent: 50,
      ),
      FlashSaleItem(
        product: const Product(
          numIid: 'long',
          title:
              'Supermarket Pet Food Stacking Pdq Paper Shelf '
              'Commercial Super Corrugated Paper Display Rack',
          displayPrice: 700,
        ),
        salePrice: 700,
        listPrice: 1000,
        discountPercent: 30,
        stock: 34,
        soldPercent: 61,
      ),
    ];

    testWidgets('a one-line title and a three-line one make the same card', (
      tester,
    ) async {
      // The grid is a Wrap, and a Wrap does not stretch a row to a common
      // height. Without the title reserving its two lines, the short card was
      // shorter and every element below it -- price, saving, stock bar -- sat
      // on a different line from its neighbour.
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      // Against DealGrid, which is where this layout now lives: the home
      // section is a swipeable rail, and the grid is the deals page.
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DealGrid(items: mixed()),
            ),
          ),
        ),
      );

      final cards = find.byType(FlashDealCard);
      expect(cards, findsNWidgets(2));
      final first = tester.getSize(cards.at(0));
      final second = tester.getSize(cards.at(1));

      expect(first.height, second.height);
      expect(first.width, second.width);
    });

    testWidgets('and they still line up at a large text scale', (tester) async {
      tester.view.physicalSize = const Size(1100, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            // A reserved height computed from a hardcoded font size would clip
            // here; it is measured through the text scaler for this reason.
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DealGrid(items: mixed()),
                ),
              ),
            ),
          ),
        ),
      );

      final cards = find.byType(FlashDealCard);
      expect(
        tester.getSize(cards.at(0)).height,
        tester.getSize(cards.at(1)).height,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('responsive', () {
    Future<int> columnsAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width * 2, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      // Against DealGrid, which is where the columns live now: the home
      // section swipes a rail, and the grid is the deals page.
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DealGrid(
                items: [for (var i = 0; i < 8; i++) _item('p$i')],
              ),
            ),
          ),
        ),
      );

      // How many cards share the topmost row.
      final tops = tester
          .widgetList<FlashDealCard>(find.byType(FlashDealCard))
          .map((card) => tester.getTopLeft(find.byWidget(card)).dy)
          .toList();
      final first = tops.first;
      return tops.where((dy) => dy == first).length;
    }

    testWidgets('a phone gets two columns', (tester) async {
      expect(await columnsAt(tester, 390), 2);
    });

    testWidgets('a tablet gets more', (tester) async {
      expect(await columnsAt(tester, 800), greaterThan(2));
    });

    testWidgets('a desktop window gets more again', (tester) async {
      final tablet = await columnsAt(tester, 800);
      expect(await columnsAt(tester, 1280), greaterThan(tablet));
    });
  });

  group('assembling a sale', () {
    late FakeApi api;

    setUp(() => api = stubCatalog());

    test('is titled Dashain Specials', () async {
      // The heading the section draws comes from the assembled sale, not from
      // a string typed into the widget -- so this is where the title lives and
      // this is what stops it drifting back.
      final sale = await FlashSaleRepository.instance.current();

      expect(sale?.headline, 'Dashain Specials');
    });

    test('prefers a banner promo over the stand-in figures', () async {
      final endsAt = DateTime.now().add(const Duration(hours: 3));
      api.on(
        'GET',
        '/hero-banners',
        body: [
          {
            'id': 'b1',
            'title': 'Mid-season',
            'is_active': true,
            'promo_headline_percent': 25,
            'promo_code': 'MID25',
            'promo_valid_until': endsAt.toIso8601String(),
          },
        ],
      );

      final sale = await FlashSaleRepository.instance.current();

      expect(sale, isNotNull);
      expect(sale!.isPlaceholder, isFalse);
      expect(sale.promoCode, 'MID25');
      // A real campaign percentage makes the struck price genuine: the
      // catalogue price really is the "before".
      final item = sale.items.first;
      expect(item.discountPercent, 25);
      expect(item.listPrice, item.product.displayPrice);
      expect(item.salePrice, lessThan(item.listPrice));
      // Nothing publishes these, so nothing claims them.
      expect(item.stock, isNull);
      expect(item.soldPercent, isNull);
    });

    test('fills all four cards even when half the feed has no price', () async {
      // The discover feed carries rows whose pricing has not been worked out,
      // and those cannot be a deal because there is nothing to discount.
      // Asking for exactly four returned two, and the section rendered a
      // half-empty row.
      api.on(
        'GET',
        '/feed/discover',
        body: [
          for (var i = 0; i < 16; i++)
            {
              'num_iid': 'row-$i',
              'title': 'Row $i',
              if (i.isEven) 'display_price': 500 + i,
            },
        ],
      );

      final sale = await FlashSaleRepository.instance.current();

      expect(sale!.items, hasLength(FlashSaleRepository.itemCount));
      expect(sale.items.every((i) => i.product.hasPrice), isTrue);
    });

    test('shows what it has when the catalogue cannot fill four', () async {
      api.on(
        'GET',
        '/feed/discover',
        body: [
          {'num_iid': 'a', 'title': 'Only one', 'display_price': 500},
        ],
      );

      final sale = await FlashSaleRepository.instance.current();
      expect(sale!.items, hasLength(1));
    });

    test('falls back to the stand-in when no banner carries a promo', () async {
      // Every live banner has all four promo columns null, so this is the
      // path that actually runs today.
      final sale = await FlashSaleRepository.instance.current();

      expect(sale, isNotNull);
      expect(
        sale!.isPlaceholder,
        isTrue,
        reason: 'the figures are made up and must say so',
      );
      expect(sale.items, isNotEmpty);
      expect(sale.endsAt.isAfter(DateTime.now()), isTrue);
    });

    test('an expired banner promo does not become a sale', () async {
      // heroBanners already drops expired banners; this guards the case where
      // one slips through with a past date.
      api.on(
        'GET',
        '/hero-banners',
        body: [
          {
            'id': 'b1',
            'title': 'Old',
            'promo_headline_percent': 30,
            'promo_valid_until': DateTime.now()
                .subtract(const Duration(days: 2))
                .toIso8601String(),
          },
        ],
      );

      final sale = await FlashSaleRepository.instance.current();
      // Either no sale, or the stand-in -- never the dead campaign.
      expect(sale?.promoCode, isNull);
      expect(sale?.discountPercent, isNot(30));
    });

    test('rows with no price are left out', () async {
      // "Price on request" rows exist in this feed, and a deal card for one
      // would advertise a discount off nothing.
      api.on(
        'GET',
        '/feed/discover',
        body: [
          {'num_iid': 'a', 'title': 'Priced', 'display_price': 500},
          {'num_iid': 'b', 'title': 'Unpriced'},
        ],
      );

      final sale = await FlashSaleRepository.instance.current();
      expect(sale!.items.map((i) => i.product.numIid), ['a']);
    });

    test('an empty feed is no sale rather than an empty one', () async {
      api.on('GET', '/feed/discover', body: const []);
      expect(await FlashSaleRepository.instance.current(), isNull);
    });
  });

  group('the stand-in figures', () {
    test('are stable for a product, so a card does not reshuffle', () {
      // Anything from Random() would give a different discount on every
      // scroll, and a stock count that changes as you watch it is worse than
      // none.
      expect(placeholder.discountFor('abc'), placeholder.discountFor('abc'));
      expect(placeholder.stockFor('abc'), placeholder.stockFor('abc'));
      expect(
        placeholder.soldPercentFor('abc'),
        placeholder.soldPercentFor('abc'),
      );
    });

    test('stay inside believable bounds', () {
      for (final id in ['a', 'bb', 'ccc', '692448816398', '']) {
        expect(placeholder.discountFor(id), inInclusiveRange(20, 50));
        expect(placeholder.stockFor(id), inInclusiveRange(8, 87));
        // Never 100: a full meter beside a card you can still buy from is the
        // one number a shopper will notice is wrong.
        expect(placeholder.soldPercentFor(id), inInclusiveRange(35, 89));
      }
    });

    test('the implied "was" price is above the sale price', () {
      final list = placeholder.listPriceFor(600, 40);
      expect(list, greaterThan(600));
      expect(list, closeTo(1000, 1));
    });

    test('a nonsensical discount leaves the price alone', () {
      expect(placeholder.listPriceFor(600, 0), 600);
      expect(placeholder.listPriceFor(600, 100), 600);
    });

    test('the window is always in the future and rolls over', () {
      final now = DateTime(2026, 8, 25, 13, 30);
      final end = placeholder.windowEnd(now);

      expect(end.isAfter(now), isTrue);
      expect(end.difference(now), lessThanOrEqualTo(placeholder.windowLength));
      // Same answer on every screen and every restart -- a countdown that
      // resets to six hours each time the app opens is its own kind of lie.
      expect(placeholder.windowEnd(now), end);
    });

    test('the last window of the day rolls into tomorrow', () {
      final late = DateTime(2026, 8, 25, 23, 59);
      final end = placeholder.windowEnd(late);
      expect(end.isAfter(late), isTrue);
      expect(end.day, 26);
    });
  });

  group('the sale panel', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      int items = 6,
      VoidCallback? onSeeAllDeals,
      double width = 400,
      double scale = 1.0,
    }) async {
      tester.view.physicalSize = Size(width * 2, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final now = DateTime(2026, 8, 25, 12);
      await tester.pumpWidget(
        _wrap(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: FlashSaleSection(
                sale: _sale(
                  now.add(const Duration(hours: 2)),
                  items: [for (var i = 0; i < items; i++) _item('p$i')],
                ),
                now: () => now,
                onSeeAllDeals: onSeeAllDeals ?? () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows four deals, two by two', (tester) async {
      // Four, not however many the sale happens to carry. A panel is a preview
      // of the deals page; six tiles at this width are too small to tell apart
      // and the fifth and sixth would sit in a half-empty third row.
      await pumpPanel(tester, items: 6);

      expect(find.byType(FlashDealTile), findsNWidgets(4));

      final tiles = tester
          .widgetList<FlashDealTile>(find.byType(FlashDealTile))
          .toList();
      final boxes = [for (final t in tiles) tester.getRect(find.byWidget(t))];

      // Two rows of two: the first pair share a top, the second pair share a
      // lower one, and each pair is side by side.
      expect(boxes[0].top, boxes[1].top);
      expect(boxes[2].top, boxes[3].top);
      expect(boxes[2].top, greaterThan(boxes[0].bottom));
      expect(boxes[1].left, greaterThan(boxes[0].right));
    });

    testWidgets('the tiles in a row are the same size', (tester) async {
      // Titles vary in length; the tiles must not. Both lines under the
      // picture are boxed to exactly one line so the grid has a straight
      // bottom edge whatever the catalogue returns.
      await pumpPanel(tester, items: 4);

      final boxes = tester
          .widgetList<FlashDealTile>(find.byType(FlashDealTile))
          .map((t) => tester.getSize(find.byWidget(t)))
          .toList();

      expect(boxes[0], boxes[1]);
      expect(boxes[2], boxes[3]);
      expect(boxes[0], boxes[2]);
    });

    testWidgets('a short sale fills what rows it can', (tester) async {
      // Three deals is one full row and one half one. The odd tile keeps its
      // column rather than stretching across, so it still reads as one of a
      // set rather than as a different kind of thing.
      await pumpPanel(tester, items: 3);

      final boxes = tester
          .widgetList<FlashDealTile>(find.byType(FlashDealTile))
          .map((t) => tester.getSize(find.byWidget(t)))
          .toList();

      expect(boxes, hasLength(3));
      expect(boxes[2].width, boxes[0].width);
    });

    testWidgets('tapping anywhere on the panel goes to the deals page', (
      tester,
    ) async {
      // The whole block is one target: the heading, the gaps, and every tile.
      // Somewhere on a panel that does not respond is what makes a block feel
      // broken, and a tile that goes somewhere else is worse.
      var opened = 0;
      await pumpPanel(tester, onSeeAllDeals: () => opened++);

      await tester.tap(find.text('Flash Sale'));
      await tester.pump();
      expect(opened, 1, reason: 'the heading');

      await tester.tap(find.byType(FlashDealTile).first);
      await tester.pump();
      expect(opened, 2, reason: 'a tile');

      await tester.tap(find.byType(FlashDealTile).last);
      await tester.pump();
      expect(opened, 3, reason: 'the last tile');
    });

    testWidgets('the tiles carry no gesture of their own', (tester) async {
      // Not a style choice. A tile with its own InkWell cuts a hole in the
      // panel's, so some presses would go to the deals page and some would
      // not, which is the failure the whole-panel target exists to avoid.
      await pumpPanel(tester);

      expect(
        find.descendant(
          of: find.byType(FlashDealTile),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('an arrow only when there is somewhere to go', (tester) async {
      await pumpPanel(tester, onSeeAllDeals: () {});
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      final now = DateTime(2026, 8, 25, 12);
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: FlashSaleSection(
              sale: _sale(now.add(const Duration(hours: 2))),
              now: () => now,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('carries no countdown', (tester) async {
      // The panel is a heading, a line of context and four tiles. The clock
      // that used to sit beside the heading is gone by request.
      await pumpPanel(tester);

      expect(find.byType(SaleCountdown), findsNothing);
    });

    testWidgets('the offer line states this deal, not a category claim', (
      tester,
    ) async {
      // The design this copies says "From Rs. 299" and "Up to 60% off" over
      // category tiles. Over one product those are a range with one member and
      // a ceiling nobody can point at. Each tile says what its own deal is.
      await pumpPanel(tester, items: 1);

      expect(find.text('40% off'), findsOneWidget);
      expect(find.textContaining('From'), findsNothing);
      expect(find.textContaining('Up to'), findsNothing);
    });

    testWidgets('the panel lays out at any text scale', (tester) async {
      for (final scale in [1.0, 1.5, 2.0]) {
        await pumpPanel(tester, scale: scale);
        expect(tester.takeException(), isNull, reason: 'at ${scale}x');
      }
    });

    testWidgets('is shorter than the grid it replaced', (tester) async {
      // Measured against the grid rather than against a number: a fixed
      // ceiling only says whether the section grew since somebody last edited
      // the ceiling.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      const six = 6;
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: DealGrid(
              items: [for (var i = 0; i < six; i++) _item('p$i')],
            ),
          ),
        ),
      );
      await tester.pump();
      final grid = tester.getSize(find.byType(DealGrid)).height;

      await pumpPanel(tester, items: six);

      expect(
        tester.getSize(find.byType(FlashSaleSection)).height,
        lessThan(grid),
      );
    });
  });
}

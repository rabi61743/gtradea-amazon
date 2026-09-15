import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/data/product_views_repository.dart';
import 'package:gtradea_amazon/features/account/presentation/recent_views_section.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// One row of the history, as the repository hands them over.
ProductView _view({
  required String id,
  required String name,
  num? price,
  Duration ago = const Duration(hours: 2),
}) => ProductView(
  productId: id,
  title: name,
  viewedAt: DateTime.now().subtract(ago),
  imageUrl: 'https://img.example/$id.jpg',
  price: price,
);

Future<void> _pump(WidgetTester tester, List<ProductView> views) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(children: [RecentViewsSection(views: views)]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

late FakeApi _api;

/// The catalogue stub these tests add product records to.
FakeApi stubApi() => _api;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _api = stubCatalog();
    CartStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
  });

  tearDown(clearApiStub);

  testWidgets('lists what the shopper actually opened, in the order given', (
    tester,
  ) async {
    await _pump(tester, [
      _view(id: '1', name: 'TWS Wireless Earbuds', price: 2850),
      _view(
        id: '2',
        name: "Men's Casual Sneakers",
        price: 4990,
        ago: const Duration(hours: 5),
      ),
    ]);

    expect(find.text('TWS Wireless Earbuds'), findsOneWidget);
    expect(find.text("Men's Casual Sneakers"), findsOneWidget);
    expect(find.text('Rs. 2,850'), findsOneWidget);

    // The time each was opened, from the record itself.
    expect(find.textContaining('Viewed'), findsNWidgets(2));

    // Newest at the top, as the caller sorted them.
    final newest = tester.getRect(find.text('TWS Wireless Earbuds'));
    final older = tester.getRect(find.text("Men's Casual Sneakers"));
    expect(newest.top, lessThan(older.top));
  });

  testWidgets('and every row can be saved, or bought outright', (tester) async {
    await _pump(tester, [
      _view(id: '1', name: 'TWS Wireless Earbuds', price: 2850),
    ]);

    // Saved.
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    expect(WishlistStore.instance.contains('1'), isTrue);

    // Buy now: the line goes into the cart at the price on the row, and the
    // cart is where it lands.
    await tester.tap(find.text('Buy Now'));
    await tester.pumpAndSettle();
    expect(CartStore.instance.lines.single.productId, '1');
    expect(CartStore.instance.lines.single.unitPrice, 2850);
    expect(find.byType(CartScreen), findsOneWidget);
  });

  testWidgets('a row with no price opens the product rather than guessing', (
    tester,
  ) async {
    // The history did not record a figure, so there is none to put in a cart.
    await _pump(tester, [_view(id: '9', name: 'Cordless Drill Machine')]);
    await tester.tap(find.text('Buy Now'));
    await tester.pumpAndSettle();

    expect(CartStore.instance.lines, isEmpty);
    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  testWidgets('no more rows than the reference shows', (tester) async {
    await _pump(tester, [
      for (var i = 0; i < 14; i++)
        _view(id: '$i', name: 'Product $i', price: 100 + i),
    ]);

    expect(find.text('Product 9'), findsOneWidget);
    expect(find.text('Product 10'), findsNothing);
  });

  testWidgets('and says nothing at all when there is no history', (
    tester,
  ) async {
    await _pump(tester, const []);

    expect(find.textContaining('recent searches'), findsNothing);
    expect(find.text('Buy Now'), findsNothing);
  });

  testWidgets('a row carries what the catalogue publishes about the product', (
    tester,
  ) async {
    // The history row knows a name, a picture and a price. The rest of the
    // row -- the line of detail and the badge -- is the catalogue's, read by
    // the product's own id.
    stubApi().onCall('GET', '/api/1688/product', (call) {
      expect(call.query['num_iid'], '1');
      return reply({
        'item': {
          'num_iid': '1',
          'title': 'TWS Wireless Earbuds',
          'total_sold': 12000,
          'props': [
            {'name': 'Sound', 'value': 'High Sound Quality'},
            {'name': 'Feature', 'value': 'Noise Cancellation'},
          ],
        },
        'pricing': {'displayPrice': 2850},
      });
    });

    await _pump(tester, [
      _view(id: '1', name: 'TWS Wireless Earbuds', price: 2850),
    ]);
    await tester.pumpAndSettle();

    // The blurb under the name, and one highlight under that -- the card is
    // as tall as this list makes it, so it carries one line of it. With no
    // prose in the listing the blurb is the first specification, so the
    // highlight is the next one: each fact once, never the same line twice.
    expect(find.text('Sound: High Sound Quality'), findsOneWidget);
    expect(find.text('Feature: Noise Cancellation'), findsOneWidget);
    expect(find.text('Rs. 2,850'), findsOneWidget);
  });

  testWidgets('a card appears whole: never a picture beside empty slots', (
    tester,
  ) async {
    // The product record is slow, as on a poor connection.
    stubApi().onCall('GET', '/api/1688/product', (call) {
      return reply({
        'item': {
          'num_iid': '1',
          'title': 'TWS Wireless Earbuds',
          'category_name': 'Earphones',
          'props': [
            {'name': 'Sound', 'value': 'High Sound Quality'},
          ],
        },
        'pricing': {'displayPrice': 2850},
      }, delay: const Duration(seconds: 2));
    });

    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              RecentViewsSection(
                views: [_view(id: '1', name: 'TWS Wireless Earbuds')],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Waiting: the whole card in outline, and none of its parts yet.
    expect(find.byType(RecentViewsSkeleton), findsOneWidget);
    expect(find.text('TWS Wireless Earbuds'), findsNothing);
    expect(find.text('Buy Now'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Arrived: name, description, price and department in the same frame.
    expect(find.byType(RecentViewsSkeleton), findsNothing);
    expect(find.text('TWS Wireless Earbuds'), findsOneWidget);
    expect(find.text('Sound: High Sound Quality'), findsOneWidget);
    expect(find.text('Rs. 2,850'), findsOneWidget);
    expect(find.text('Earphones'), findsOneWidget);
  });

  testWidgets('a product record already fetched draws complete, unasked', (
    tester,
  ) async {
    var asked = 0;
    stubApi().onCall('GET', '/api/1688/product', (call) {
      asked++;
      return reply({
        'item': {'num_iid': '1', 'title': 'TWS Wireless Earbuds'},
        'pricing': {'displayPrice': 2850},
      });
    });

    await _pump(tester, [_view(id: '1', name: 'TWS Wireless Earbuds')]);
    expect(asked, 1);

    // A second visit within the cache's life: first frame is the full card.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              RecentViewsSection(
                views: [_view(id: '1', name: 'TWS Wireless Earbuds')],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RecentViewsSkeleton), findsNothing);
    expect(find.text('Rs. 2,850'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(asked, 1, reason: 'no second request');
  });

  testWidgets('and waits for its picture too, fetched alongside the details', (
    tester,
  ) async {
    final picture = Completer<void>();
    var pictureStarted = false;
    final previous = RecentViewsSection.warmImage;
    RecentViewsSection.warmImage = (_, _) {
      pictureStarted = true;
      return picture.future;
    };
    addTearDown(() => RecentViewsSection.warmImage = previous);
    var detailStarted = false;
    stubApi().onCall('GET', '/api/1688/product', (call) {
      detailStarted = true;
      return reply({
        'item': {'num_iid': '1', 'title': 'TWS Wireless Earbuds'},
        'pricing': {'displayPrice': 2850},
      });
    });

    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              RecentViewsSection(
                views: [_view(id: '1', name: 'TWS Wireless Earbuds')],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Both began together; the details are in, the picture is not.
    expect(pictureStarted, isTrue);
    expect(detailStarted, isTrue);
    expect(find.byType(RecentViewsSkeleton), findsOneWidget);
    expect(find.text('Rs. 2,850'), findsNothing);

    picture.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(RecentViewsSkeleton), findsNothing);
    expect(find.text('Rs. 2,850'), findsOneWidget);
  });

  testWidgets('a batch asks for every record at once, each once', (
    tester,
  ) async {
    final started = <String>[];
    stubApi().onCall('GET', '/api/1688/product', (call) {
      started.add('${call.query['num_iid']}');
      return reply({
        'item': {'num_iid': '${call.query['num_iid']}', 'title': 'x'},
      }, delay: const Duration(seconds: 1));
    });

    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              RecentViewsSection(
                views: [
                  for (var i = 0; i < 10; i++)
                    _view(id: 'b$i', name: 'Product $i', price: 100),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(started.toSet(), {for (var i = 0; i < 10; i++) 'b$i'});
    expect(started, hasLength(10), reason: 'each once');
    expect(find.text('Product 9'), findsOneWidget);
  });

  testWidgets('a product with one specification prints it only once', (
    tester,
  ) async {
    stubApi().onCall('GET', '/api/1688/product', (call) {
      return reply({
        'item': {
          'num_iid': '1',
          'title': 'Lead-Acid Battery Charger',
          'props': [
            {'name': 'Brand', 'value': 'Pulse treasure'},
          ],
        },
        'pricing': {'displayPrice': 995},
      });
    });

    await _pump(tester, [
      _view(id: '1', name: 'Lead-Acid Battery Charger', price: 995),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Brand: Pulse treasure'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });

  testWidgets('the department chip stays one line beside the price', (
    tester,
  ) async {
    stubApi().onCall('GET', '/api/1688/product', (call) {
      return reply({
        'item': {
          'num_iid': '1',
          'title': 'Source Factory Display',
          'category_name': 'Display rack and shelving for retail stores',
        },
        'pricing': {'displayPrice': 11544},
      });
    });
    tester.view.physicalSize = const Size(406 * 3, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              RecentViewsSection(
                views: [
                  _view(id: '1', name: 'Source Factory Display', price: 11544),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chips = find.byWidgetPredicate(
      (w) => w is Text && w.maxLines == 1 && w.style?.fontSize == 9.5,
    );
    expect(chips, findsOneWidget);
    // Two lines of 9.5pt type, with the theme's line height, would be over 20.
    final chip = tester.getRect(chips);
    expect(chip.height, lessThan(20), reason: 'one line, not two');
    expect(find.text('Rs. 11,544'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('and invents no rating, no was-price and no discount', (
    tester,
  ) async {
    // This catalogue publishes no reviews and one price per product, so a
    // star, a struck-out figure or a "% OFF" here would each be a claim
    // nobody made.
    stubApi().onCall('GET', '/api/1688/product', (call) {
      return reply({
        'item': {'num_iid': '1', 'title': 'TWS Wireless Earbuds'},
        'pricing': {'displayPrice': 2850},
      });
    });

    await _pump(tester, [
      _view(id: '1', name: 'TWS Wireless Earbuds', price: 2850),
    ]);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.textContaining('OFF'), findsNothing);
    expect(find.text('Best Seller'), findsNothing);
    expect(find.text('Popular'), findsNothing);
  });

  testWidgets('every card is the same shape, whatever the product', (
    tester,
  ) async {
    // One with a long name, one short; one with a badge, one without. The
    // cards should not be able to tell.
    stubApi().onCall('GET', '/api/1688/product', (call) {
      final id = call.query['num_iid'];
      return reply({
        'item': {
          'num_iid': id,
          if (id == '1') 'total_sold': 12000,
          if (id == '1')
            'props': [
              {'name': 'Sound', 'value': 'High Sound Quality'},
            ],
        },
        'pricing': {'displayPrice': id == '1' ? 2850 : 199},
      });
    });

    await _pump(tester, [
      _view(
        id: '1',
        name:
            'TWS Wireless Earbuds With A Very Long Name That Wraps Onto '
            'A Second Line And Then Some',
        price: 2850,
      ),
      _view(id: '2', name: 'Short', price: 199),
    ]);
    await tester.pumpAndSettle();

    // The rows themselves.
    final cards = find.byType(Material);
    final first = tester.getRect(
      find.ancestor(of: find.text('Short'), matching: cards).first,
    );
    final long = tester.getRect(
      find
          .ancestor(of: find.textContaining('TWS Wireless'), matching: cards)
          .first,
    );
    expect(long.height, first.height, reason: 'one card height');
    expect(long.width, first.width, reason: 'one card width');

    // Buy Now sits at the same offset from the foot of each card.
    final buys = find.text('Buy Now');
    final one = tester.getRect(buys.at(0));
    final two = tester.getRect(buys.at(1));
    final cardOne = tester.getRect(
      find.ancestor(of: buys.at(0), matching: cards).first,
    );
    final cardTwo = tester.getRect(
      find.ancestor(of: buys.at(1), matching: cards).first,
    );
    expect(
      cardOne.bottom - one.bottom,
      closeTo(cardTwo.bottom - two.bottom, 0.5),
    );

    // And so does the price.
    final priceOne = tester.getRect(find.text('Rs. 2,850'));
    final priceTwo = tester.getRect(find.text('Rs. 199'));
    expect(
      cardOne.bottom - priceOne.bottom,
      closeTo(cardTwo.bottom - priceTwo.bottom, 0.5),
    );
  });

  testWidgets('the rows are the section, with no banner under them', (
    tester,
  ) async {
    await _pump(tester, [
      _view(id: '1', name: 'TWS Wireless Earbuds', price: 2850),
    ]);

    // The list is the rows; the strip that sat under it is gone.
    expect(find.text('TWS Wireless Earbuds'), findsOneWidget);
    expect(find.text('Discover more products'), findsNothing);
    expect(
      find.text('Explore categories trending on gtradea.com'),
      findsNothing,
    );
    expect(find.text('Browse Categories'), findsNothing);
  });
}

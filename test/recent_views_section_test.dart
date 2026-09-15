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
    // as tall as this list makes it, so it carries one line of it.
    expect(find.text('Sound: High Sound Quality'), findsWidgets);
    expect(find.text('Feature: Noise Cancellation'), findsNothing);
    expect(find.text('Rs. 2,850'), findsOneWidget);
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

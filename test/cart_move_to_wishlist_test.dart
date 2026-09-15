import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/catalog/presentation/browse_screen.dart';
import 'package:gtradea_amazon/features/product/data/storefront_config.dart';
import 'package:gtradea_amazon/features/promo/data/coupon_store.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

const _polo = CartLine(
  productId: '825709571788',
  title: 'Quick-drying polo',
  unitPrice: 554,
  quantity: 2,
  source: '1688',
  category: 'Men',
);

const _kettle = CartLine(
  productId: '1122334455',
  title: 'Electric kettle',
  unitPrice: 1800,
  source: '1688',
);

/// A line the shop has no price for, which is not one to file under a figure.
const _unpriced = CartLine(
  productId: '9090909090',
  title: 'Price on request',
  unitPrice: 0,
  source: '1688',
);

late FakeApi api;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const CartScreen()),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    CouponStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    api = stubCatalog();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  testWidgets('a line moves out of the cart and onto the saved list', (
    tester,
  ) async {
    signInForTest();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/cart', body: const {'items': []});
    api.on('GET', '/wishlist', body: const {'items': []});
    api.on('POST', '/wishlist', body: const {'id': 'w-1'});
    api.on('POST', '/cart', body: const {'id': 'c-1', 'quantity': 2});
    api.on('DELETE', '/cart/c-1', status: 204);

    CartStore.instance.add(_polo);
    await _pump(tester);

    await tester.tap(find.text('Move to wishlist'));
    await tester.pump();
    // The cart batches its own sync behind a short timer; let it run.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // Out of the cart, onto the list, and the account told about both.
    expect(CartStore.instance.lines, isEmpty);
    expect(WishlistStore.instance.contains('825709571788'), isTrue);
    expect(
      api.calls.where((c) => c.method == 'POST' && c.path == '/wishlist'),
      isNotEmpty,
      reason: 'the save reaches the account',
    );
  });

  testWidgets('and undo puts it back in the cart and off the list', (
    tester,
  ) async {
    api.on('GET', '/cart', body: const {'items': []});
    CartStore.instance.add(_polo);
    await _pump(tester);

    await tester.tap(find.text('Move to wishlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(CartStore.instance.lines, hasLength(1));
    expect(WishlistStore.instance.contains('825709571788'), isFalse);
  });

  testWidgets('Save all takes the priced lines and leaves the rest', (
    tester,
  ) async {
    CartStore.instance
      ..add(_polo)
      ..add(_kettle)
      ..add(_unpriced);
    // One of them is already saved, so it is not saved twice.
    WishlistStore.instance.toggle(
      const SavedProduct(
        id: '1122334455',
        title: 'Electric kettle',
        price: 1800,
      ),
    );

    await _pump(tester);
    // The whole card is the button now, so its words are what is tapped.
    await tester.tap(find.text('Save all to wishlist'));
    await tester.pumpAndSettle();

    // The unpriced line stays; the other two are off the cart.
    expect(CartStore.instance.lines, hasLength(1));
    expect(CartStore.instance.lines.single.productId, '9090909090');
    expect(WishlistStore.instance.count, 2);

    // And the shopper is told what happened to each group -- in the snack bar
    // and again in the card, which keeps the answer after the bar has gone.
    expect(find.textContaining('1 saved'), findsWidgets);
    expect(find.textContaining('already on your list'), findsWidgets);
    expect(find.textContaining('no price'), findsWidgets);
  });

  testWidgets('each action is a compact card that answers a tap anywhere', (
    tester,
  ) async {
    CartStore.instance.add(_polo);
    await _pump(tester);

    for (final title in ['Save all to wishlist', 'Continue shopping']) {
      final card = find.ancestor(
        of: find.text(title),
        matching: find.byType(Card),
      );
      final height = tester.getSize(card).height;
      // One row: no heading, paragraph and button stacked up any more -- and
      // still a comfortable thumb target.
      expect(height, lessThanOrEqualTo(64), reason: '$title is $height tall');
      expect(height, greaterThanOrEqualTo(48), reason: title);
    }

    // Not only the words: the line under the title opens it too. It sits
    // under the recommendations now, so it is scrolled to first.
    await tester.ensureVisible(find.text('Back to browsing products'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to browsing products'));
    await tester.pumpAndSettle();
    expect(find.byType(BrowseScreen), findsOneWidget);
  });

  testWidgets('Continue shopping goes to the catalogue', (tester) async {
    CartStore.instance.add(_polo);
    await _pump(tester);

    await tester.ensureVisible(find.text('Continue shopping'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue shopping'));
    await tester.pumpAndSettle();

    expect(find.byType(BrowseScreen), findsOneWidget);
  });

  testWidgets('the line says how long delivery takes, from the shop', (
    tester,
  ) async {
    // The settings row the live site publishes, double-encoded as it is
    // there.
    StorefrontConfigRepository.instance.resetForTest();
    api.on(
      'GET',
      '/site-settings',
      body: [
        {
          'setting_key': 'shipping_estimate_note',
          'setting_value': '{"enabled":true,"guarantee":{"enabled":true,"weeksMin":2,"weeksMax":4}}',
        },
      ],
    );

    CartStore.instance.add(_polo);
    await _pump(tester);

    expect(find.text('Delivery in 2-4 weeks'), findsOneWidget);
  });

  testWidgets('the price sits on the delivery line, and the cards sit close', (
    tester,
  ) async {
    StorefrontConfigRepository.instance.resetForTest();
    api.on(
      'GET',
      '/site-settings',
      body: [
        {
          'setting_key': 'shipping_estimate_note',
          'setting_value': '{"enabled":true,"guarantee":{"enabled":true,"weeksMin":3,"weeksMax":5}}',
        },
      ],
    );

    CartStore.instance
      ..add(_polo)
      ..add(_kettle);
    await _pump(tester);

    // The polo's delivery note, small, with its price at the right of the
    // same line -- and shown once, not again on a line of its own. Read from
    // the polo's own card: the cart lists the newest line first.
    final price = find.text('Rs. 554');
    expect(price, findsOneWidget);
    final poloCard = find.ancestor(of: price, matching: find.byType(Card));
    final delivery = find.descendant(
      of: poloCard,
      matching: find.text('Delivery in 3-5 weeks'),
    );
    expect(delivery, findsOneWidget);
    final note = tester.widget<Text>(delivery);
    expect(note.style?.fontSize, 9.5);
    final noteBox = tester.getRect(delivery);
    final priceBox = tester.getRect(price);
    expect(priceBox.left, greaterThan(noteBox.right), reason: 'to its right');
    expect(
      (priceBox.center.dy - noteBox.center.dy).abs(),
      lessThan(8),
      reason: 'on the same line',
    );

    // Two cards, closer than they were and still apart. Measured on each
    // card's visible surface: a Card's own bounds include its margin, so two
    // of them always abut.
    final cards = find.descendant(
      of: find.byType(CartScreen),
      matching: find.byType(Card),
    );
    Rect surface(int i) => tester.getRect(
      find.descendant(of: cards.at(i), matching: find.byType(Material)).first,
    );
    final first = surface(0);
    final second = surface(1);
    final gap = second.top - first.bottom;
    expect(gap, greaterThan(0), reason: 'not touching');
    expect(gap, lessThanOrEqualTo(6));

    // The wishlist action is still on every line.
    expect(find.text('Move to wishlist'), findsNWidgets(2));
  });
}

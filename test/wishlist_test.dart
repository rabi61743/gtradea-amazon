import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/presentation/image_viewer_screen.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:gtradea_amazon/features/wishlist/presentation/wishlist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

const _jacket = SavedProduct(
  id: 'jacket',
  title: 'Ice silk jacket',
  price: 1130,
  listPrice: 1568,
);

const _dress = SavedProduct(id: 'dress', title: 'Suspender dress', price: 1808);

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

late FakeApi api;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WishlistStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    api = stubCatalog();
  });

  group('WishlistStore', () {
    test('toggle adds, reports the new state, and toggles back off', () {
      final store = WishlistStore.instance;
      expect(store.contains('jacket'), isFalse);

      expect(store.toggle(_jacket), isTrue);
      expect(store.contains('jacket'), isTrue);
      expect(store.count, 1);

      expect(store.toggle(_jacket), isFalse);
      expect(store.contains('jacket'), isFalse);
    });

    test('newest saved comes first', () {
      final store = WishlistStore.instance
        ..toggle(_jacket)
        ..toggle(_dress);
      expect(store.items.map((e) => e.id), ['dress', 'jacket']);
    });

    test('saving the same product twice does not duplicate it', () {
      final store = WishlistStore.instance..toggle(_jacket);
      // Same id, different price -- identity is the id, not the payload.
      store.toggle(
        const SavedProduct(id: 'jacket', title: 'Ice silk jacket', price: 999),
      );
      expect(store.count, 0, reason: 'second toggle removes it');
    });

    test('survives a reload from disk', () async {
      WishlistStore.instance.toggle(_jacket);
      // Let the fire-and-forget write land before reading it back.
      await Future<void>.delayed(Duration.zero);

      WishlistStore.instance.resetForTest();
      await WishlistStore.instance.load();

      expect(WishlistStore.instance.contains('jacket'), isTrue);
      expect(WishlistStore.instance.items.first.title, 'Ice silk jacket');
    });

    test('a corrupt store degrades to empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'gtradea_wishlist': 'not json'});
      WishlistStore.instance.resetForTest();
      await WishlistStore.instance.load();
      expect(WishlistStore.instance.items, isEmpty);
    });

    test('entries missing an id are skipped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_wishlist': '[{"title":"no id","price":1},{"id":"ok","title":"Fine","price":2}]',
      });
      WishlistStore.instance.resetForTest();
      await WishlistStore.instance.load();
      expect(WishlistStore.instance.items.map((e) => e.id), ['ok']);
    });
  });

  testWidgets('the empty list explains how to fill it', (tester) async {
    await tester.pumpWidget(_wrap(const WishlistScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('saved products are listed with their price', (tester) async {
    WishlistStore.instance.toggle(_jacket);
    await tester.pumpWidget(_wrap(const WishlistScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Ice silk jacket'), findsOneWidget);
    expect(find.text('Rs. 1,130'), findsOneWidget);
    expect(find.text('Rs. 1,568'), findsOneWidget);
  });

  testWidgets('removing one offers an undo that really restores it', (
    tester,
  ) async {
    WishlistStore.instance.toggle(_jacket);
    await tester.pumpWidget(_wrap(const WishlistScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove from saved'));
    await tester.pump();
    expect(WishlistStore.instance.count, 0);

    // Let the snack bar finish animating in; tapping mid-slide misses it.
    await tester.pump(const Duration(milliseconds: 750));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(WishlistStore.instance.contains('jacket'), isTrue);
  });

  testWidgets('clearing everything asks first', (tester) async {
    WishlistStore.instance
      ..toggle(_jacket)
      ..toggle(_dress);
    await tester.pumpWidget(_wrap(const WishlistScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear your saved items?'), findsOneWidget);

    // Backing out must keep the list intact.
    await tester.tap(find.text('Keep them'));
    await tester.pumpAndSettle();
    expect(WishlistStore.instance.count, 2);
  });

  testWidgets('the image viewer shows a page counter and closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ImageViewerScreen(
          images: [
            'https://example.invalid/1.jpg',
            'https://example.invalid/2.jpg',
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('1/2'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsWidgets);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  group('the saved screen', () {
    const wholesale = SavedProduct(
      id: 'polo',
      title: 'Quick-drying polo shirt',
      price: 554,
      sellerBadge: 'Verified factory',
      salesLabel: '3k+ sold',
      category: 'Men',
      minOrder: 10,
    );

    const unpriced = SavedProduct(
      id: 'mystery',
      title: 'Display rack, price pending',
      price: 0,
    );

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(const WishlistScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('shows what the catalogue actually knows about a product', (
      tester,
    ) async {
      WishlistStore.instance.toggle(wholesale);
      await pump(tester);

      expect(find.text('Quick-drying polo shirt'), findsOneWidget);
      expect(find.text('Verified factory'), findsOneWidget);
      expect(find.text('3k+ sold'), findsOneWidget);
      expect(find.text('Rs. 554'), findsOneWidget);
      expect(find.text('Minimum 10'), findsOneWidget);
    });

    testWidgets('invents neither a rating nor a stock promise', (tester) async {
      // The reference design carries both. This catalogue publishes neither,
      // so stars would be made up, and "In Stock" would be a promise the
      // server never made -- which a shopper only discovers at checkout.
      WishlistStore.instance.toggle(wholesale);
      await pump(tester);

      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(find.textContaining('In Stock'), findsNothing);
    });

    testWidgets('moving one puts it in the cart at the seller minimum', (
      tester,
    ) async {
      // One of a listing that sells in tens is a refusal waiting to happen.
      WishlistStore.instance.toggle(wholesale);
      await pump(tester);

      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();

      final line = CartStore.instance.lines.single;
      expect(line.productId, 'polo');
      expect(line.quantity, 10);
      expect(line.minOrder, 10);
      expect(line.category, 'Men', reason: 'so a category coupon still knows');
    });

    testWidgets('adding one keeps its card and then reads Added to Cart', (
      tester,
    ) async {
      WishlistStore.instance
        ..toggle(wholesale)
        ..toggle(_dress);
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('saved-add-dress')));
      await tester.pump();

      // Mid-flight: nothing is claimed yet, and nothing is in the cart.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Added to Cart'), findsNothing);
      expect(CartStore.instance.isEmpty, isTrue);

      await tester.pumpAndSettle();
      expect(CartStore.instance.contains(_dress.id), isTrue);
      expect(find.text('Added to Cart'), findsOneWidget);
      // Both cards are still saved.
      expect(WishlistStore.instance.contains(_dress.id), isTrue);
      expect(WishlistStore.instance.contains('polo'), isTrue);
      expect(find.text('2 items saved'), findsOneWidget);
    });

    testWidgets('undo takes it out of the cart and resets the button', (
      tester,
    ) async {
      WishlistStore.instance.toggle(wholesale);
      await pump(tester);

      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();
      expect(CartStore.instance.lineCount, 1);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(CartStore.instance.isEmpty, isTrue);
      expect(WishlistStore.instance.contains('polo'), isTrue);
      expect(find.text('Add to cart'), findsOneWidget);
      expect(find.text('Added to Cart'), findsNothing);
    });

    testWidgets('a saved row with no price gets one from the catalogue', (
      tester,
    ) async {
      // A row can be saved before the pricing engine has worked one out. Asking
      // for the price is what lets every item move rather than most of them.
      api.on(
        'GET',
        'https://gtradea.com/api/1688/product',
        body: {
          'item': {'num_iid': 'mystery', 'title': 'Display rack'},
          'pricing': {'displayPrice': 4200},
        },
      );
      WishlistStore.instance.toggle(unpriced);
      await pump(tester);

      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();

      expect(CartStore.instance.lines.single.unitPrice, 4200);
      expect(WishlistStore.instance.contains('mystery'), isTrue);
    });

    testWidgets('a product the catalogue cannot price stays saved', (
      tester,
    ) async {
      // Adding it at nothing would put Rs. 0 in the cart for something real.
      api.on(
        'GET',
        'https://gtradea.com/api/1688/product',
        status: 404,
        body: const {'error': 'gone'},
      );
      WishlistStore.instance.toggle(unpriced);
      await pump(tester);

      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();

      expect(CartStore.instance.isEmpty, isTrue);
      expect(WishlistStore.instance.contains('mystery'), isTrue);
      expect(find.textContaining('no price yet'), findsOneWidget);
      // The add failed, so the button is back as it was.
      expect(find.text('Add to cart'), findsOneWidget);
      expect(find.text('Added to Cart'), findsNothing);
    });

    testWidgets('Move all empties the list into the cart', (tester) async {
      api.on(
        'GET',
        'https://gtradea.com/api/1688/product',
        body: {
          'item': {'num_iid': 'mystery', 'title': 'Display rack'},
          'pricing': {'displayPrice': 4200},
        },
      );
      WishlistStore.instance
        ..toggle(wholesale)
        ..toggle(unpriced)
        ..toggle(_dress);
      await pump(tester);

      await tester.tap(find.text('Move all'));
      await tester.pumpAndSettle();

      expect(CartStore.instance.lineCount, 3);
      expect(WishlistStore.instance.count, 0);
      expect(find.text('Nothing saved yet'), findsOneWidget);
    });

    testWidgets('Move all leaves behind only what it could not price', (
      tester,
    ) async {
      api.on(
        'GET',
        'https://gtradea.com/api/1688/product',
        status: 404,
        body: const {'error': 'gone'},
      );
      WishlistStore.instance
        ..toggle(wholesale)
        ..toggle(unpriced);
      await pump(tester);

      await tester.tap(find.text('Move all'));
      await tester.pumpAndSettle();

      expect(CartStore.instance.lineCount, 1);
      expect(WishlistStore.instance.count, 1);
      expect(WishlistStore.instance.contains('mystery'), isTrue);
      expect(find.textContaining('1 had no price'), findsOneWidget);
    });

    testWidgets('the heart on a card unsaves it', (tester) async {
      WishlistStore.instance.toggle(wholesale);
      await pump(tester);

      await tester.tap(find.byTooltip('Remove from saved'));
      await tester.pump();

      expect(WishlistStore.instance.contains('polo'), isFalse);
    });

    testWidgets('the cart badge counts what was just added', (tester) async {
      WishlistStore.instance.toggle(wholesale);
      await pump(tester);

      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('10')),
        findsNothing,
      );

      await tester.tap(find.text('Add to cart'));
      // Counted when the animation lands, which is when the add is made.
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('10')),
        findsOneWidget,
      );
    });

    testWidgets('the summary counts the list and offers one action', (
      tester,
    ) async {
      WishlistStore.instance
        ..toggle(wholesale)
        ..toggle(_dress);
      await pump(tester);

      expect(find.text('2 items saved'), findsOneWidget);
      expect(find.text('Move all'), findsOneWidget);
    });

    testWidgets('an empty list explains itself and offers no bulk action', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Nothing saved yet'), findsOneWidget);
      expect(find.text('Move all'), findsNothing);
      expect(find.byTooltip('Clear all'), findsNothing);
    });

    testWidgets('tapping a card opens that product', (tester) async {
      WishlistStore.instance.toggle(wholesale);
      await pump(tester);

      await tester.tap(find.text('Quick-drying polo shirt'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
    });
  });
}

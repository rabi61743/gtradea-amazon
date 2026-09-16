import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/add_to_cart_sheet.dart';
import 'package:gtradea_amazon/features/cart/presentation/quick_add_to_cart.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/home/widgets/product_grid.dart';
import 'package:gtradea_amazon/features/product/data/product_repository.dart';
import 'package:gtradea_amazon/shared/widgets/app_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// Two axes with real choices on them: this one has to ask.
Map<String, dynamic> _choosy() => {
  'item': {
    'num_iid': '1234',
    'title': 'Quick-drying polo',
    'skus': [
      {
        'sku_id': 'a',
        'quantity': 5,
        'variant_parts': [
          {'name': 'Color', 'value': 'Wine red'},
          {'name': 'Size', 'value': 'M'},
        ],
      },
      {
        'sku_id': 'b',
        'quantity': 5,
        'variant_parts': [
          {'name': 'Color', 'value': 'Navy'},
          {'name': 'Size', 'value': 'L'},
        ],
      },
    ],
  },
  'pricing': {'displayPrice': 554},
};

/// One SKU, one colour, one size: nothing to ask about.
Map<String, dynamic> _single() => {
  'item': {
    'num_iid': '1234',
    'title': 'Quick-drying polo',
    'min_order_quantity': 3,
    'skus': [
      {
        'sku_id': 'only',
        'spec_id': 'spec-only',
        'quantity': 40,
        'variant_parts': [
          {'name': 'Color', 'value': 'Wine red'},
          {'name': 'Size', 'value': 'M'},
        ],
      },
    ],
  },
  'pricing': {
    'displayPrice': 554,
    'skuPrices': {
      'only': {'displayPrice': 540},
    },
  },
};

/// And one the seller publishes no options for at all.
Map<String, dynamic> _plain() => {
  'item': {'num_iid': '1234', 'title': 'Made-to-order banner'},
  'pricing': {'displayPrice': 99},
};

const _product = Product(
  numIid: '1234',
  title: 'Quick-drying polo',
  displayPrice: 554,
  imageUrl: 'https://example.invalid/polo.jpg',
);

/// A grid card and a bottom bar: a cart button to leave from, and a cart icon
/// to arrive at.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => SingleChildScrollView(
            child: ProductGrid(
              title: 'More',
              products: const [_product],
              onAddToCart: (p) => quickAddToCart(context, p),
            ),
          ),
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: CartStore.instance,
          builder: (context, _) => AppBottomNav(
            currentIndex: 0,
            onSelected: (_) {},
            cartCount: CartStore.instance.count,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder get _cartButton => find.byIcon(Icons.add_shopping_cart);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    ProductRepository.instance.clearDetailCache();
    api = stubCatalog();
  });

  tearDown(clearApiStub);

  testWidgets('a product with choices to make still opens the sheet', (
    tester,
  ) async {
    api.on('GET', '/api/1688/product', body: _choosy());
    await _pump(tester);

    await tester.tap(_cartButton);
    await tester.pumpAndSettle();

    expect(find.byType(AddToCartSheet), findsOneWidget);
    expect(find.text('Select an option'), findsOneWidget);
    expect(CartStore.instance.lines, isEmpty, reason: 'nothing added yet');
  });

  testWidgets('one published option goes straight into the cart', (
    tester,
  ) async {
    api.on('GET', '/api/1688/product', body: _single());
    await _pump(tester);

    await tester.tap(_cartButton);
    await tester.pumpAndSettle();

    // No sheet: there was nothing to ask.
    expect(find.byType(AddToCartSheet), findsNothing);

    final line = CartStore.instance.lines.single;
    expect(line.productId, '1234');
    expect(line.skuId, 'only', reason: 'the one SKU, carried');
    expect(line.specId, 'spec-only');
    // The record's own minimum and the option's own price.
    expect(line.quantity, 3);
    expect(line.minOrder, 3);
    expect(line.unitPrice, 540);
  });

  testWidgets('and so does one with no options at all', (tester) async {
    api.on('GET', '/api/1688/product', body: _plain());
    await _pump(tester);

    await tester.tap(_cartButton);
    await tester.pumpAndSettle();

    expect(find.byType(AddToCartSheet), findsNothing);
    final line = CartStore.instance.lines.single;
    expect(line.variantLabel, isNull);
    expect(line.unitPrice, 99);
  });

  testWidgets('the product flies to the cart, and nothing is left behind', (
    tester,
  ) async {
    api.on('GET', '/api/1688/product', body: _single());
    await _pump(tester);

    await tester.tap(_cartButton);
    // Past the fetch and into the flight.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final flying = find.byWidgetPredicate(
      (w) => w is Transform && w.child is ClipRRect,
    );
    expect(flying, findsWidgets, reason: 'something is in the air');

    await tester.pumpAndSettle();
    // The overlay entry is gone: the only cart icons left are the bar's own.
    expect(
      find
          .descendant(
            of: find.byType(Overlay),
            matching: find.byType(ClipRRect),
          )
          .evaluate()
          .length,
      lessThan(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the arc is a curve, not a loop over the page', (tester) async {
    // It used to rise a flat 80 above the higher end whatever the distance,
    // which from a card near the cart read as the picture flying up the
    // screen and coming back down. The rise is a fraction of the journey now,
    // capped, so it curves without leaving the path.
    api.on('GET', '/api/1688/product', body: _single());
    await _pump(tester);

    final start = tester.getCenter(_cartButton);
    final target = tester.getCenter(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.byIcon(Icons.shopping_cart_outlined),
      ),
    );

    await tester.tap(_cartButton);
    await tester.pump();

    final path = <Offset>[];
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      final flying = find.byWidgetPredicate(
        (w) => w is ClipRRect && w.child is Image,
      );
      if (flying.evaluate().isNotEmpty) path.add(tester.getCenter(flying));
    }
    expect(path.length, greaterThan(3), reason: 'it was seen in flight');

    final highest = path.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    final topEnd = start.dy < target.dy ? start.dy : target.dy;
    // Above the higher end -- it is still an arc -- but only just.
    expect(highest, lessThan(topEnd), reason: 'still curved');
    expect(
      topEnd - highest,
      lessThan(40),
      reason: 'and no longer loops: rose ${topEnd - highest}',
    );

    await tester.pumpAndSettle();
  });

  testWidgets('a rapid second tap does not add it twice', (tester) async {
    api.on('GET', '/api/1688/product', body: _single());
    await _pump(tester);

    await tester.tap(_cartButton);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_cartButton, warnIfMissed: false);
    await tester.tap(_cartButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(CartStore.instance.lines.length, 1);
    expect(CartStore.instance.lines.single.quantity, 3, reason: 'added once');
  });

  testWidgets('the cart count is the store own, and it moves on the add', (
    tester,
  ) async {
    api.on('GET', '/api/1688/product', body: _single());
    await _pump(tester);

    expect(
      find.descendant(of: find.byType(AppBottomNav), matching: find.text('3')),
      findsNothing,
      reason: 'an empty cart carries no badge',
    );

    await tester.tap(_cartButton);
    await tester.pumpAndSettle();

    expect(CartStore.instance.count, 3);
    expect(
      find.descendant(of: find.byType(AppBottomNav), matching: find.text('3')),
      findsOneWidget,
      reason: 'the real count, once the cart really took it',
    );
  });

  testWidgets('a record that will not load falls back to the sheet', (
    tester,
  ) async {
    api.on('GET', '/api/1688/product', status: 500);
    await _pump(tester);

    await tester.tap(_cartButton);
    await tester.pumpAndSettle();

    // Nothing is added on a guess, and nothing claims success.
    expect(CartStore.instance.lines, isEmpty);
    expect(find.byType(AddToCartSheet), findsOneWidget);
  });

  testWidgets('reduced motion still adds, with nothing left over', (
    tester,
  ) async {
    api.on('GET', '/api/1688/product', body: _single());
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: ProductGrid(
                  title: 'More',
                  products: const [_product],
                  onAddToCart: (p) => quickAddToCart(context, p),
                ),
              ),
            ),
            bottomNavigationBar: ListenableBuilder(
              listenable: CartStore.instance,
              builder: (context, _) => AppBottomNav(
                currentIndex: 0,
                onSelected: (_) {},
                cartCount: CartStore.instance.count,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(_cartButton);
    await tester.pumpAndSettle();

    expect(CartStore.instance.lines.single.skuId, 'only');
    expect(tester.takeException(), isNull);
  });
}

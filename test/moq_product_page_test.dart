import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/home/widgets/product_rail.dart'
    show formatRupees;
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

/// Test data only; real ladders come from each product's record.
const _ladder = [
  QuantityTier(minQuantity: 1, price: 20),
  QuantityTier(minQuantity: 10, price: 17),
  QuantityTier(minQuantity: 100, price: 14),
  QuantityTier(minQuantity: 1000, price: 11),
];

final _detail = ProductDetail(
  numIid: '536875038426',
  title: 'Adult diapers, L',
  price: 20,
  rating: 0,
  reviewCount: 0,
  images: const [],
  variants: const [],
  specs: const [],
  description: '',
  tiers: _ladder,
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(
        product: productStub(
          numIid: '536875038426',
          title: 'Adult diapers, L',
          displayPrice: 20,
        ),
        detail: _detail,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.byKey(const ValueKey('quantity-value')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('quantity-value')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.text('Set'));
  await tester.pumpAndSettle();
}

String _buy(num total) => 'Buy · ${formatRupees(total)}';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    stubCatalog();
  });

  tearDown(clearApiStub);

  testWidgets('the buy bar is quantity x the rung, at every boundary', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(_buy(20)), findsOneWidget, reason: '1 piece at 20');

    for (final (quantity, unit) in const [
      (9, 20),
      (10, 17),
      (99, 17),
      (100, 14),
      (999, 14),
      (1000, 11),
      (5000, 11),
    ]) {
      await _type(tester, '$quantity');
      expect(
        find.text(_buy(quantity * unit)),
        findsOneWidget,
        reason: '$quantity pieces at $unit',
      );
    }
  });

  testWidgets('what reaches the cart is priced the same', (tester) async {
    await _pump(tester);
    await _type(tester, '1000');
    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();

    final line = CartStore.instance.lines.single;
    expect(line.quantity, 1000);
    expect(line.unitPrice, 11);
    expect(line.lineTotal, 11000);
  });

  testWidgets('a quantity that cannot be ordered is refused, with why', (
    tester,
  ) async {
    await _pump(tester);
    for (final (text, message) in [
      ('0', 'The minimum order is 1.'),
      ('abc', 'Enter a whole number of pieces.'),
      ('${CartStore.maxPerLine + 1}', 'The most one order can take is '),
    ]) {
      await tester.tap(find.byKey(const ValueKey('quantity-value')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, text);
      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();
      expect(find.textContaining(message), findsOneWidget, reason: text);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    // Nothing changed the price.
    expect(find.text(_buy(20)), findsOneWidget);
  });
}

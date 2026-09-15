import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

/// A real shape of ladder: the price of one falls as the order grows. Test
/// data only -- every real ladder comes from the product's own record.
const _ladder = [
  QuantityTier(minQuantity: 1, price: 373),
  QuantityTier(minQuantity: 90, price: 350),
  QuantityTier(minQuantity: 7200, price: 345),
];

final _detail = ProductDetail(
  numIid: '45739871978',
  title: 'Adult care pad',
  price: 373,
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
          numIid: '45739871978',
          title: 'Adult care pad',
          displayPrice: 373,
        ),
        detail: _detail,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _setQuantity(WidgetTester tester, String value) async {
  await tester.ensureVisible(find.byKey(const ValueKey('quantity-value')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('quantity-value')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, value);
  await tester.tap(find.text('Set'));
  await tester.pumpAndSettle();
}

/// The headline figure, which is drawn as "Rs. " plus the digits.
Finder _headline(String digits) => find.byWidgetPredicate((widget) {
  if (widget is! Text) return false;
  final span = widget.textSpan;
  if (span is! TextSpan) return false;
  final children = span.children;
  if (children == null || children.length != 2) return false;
  final prefix = children.first;
  final figure = children.last;
  return prefix is TextSpan &&
      prefix.text == 'Rs. ' &&
      figure is TextSpan &&
      figure.text == digits;
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    stubCatalog();
  });

  tearDown(clearApiStub);

  testWidgets('the headline price is the rung the quantity reaches', (
    tester,
  ) async {
    await _pump(tester);
    expect(_headline('373'), findsOneWidget, reason: 'one piece');

    await _setQuantity(tester, '89');
    expect(_headline('373'), findsOneWidget, reason: 'still the first rung');

    await _setQuantity(tester, '90');
    expect(_headline('350'), findsOneWidget, reason: 'the 90+ rung');
    expect(_headline('373'), findsNothing, reason: 'and not the old figure');

    await _setQuantity(tester, '7200');
    expect(_headline('345'), findsOneWidget, reason: 'the 7,200+ rung');

    await _setQuantity(tester, '1');
    expect(_headline('373'), findsOneWidget, reason: 'and back again');
  });

  testWidgets('the VAT line is the tax inside that same price', (tester) async {
    await _pump(tester);
    // 13% inside 373 is 43; inside 350 it is 40. The line must not keep
    // quoting the tax on a price nobody is being charged.
    expect(find.text('Includes Rs. 43 VAT'), findsOneWidget);

    await _setQuantity(tester, '90');
    expect(find.text('Includes Rs. 40 VAT'), findsOneWidget);
    expect(find.text('Includes Rs. 43 VAT'), findsNothing);
  });
}

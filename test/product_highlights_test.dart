import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/catalog.dart';

/// A listing whose highlights carry the facts a shopper scans for.
ProductDetail _detail() {
  final body = Map<String, dynamic>.from(detailResponseJson);
  final item = Map<String, dynamic>.from(body['item'] as Map<String, dynamic>);
  item['props'] = const [
    {'name': 'Brand', 'value': 'Other/other'},
    {'name': 'Model', 'value': 'T50'},
  ];
  body['item'] = item;
  return ProductDetail.fromApi(body, fallback: sampleProduct);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductDetailScreen(product: sampleProduct, detail: _detail()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    await tester.pumpAndSettle();
  }

  group('the facts in Highlights are legible at a glance', () {
    testWidgets('the value is 16pt and bold', (tester) async {
      // Brand and model are what somebody is scanning this block for, so
      // they are the largest thing in it rather than 14pt at half weight.
      await pump(tester);
      await reveal(tester, find.text('Other/other'));

      final value = tester.widget<Text>(find.text('Other/other'));
      expect(value.style?.fontSize, 16);
      expect(value.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('the caption above it is 12pt and stays muted', (tester) async {
      // It names the fact rather than being the fact, so it grows a step but
      // keeps its weight and colour -- otherwise the pair reads as two
      // headings and neither leads.
      await pump(tester);
      await reveal(tester, find.text('Brand'));

      final label = tester.widget<Text>(find.text('Brand'));
      expect(label.style?.fontSize, 12);
      expect(label.style?.fontWeight, isNot(FontWeight.w700));
    });

    testWidgets('every highlight the seller sent is still shown', (
      tester,
    ) async {
      // Bigger type must not have cost a row.
      await pump(tester);
      await reveal(tester, find.text('Brand'));

      expect(find.text('Brand'), findsOneWidget);
      expect(find.text('Other/other'), findsOneWidget);
      expect(find.text('Model'), findsOneWidget);
      expect(find.text('T50'), findsWidgets);
    });

    testWidgets('it still lays out two to a row', (tester) async {
      // The grid is unchanged: same two columns, same gap.
      await pump(tester);
      await reveal(tester, find.text('Brand'));

      final brand = tester.getTopLeft(find.text('Brand'));
      final model = tester.getTopLeft(find.text('Model'));
      expect(model.dy, brand.dy, reason: 'the pair share a row');
      expect(model.dx, greaterThan(brand.dx), reason: 'and sit side by side');
    });
  });
}

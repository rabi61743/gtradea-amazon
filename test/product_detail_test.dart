import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

/// Pumps on a phone-shaped surface. The default test window is 600x800,
/// which the gallery alone very nearly fills, so anything under it stays
/// unbuilt and every finder below the fold misses.
Future<void> _pumpDetail(WidgetTester tester, {ProductDetail? product}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(
    product == null
        ? const ProductDetailScreen()
        : ProductDetailScreen(product: product),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

const _base = ProductDetail(
  title: 'Test product',
  price: 1000,
  rating: 4,
  reviewCount: 10,
  images: ['https://example.invalid/a.jpg'],
  variants: [
    ProductVariant(label: 'Red', imageUrl: 'https://example.invalid/r.jpg'),
    ProductVariant(
      label: 'Blue',
      imageUrl: 'https://example.invalid/b.jpg',
      inStock: false,
    ),
  ],
  specs: [ProductSpec('Material', 'Cotton')],
  description: 'A short description.',
);

void main() {
  group('ProductDetail', () {
    test('claims a discount only when the list price is genuinely higher', () {
      expect(_base.discountPercent, isNull);

      const higher = ProductDetail(
        title: 't',
        price: 1000,
        listPrice: 1250,
        rating: 4,
        reviewCount: 1,
        images: [],
        variants: [],
        specs: [],
        description: '',
      );
      expect(higher.discountPercent, 20);

      const notASaving = ProductDetail(
        title: 't',
        price: 1000,
        listPrice: 900,
        rating: 4,
        reviewCount: 1,
        images: [],
        variants: [],
        specs: [],
        description: '',
      );
      expect(notASaving.discountPercent, isNull);
    });

    test('back-solves the VAT already inside the price', () {
      // 13/113 of 1000, the same rule both storefronts use.
      expect(_base.vatIncluded, 115);
    });

    test('drops a VAT note that would round to nothing', () {
      // 13/113 of 3 is 0.35, which rounds to nothing.
      const cheap = ProductDetail(
        title: 't',
        price: 3,
        rating: 4,
        reviewCount: 1,
        images: [],
        variants: [],
        specs: [],
        description: '',
      );
      expect(cheap.vatIncluded, isNull);
    });
  });

  testWidgets('shows price, saving and the tax it includes', (tester) async {
    await _pumpDetail(tester);

    expect(find.text('Rs. 1,130'), findsOneWidget);
    expect(find.text('Rs. 1,568'), findsOneWidget);
    expect(find.text('-28%'), findsOneWidget);
    expect(find.text('Includes Rs. 130 VAT'), findsOneWidget);
  });

  testWidgets('names the selected colour rather than only highlighting it',
      (tester) async {
    await _pumpDetail(tester);

    expect(find.text('Blush pink'), findsOneWidget);
  });

  testWidgets('an out-of-stock variant stays visible but is not selectable',
      (tester) async {
    await _pumpDetail(tester, product: _base);

    expect(find.text('Sold out'), findsOneWidget);
    expect(find.text('Red'), findsOneWidget);

    // Tapping the sold-out swatch must not change the selection.
    await tester.tap(find.text('Sold out'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Red'), findsOneWidget);
  });

  testWidgets('the buy bar tracks quantity so the total is never a surprise',
      (tester) async {
    await _pumpDetail(tester);

    expect(find.text('Buy · Rs. 1,130'), findsOneWidget);

    // The stepper sits low enough to fall under the pinned buy bar, where
    // a tap lands on the bar instead.
    await tester.scrollUntilVisible(find.text('Quantity'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pump();

    expect(find.text('Buy · Rs. 2,260'), findsOneWidget);
  });

  testWidgets('quantity cannot go below the minimum order', (tester) async {
    await _pumpDetail(tester);

    // The stepper sits low enough to fall under the pinned buy bar, where
    // a tap lands on the bar instead.
    await tester.scrollUntilVisible(find.text('Quantity'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    // byTooltip resolves to the tooltip wrapper, not the button inside it.
    final fewer = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove),
    );
    expect(fewer.onPressed, isNull, reason: "min order is 1");
  });

  testWidgets('the description expands on request', (tester) async {
    await _pumpDetail(tester);

    await tester.scrollUntilVisible(find.text('Read more'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Read more'), findsOneWidget);
    await tester.tap(find.text('Read more'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/catalog.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/product_gallery.dart';

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
        ? ProductDetailScreen(product: sampleProduct, detail: sampleDetail)
        : ProductDetailScreen(product: sampleProduct, detail: product),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

const _base = ProductDetail(
  numIid: 'test-product',
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
        numIid: 'test-product',
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
        numIid: 'test-product',
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
        numIid: 'test-product',
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

  testWidgets('shows the price and the tax already inside it', (tester) async {
    await _pumpDetail(tester);

    expect(find.text('Rs. 388'), findsWidgets);
    // 13 percent backed out of the price, not added to it.
    expect(find.text('Includes Rs. 45 VAT'), findsOneWidget);
  });

  testWidgets('no strike-through price is invented', (tester) async {
    // The catalogue publishes one price. A crossed-out figure derived from a
    // markup nobody publishes would be a false saving.
    await _pumpDetail(tester);

    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('names the selected option rather than only highlighting it',
      (tester) async {
    await _pumpDetail(tester);

    expect(find.text('Red'), findsWidgets);
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

    // Two, because the listing has a minimum order of two -- opening below it
    // would make the first tap on Add to cart a refusal.
    expect(find.text('Buy · Rs. 776'), findsOneWidget);

    // The stepper sits low enough to fall under the pinned buy bar, where
    // a tap lands on the bar instead.
    await tester.scrollUntilVisible(find.text('Quantity'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pump();

    // Three at 388.
    expect(find.text('Buy · Rs. 1,164'), findsOneWidget);
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

  testWidgets('Save and Share live in the app bar, not on the photo',
      (tester) async {
    // They used to float on the gallery, which is the reference app pattern
    // and made them invisible against a white-background product shot.
    await _pumpDetail(tester);

    final save = find.byTooltip('Save');
    expect(save, findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);

    expect(
      find.ancestor(of: save, matching: find.byType(SliverAppBar)),
      findsOneWidget,
      reason: "actions belong to the app bar",
    );
    expect(
      find.descendant(of: find.byType(ProductGallery), matching: save),
      findsNothing,
      reason: "nothing sits on the photograph",
    );
  });

  testWidgets('the app bar stays pinned, so Save survives a scroll',
      (tester) async {
    await _pumpDetail(tester);

    await tester.scrollUntilVisible(find.text('Specifications'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    // Deep in the page, the actions are still there -- the whole point of
    // pinning rather than letting the bar scroll away.
    expect(find.byTooltip('Save'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
  });

  testWidgets('sales and seller read beside the title', (tester) async {
    await _pumpDetail(tester);

    expect(find.text('111.3k sold'), findsOneWidget);
    expect(find.text('Yiwu Match Factory'), findsOneWidget);
  });

  testWidgets('an unrated product shows no stars rather than zero stars',
      (tester) async {
    // Nothing in this catalogue carries a rating. "0.0 (0)" beside a title
    // reads as rated badly, which is the opposite of the truth.
    await _pumpDetail(tester);

    expect(find.text('0.0'), findsNothing);
    expect(find.text('(0)'), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
  });
}

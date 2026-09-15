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
  await tester.pumpWidget(
    _wrap(
      product == null
          ? ProductDetailScreen(product: sampleProduct, detail: sampleDetail)
          : ProductDetailScreen(product: sampleProduct, detail: product),
    ),
  );
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

/// A listing whose price is the seller's bulk ladder and nothing else: the
/// variants carry no price of their own, so [ProductDetail.priceAt] is what
/// decides the figure and the ladder is safe to draw.
const _laddered = ProductDetail(
  numIid: 'test-product',
  title: 'Test product',
  price: 404,
  rating: 4,
  reviewCount: 10,
  images: ['https://example.invalid/a.jpg'],
  unitLabel: 'pairs',
  variants: [],
  tiers: [
    QuantityTier(minQuantity: 1, price: 404),
    QuantityTier(minQuantity: 100, price: 398),
    QuantityTier(minQuantity: 10000, price: 386),
  ],
  specs: [ProductSpec('Material', 'Cotton')],
  description: 'A short description.',
);

void main() {
  group('the bulk ladder', () {
    test('the price steps down as the quantity crosses each rung', () {
      // The same function the cart line and the buy bar call, so this is the
      // figure that is actually charged rather than one drawn beside it.
      expect(_laddered.priceAt(1), 404);
      expect(_laddered.priceAt(99), 404);
      expect(_laddered.priceAt(100), 398);
      expect(_laddered.priceAt(9999), 398);
      expect(_laddered.priceAt(10000), 386);
    });

    testWidgets('every rung the seller published is drawn, in its own unit', (
      tester,
    ) async {
      await _pumpDetail(tester, product: _laddered);

      // Bands, not thresholds: the top of each is the next rung less one, and
      // the last has no top.
      expect(find.text('1 - 99 pairs'), findsOneWidget);
      expect(find.text('100 - 9,999 pairs'), findsOneWidget);
      expect(find.text('10,000+ pairs'), findsOneWidget);
    });

    testWidgets('nothing is drawn for a listing the seller sent no ladder for', (
      tester,
    ) async {
      await _pumpDetail(tester, product: _base);

      expect(find.textContaining(' - '), findsNothing);
    });
  });

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

    expect(find.text('Rs. 388', findRichText: true), findsWidgets);
    // 13 percent backed out of the price, not added to it.
    expect(find.text('Includes Rs. 45 VAT'), findsOneWidget);
  });

  testWidgets('no strike-through price is invented', (tester) async {
    // The catalogue publishes one price. A crossed-out figure derived from a
    // markup nobody publishes would be a false saving.
    await _pumpDetail(tester);

    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('names the selected option rather than only highlighting it', (
    tester,
  ) async {
    await _pumpDetail(tester);

    expect(find.text('Red'), findsWidgets);
  });

  testWidgets('an out-of-stock variant stays visible but is not selectable', (
    tester,
  ) async {
    await _pumpDetail(tester, product: _base);

    expect(find.text('Sold out'), findsOneWidget);
    // Twice over: the swatch, and the summary of what is being bought.
    expect(find.text('Red'), findsNWidgets(2));

    // Tapping the sold-out swatch must not change the selection.
    await tester.tap(find.text('Sold out'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Red'), findsNWidgets(2));
  });

  testWidgets('a listing with no price asks for one instead of saying Rs. 0', (
    tester,
  ) async {
    // A catalogue row that carries no price seeds the preview record with
    // zero, and the page used to print that as "Rs. 0" -- telling the shopper
    // the product was free. Nothing in this catalogue is free, so zero means
    // the price is not known yet.
    const priceless = ProductDetail(
      numIid: 'test-product',
      title: 'Test product',
      price: 0,
      rating: 4,
      reviewCount: 10,
      images: ['https://example.invalid/a.jpg'],
      variants: [
        ProductVariant(label: 'Red', imageUrl: 'https://example.invalid/r.jpg'),
      ],
      specs: [],
      description: '',
    );

    await _pumpDetail(tester, product: priceless);

    expect(find.text('Rs. 0'), findsNothing);
    expect(find.textContaining('Buy · Rs. 0'), findsNothing);
    expect(find.text('Select an option'), findsWidgets);
  });

  testWidgets('a priceless listing cannot be added to the cart', (
    tester,
  ) async {
    // The displayed price and the price charged have to be the same number.
    // Letting a Rs. 0 line through would be charged as free at checkout.
    const priceless = ProductDetail(
      numIid: 'test-product',
      title: 'Test product',
      price: 0,
      rating: 4,
      reviewCount: 10,
      images: ['https://example.invalid/a.jpg'],
      variants: [
        ProductVariant(label: 'Red', imageUrl: 'https://example.invalid/r.jpg'),
      ],
      specs: [],
      description: '',
    );

    await _pumpDetail(tester, product: priceless);

    final addToCart = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Add to cart'),
    );
    expect(addToCart.onPressed, isNull, reason: 'nothing priced to add');
  });

  testWidgets('a priced listing still shows its price and can be bought', (
    tester,
  ) async {
    // The guard above must not catch an ordinary listing.
    await _pumpDetail(tester);

    expect(find.text('Buy · Rs. 776'), findsOneWidget);
    expect(find.text('Select an option'), findsNothing);

    final addToCart = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Add to cart'),
    );
    expect(addToCart.onPressed, isNotNull);
  });

  testWidgets('the buy bar tracks quantity so the total is never a surprise', (
    tester,
  ) async {
    await _pumpDetail(tester);

    // Two, because the listing has a minimum order of two -- opening below it
    // would make the first tap on Add to cart a refusal.
    expect(find.text('Buy · Rs. 776'), findsOneWidget);

    // The stepper sits low enough to fall under the pinned buy bar, where
    // a tap lands on the bar instead.
    await tester.scrollUntilVisible(
      find.text('Quantity'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.scrollUntilVisible(
      find.text('Quantity'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Pumped rather than settled: the gallery rotates its photographs on a
    // timer now, so this page never comes to rest and pumpAndSettle would wait
    // out its ten-minute limit.
    await tester.pump(const Duration(milliseconds: 300));

    // byTooltip resolves to the tooltip wrapper, not the button inside it.
    final fewer = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove),
    );
    expect(fewer.onPressed, isNull, reason: "min order is 1");
  });

  testWidgets('the description expands on request', (tester) async {
    await _pumpDetail(tester);

    await tester.scrollUntilVisible(
      find.text('Read more'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Read more'), findsOneWidget);
    await tester.tap(find.text('Read more'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('Save and Share live in the app bar, not on the photo', (
    tester,
  ) async {
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

  testWidgets('the app bar stays pinned, so Save survives a scroll', (
    tester,
  ) async {
    await _pumpDetail(tester);

    await tester.scrollUntilVisible(
      find.text('Specifications'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    // Pumped rather than settled, for the same reason as above.
    await tester.pump(const Duration(milliseconds: 300));

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

  testWidgets('a product with no options renders without a picker', (
    tester,
  ) async {
    // The page opens on the tapped card's data, which has no SKUs yet, and
    // plenty of listings sell one thing in one form. Indexing the empty option
    // list crashed the whole screen.
    await _pumpDetail(
      tester,
      product: sampleDetail.copyWith(similar: const []),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _wrap(
        ProductDetailScreen(
          product: sampleProduct,
          detail: ProductDetail.fromProduct(sampleProduct),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Add to cart'), findsOneWidget);
  });

  testWidgets('an unrated product shows no stars rather than zero stars', (
    tester,
  ) async {
    // Nothing in this catalogue carries a rating. "0.0 (0)" beside a title
    // reads as rated badly, which is the opposite of the truth.
    await _pumpDetail(tester);

    expect(find.text('0.0'), findsNothing);
    expect(find.text('(0)'), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
  });
}

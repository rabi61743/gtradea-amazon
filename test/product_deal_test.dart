import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/flash_sale/data/flash_sale.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/product_deal_banner.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/product_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

const _product = Product(
  numIid: 'deal-product',
  title: 'Smart Watch',
  displayPrice: 2999,
);

const _detail = ProductDetail(
  numIid: 'deal-product',
  title: 'Smart Watch',
  price: 2999,
  rating: 0,
  reviewCount: 0,
  images: ['https://example.invalid/watch.jpg'],
  description: 'A watch.',
  variants: [],
  specs: [],
);

FlashSaleItem _item({int percent = 40, int? stock = 36, int? sold = 64}) =>
    FlashSaleItem(
      product: _product,
      salePrice: 2999,
      listPrice: 4999,
      discountPercent: percent,
      stock: stock,
      soldPercent: sold,
    );

Future<void> pumpDetail(
  WidgetTester tester, {
  ProductDeal? deal,
  DateTime Function()? now,
}) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(
        product: _product,
        detail: _detail,
        deal: deal,
        now: now,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    stubCatalog();
  });

  group('a product opened from a deal', () {
    testWidgets('carries the discount, the deadline and the was-price', (
      tester,
    ) async {
      final now = DateTime(2026, 8, 25, 12);
      await pumpDetail(
        tester,
        deal: ProductDeal(
          item: _item(),
          endsAt: now.add(const Duration(hours: 2, minutes: 35, seconds: 41)),
        ),
        now: () => now,
      );

      expect(find.byType(ProductDealBadge), findsOneWidget);
      expect(find.text('-40%'), findsWidgets);
      expect(find.text('Flash Sales'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('35'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      expect(find.text('Rs. 4,999'), findsOneWidget);
      expect(find.text('64% sold'), findsOneWidget);
      expect(find.textContaining('Stock left:'), findsOneWidget);
    });

    testWidgets('the gallery and the page chrome are left where they were', (
      tester,
    ) async {
      final now = DateTime(2026, 8, 25, 12);
      await pumpDetail(
        tester,
        deal: ProductDeal(
          item: _item(),
          endsAt: now.add(const Duration(hours: 1)),
        ),
        now: () => now,
      );

      // Share and Save stay in the app bar, where every other product page
      // keeps them -- the badge is laid over the gallery, not in place of them.
      expect(find.byTooltip('Share'), findsOneWidget);
      expect(find.byTooltip('Save'), findsOneWidget);
      expect(find.byTooltip('Cart'), findsOneWidget);
      expect(find.byType(ProductGallery), findsOneWidget);
      expect(find.text('Add to cart'), findsOneWidget);

      // The band sits under the gallery, not over it.
      final gallery = tester.getRect(find.byType(ProductGallery));
      final band = tester.getRect(find.byType(ProductDealBanner));
      expect(band.top, greaterThanOrEqualTo(gallery.bottom - 1));
    });
  });

  group('a product opened from anywhere else', () {
    testWidgets('looks exactly as it did before deals existed', (tester) async {
      await pumpDetail(tester);

      expect(find.byType(ProductDealBanner), findsNothing);
      expect(find.byType(ProductDealBadge), findsNothing);
      expect(find.byType(ProductDealStock), findsNothing);
      expect(find.textContaining('% sold'), findsNothing);
      expect(find.textContaining('Stock left:'), findsNothing);
      // No struck price is invented for a product nobody put on offer.
      expect(find.text('Rs. 4,999'), findsNothing);

      // And everything that was always there still is.
      expect(find.byTooltip('Share'), findsOneWidget);
      expect(find.byType(ProductGallery), findsOneWidget);
      expect(find.text('Add to cart'), findsOneWidget);
      expect(find.text('Rs. 2,999'), findsWidgets);
    });
  });

  group('when the sale runs out under the shopper', () {
    testWidgets('the badge, the band and the was-price all go', (tester) async {
      var now = DateTime(2026, 8, 25, 12);
      await pumpDetail(
        tester,
        deal: ProductDeal(
          item: _item(),
          endsAt: now.add(const Duration(seconds: 2)),
        ),
        now: () => now,
      );
      expect(find.byType(ProductDealBanner), findsOneWidget);
      expect(find.text('Rs. 4,999'), findsOneWidget);

      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Every one of these is a claim about a price no longer being offered.
      expect(find.byType(ProductDealBanner), findsNothing);
      expect(find.byType(ProductDealBadge), findsNothing);
      expect(find.text('Rs. 4,999'), findsNothing);
      expect(find.textContaining('Stock left:'), findsNothing);

      // The product itself is untouched and still buyable.
      expect(find.text('Rs. 2,999'), findsWidgets);
      expect(find.text('Add to cart'), findsOneWidget);
    });
  });

  group('the cart agrees with the page', () {
    testWidgets('adding from a deal page carries the same was-price', (
      tester,
    ) async {
      final now = DateTime(2026, 8, 25, 12);
      await pumpDetail(
        tester,
        deal: ProductDeal(
          item: _item(),
          endsAt: now.add(const Duration(hours: 1)),
        ),
        now: () => now,
      );

      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();

      final line = CartStore.instance.lineFor('deal-product');
      expect(line, isNotNull);
      expect(line!.unitPrice, 2999);
      // A cart that struck through nothing, beside a page that struck through
      // Rs. 4,999, would read as the discount having been lost on the way.
      expect(line.listPrice, 4999);
    });
  });

  group('the was-price follows what is actually being charged', () {
    test('is rescaled from the current unit price, not copied', () {
      // The page prices by variant and quantity tier. A struck price copied
      // from the card would stop matching the moment either changed, and the
      // badge beside it would claim a percentage the two numbers do not show.
      const deal = ProductDeal(
        item: FlashSaleItem(
          product: _product,
          salePrice: 2999,
          listPrice: 4999,
          discountPercent: 40,
        ),
      );

      expect(deal.listPriceFor(2999), closeTo(4998, 2));
      // A cheaper tier gets a proportionally cheaper "was".
      expect(deal.listPriceFor(600), closeTo(1000, 1));
    });

    test('claims nothing when the percentage is nonsense', () {
      const zero = ProductDeal(
        item: FlashSaleItem(
          product: _product,
          salePrice: 100,
          listPrice: 100,
          discountPercent: 0,
        ),
      );
      expect(zero.listPriceFor(100), isNull);
    });
  });
}

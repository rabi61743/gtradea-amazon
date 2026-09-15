import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/data/product_repository.dart';
import 'package:gtradea_amazon/features/product/data/storefront_config.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/product_gallery.dart';
import 'package:gtradea_amazon/features/product/widgets/product_summary_card.dart';

import 'support/api.dart';
import 'support/catalog.dart';

/// The card, and only the card: the page names the same product above it.
Finder _inCard(Finder matching) =>
    find.descendant(of: find.byType(ProductSummaryCard), matching: matching);

Future<void> _pump(WidgetTester tester, {ProductDetail? detail}) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(
        product: sampleProduct,
        detail: detail ?? sampleDetail,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stubCatalog();
    CartStore.instance.resetForTest();
    StorefrontConfigRepository.instance.resetForTest();
    ProductRepository.instance.clearDetailCache();
  });

  tearDown(clearApiStub);

  testWidgets('opens with the photographs, above the name', (tester) async {
    await _pump(tester);

    // The gallery is inside the card now, at the top of it: the same widget,
    // the same pictures the record carried, above the product's name.
    final gallery = find.byType(ProductGallery);
    expect(gallery, findsOneWidget);

    final photos = tester.getRect(gallery);
    final name = tester.getRect(find.textContaining('Phosphorus Paper').first);
    final card = tester.getRect(
      find
          .ancestor(
            of: find.textContaining('Phosphorus Paper').first,
            matching: find.byType(Container),
          )
          .last,
    );

    expect(photos.bottom, lessThanOrEqualTo(name.top), reason: 'above it');
    // Inside the card, and the full width of it -- to its border, which is the
    // one point between the photograph and the card's edge.
    expect(photos.top, greaterThanOrEqualTo(card.top - 1));
    expect(photos.left, closeTo(card.left, 1));
    expect(photos.right, closeTo(card.right, 1));
  });

  testWidgets('sits in a card that takes 97% of the page, centred', (
    tester,
  ) async {
    await _pump(tester);

    // The measure every card down this page shares: a margin that is a share
    // of the width rather than a fixed inset, so it sits right on a phone, a
    // tablet and a desktop window. It used to run edge to edge.
    final card = find
        .ancestor(
          of: find.textContaining('Phosphorus Paper').first,
          matching: find.byType(Container),
        )
        .last;
    final rect = tester.getRect(card);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    expect(rect.width, closeTo(width * cardWidthFactor, 0.5));
    expect(rect.left, closeTo(width - rect.right, 0.5), reason: 'centred');
  });

  testWidgets('sums up what is about to be bought', (tester) async {
    await _pump(tester);

    expect(find.byType(ProductSummaryCard), findsOneWidget);
    // The product's own name and picture, from the record the page fetched.
    expect(_inCard(find.textContaining('Phosphorus Paper')), findsOneWidget);
    expect(_inCard(find.byType(Image)), findsOneWidget);

    // The seller's minimum is where the stepper starts, so that is the count
    // the card opens on -- and the line total follows from it.
    expect(_inCard(find.textContaining('Qty: 2')), findsOneWidget);
    expect(_inCard(find.textContaining('Rs. 388')), findsOneWidget);
    expect(_inCard(find.text('Rs. 776')), findsOneWidget);
  });

  testWidgets('and follows the quantity as it changes', (tester) async {
    await _pump(tester);

    await tester.ensureVisible(find.byType(ProductSummaryCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(_inCard(find.textContaining('Qty: 3')), findsOneWidget);
    expect(_inCard(find.text('Rs. 1,164')), findsOneWidget);
  });

  testWidgets('and the option the shopper picked', (tester) async {
    await _pump(tester);

    // The record's first in-stock option is the one the page opens on.
    expect(_inCard(find.text('Red')), findsOneWidget);
  });

  testWidgets('says nothing about a price the catalogue does not have', (
    tester,
  ) async {
    // Rs. 0 would read as free rather than as unknown, which is what it is.
    // A real record, priced at nothing -- which is what this catalogue
    // returns when the pricing engine has not answered for a listing.
    await _pump(
      tester,
      detail: const ProductDetail(
        numIid: '639278524639',
        title: 'Phosphorus Paper for Matches',
        price: 0,
        rating: 0,
        reviewCount: 0,
        images: [],
        variants: [],
        specs: [],
        description: '',
      ),
    );

    expect(_inCard(find.textContaining('each')), findsNothing);
    expect(_inCard(find.text('—')), findsOneWidget);
  });
}

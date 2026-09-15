import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/data/storefront_config.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/logistics_trust_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';

/// The scale the page is set in, pinned so a copyWith somewhere cannot quietly
/// move a heading a point away from the heading two cards below it.
const _slate = AppColors.himalayanSlate;
const _muted = AppColors.mutedForegroundLight;
const _trustBlue = AppColors.trustBlue;

ProductDetail _detail() => ProductDetail(
  numIid: '900',
  // Long on purpose: wholesale titles run to forty words of keywords.
  title:
      'Braided Outer Sheath Data Cable with Elbow Connector Type-Cm to Dc '
      '3.5Trrs Black Outer Sheath Data Connection Cable Typec for Every '
      'Workshop and Every Bench, Boxed in Fifties',
  price: 2340,
  rating: 0,
  reviewCount: 0,
  images: const ['https://img.example/1.jpg'],
  variants: const [],
  specs: const [ProductSpec('Brand', 'Hongkuang')],
  highlights: const [ProductSpec('Brand', 'Hongkuang')],
  description: 'A braided cable, boxed in fifties, shipped from Yiwu.',
  minOrder: 500,
  sellerName: 'Hongkuang Electronics',
  soldCount: 1200,
  assurances: storeAssurances,
);

/// The style actually painted on the text at [finder].
TextStyle _styleOf(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).style!;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(product: sampleProduct, detail: _detail()),
    ),
  );
  // Pumped rather than settled: the gallery rotates on a timer, so this page
  // never comes to rest.
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    StorefrontConfigRepository.instance.resetForTest();
    stubCatalog();
  });

  tearDown(clearApiStub);

  group('what the product says about itself', () {
    testWidgets('the name is 16/600 slate, and stops after three lines', (
      tester,
    ) async {
      await _pump(tester);

      // The heading, not the summary card lower down, which names the
      // same product.
      final title = tester.widget<Text>(
        find.textContaining('Braided Outer').first,
      );
      expect(title.style?.fontSize, 16);
      expect(title.style?.fontWeight, FontWeight.w600);
      expect(title.style?.color, _slate);
      expect(title.style?.height, 1.3);
      // A title this long would otherwise push the price off the first screen.
      expect(title.maxLines, 3);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('sold and supplier are 12/400 muted grey', (tester) async {
      await _pump(tester);

      for (final finder in [
        find.text('1.2k sold'),
        find.text('Hongkuang Electronics'),
      ]) {
        final style = _styleOf(tester, finder);
        expect(style.fontSize, 12, reason: 'size');
        expect(style.fontWeight, FontWeight.w400, reason: 'weight');
        expect(style.color, _muted, reason: 'colour');
      }
    });

    testWidgets('the price is 24/700 Trust Blue, its currency a step down', (
      tester,
    ) async {
      await _pump(tester);

      // One line of text in two sizes, so the prefix rides the digits.
      // Matched on the spans rather than on the string: the rails further
      // down the page carry the same figure as plain text.
      final rich = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.textSpan is TextSpan &&
              (w.textSpan! as TextSpan).toPlainText() == 'Rs. 2,340',
        ),
      );
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();

      expect(spans.first.text, 'Rs. ');
      expect(spans.first.style?.fontSize, 18);
      expect(spans.first.style?.fontWeight, FontWeight.w700);
      expect(spans.first.style?.color, _trustBlue);

      expect(spans.last.text, '2,340');
      expect(spans.last.style?.fontSize, 24);
      expect(spans.last.style?.fontWeight, FontWeight.w700);
      expect(spans.last.style?.color, _trustBlue);
    });
  });

  group('quantity and the order floor', () {
    testWidgets('the label is 13/600 and the value 14/600, both slate', (
      tester,
    ) async {
      await _pump(tester);
      await _reveal(tester, find.text('Quantity'));

      final label = _styleOf(tester, find.text('Quantity'));
      expect(label.fontSize, 13);
      expect(label.fontWeight, FontWeight.w600);
      expect(label.color, _slate);

      final value = _styleOf(tester, find.text('500'));
      expect(value.fontSize, 14);
      expect(value.fontWeight, FontWeight.w600);
      expect(value.color, _slate);
    });

    testWidgets('and the minimum names itself quietly, then says the figure', (
      tester,
    ) async {
      await _pump(tester);

      final pill = tester.widget<Text>(find.textContaining('Min. order:'));
      final spans = (pill.textSpan! as TextSpan).children!.cast<TextSpan>();

      // The label: 11/400 muted grey.
      expect(spans.first.text, 'Min. order: ');
      expect(spans.first.style?.fontSize, 11);
      expect(spans.first.style?.fontWeight, FontWeight.w400);
      expect(spans.first.style?.color, _muted);

      // The figure: the same size, a step heavier and in the foreground, so it
      // leads without the pill growing.
      expect(spans.last.text, '500 pcs');
      expect(spans.last.style?.fontSize, 11);
      expect(spans.last.style?.fontWeight, FontWeight.w600);
      expect(spans.last.style?.color, _slate);
    });
  });

  group('the logistics block', () {
    testWidgets('title 14/600 slate, dates 13/600 blue, benefits 11/500', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LogisticsTrustCard(
              guarantee: const DeliveryGuarantee(weeksMin: 3, weeksMax: 5),
              assurances: storeAssurances,
              now: () => DateTime(2026, 8, 28),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final title = _styleOf(
        tester,
        find.text('Standard gtradea.com Logistics'),
      );
      expect(title.fontSize, 14);
      expect(title.fontWeight, FontWeight.w600);
      expect(title.color, _slate);

      // The label names the dates rather than being them, so it is held
      // back while they keep the blue.
      final label = _styleOf(tester, find.text('Guaranteed delivery:'));
      expect(label.fontSize, 13);
      expect(label.fontWeight, FontWeight.w400);
      expect(label.color, _muted);

      final dates = _styleOf(tester, find.text('Sep 18 – Oct 2'));
      expect(dates.fontSize, 13);
      expect(dates.fontWeight, FontWeight.w600);
      expect(dates.color, _trustBlue);

      final benefit = _styleOf(tester, find.text('Cash on delivery'));
      expect(benefit.fontSize, 11);
      expect(benefit.fontWeight, FontWeight.w500);
      expect(benefit.color, _slate);
    });
  });

  group('the detail cards', () {
    testWidgets('headings are 15/700 slate', (tester) async {
      await _pump(tester);
      await _reveal(tester, find.text('Highlights'));

      for (final heading in ['Highlights', 'Description']) {
        final style = _styleOf(tester, find.text(heading));
        expect(style.fontSize, 15, reason: heading);
        expect(style.fontWeight, FontWeight.w700, reason: heading);
        expect(style.color, _slate, reason: heading);
      }
    });

    testWidgets('a fact is 11/400 muted over 14/600 slate', (tester) async {
      await _pump(tester);
      await _reveal(tester, find.text('Highlights'));

      final label = _styleOf(tester, find.text('Brand'));
      expect(label.fontSize, 11);
      expect(label.fontWeight, FontWeight.w400);
      expect(label.color, _muted);

      final value = _styleOf(tester, find.text('Hongkuang'));
      expect(value.fontSize, 14);
      expect(value.fontWeight, FontWeight.w600);
      expect(value.color, _slate);
    });

    testWidgets('the description is 13/400 on a 1.45 line', (tester) async {
      await _pump(tester);
      await _reveal(tester, find.text('Description'));

      final style = _styleOf(
        tester,
        find.textContaining('A braided cable, boxed in fifties'),
      );
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.height, 1.45);
    });

    testWidgets('and a panel that opens is labelled 14/600 slate', (
      tester,
    ) async {
      await _pump(tester);
      await _reveal(tester, find.text('Specifications'));

      final style = _styleOf(tester, find.text('Specifications'));
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, _slate);
    });
  });

  group('the buttons at the foot', () {
    testWidgets('are 15/700, and the primary one is white on the blue', (
      tester,
    ) async {
      await _pump(tester);

      final buy = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      const states = <WidgetState>{};
      expect(buy.style?.textStyle?.resolve(states)?.fontSize, 15);
      expect(
        buy.style?.textStyle?.resolve(states)?.fontWeight,
        FontWeight.w700,
      );
      expect(buy.style?.foregroundColor?.resolve(states), Colors.white);

      final add = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(add.style?.textStyle?.resolve(states)?.fontSize, 15);
      expect(
        add.style?.textStyle?.resolve(states)?.fontWeight,
        FontWeight.w700,
      );
    });
  });
}

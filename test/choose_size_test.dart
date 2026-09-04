import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_picker.dart';

/// Sizes, which the seller sends without pictures of their own.
List<ProductVariant> _sizes(int count) => [
  for (var i = 0; i < count; i++)
    ProductVariant(
      label: 'No. ${i + 1} us size',
      imageUrl: '',
      skuId: 'sku-$i',
      axisValues: ['No. ${i + 1} us size'],
    ),
];

/// Colourways, which do have photographs.
List<ProductVariant> _colours(int count) => [
  for (var i = 0; i < count; i++)
    ProductVariant(
      label: 'Colour $i',
      imageUrl: 'https://cdn.invalid/$i.jpg',
      skuId: 'sku-$i',
      axisValues: ['Colour $i'],
    ),
];

void main() {
  /// A 360pt phone, which is the width the row has to work on.
  Future<int?> pump(
    WidgetTester tester, {
    required String label,
    required List<ProductVariant> variants,
    int selected = 0,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: VariantPicker(
            label: label,
            variants: variants,
            selectedIndex: selected,
            onSelected: (i) => picked = i,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return picked;
  }

  group('it says what to do', () {
    testWidgets('Choose Size over a size axis', (tester) async {
      await pump(tester, label: 'Size', variants: _sizes(4));

      expect(find.text('Choose Size'), findsOneWidget);
    });

    testWidgets('Choose Color over a colour axis', (tester) async {
      await pump(tester, label: 'Color', variants: _colours(4));

      expect(find.text('Choose Color'), findsOneWidget);
    });

    testWidgets('and still names the one chosen', (tester) async {
      // The line that was there before the heading was added.
      await pump(tester, label: 'Size', variants: _sizes(4), selected: 1);

      expect(find.text(': '), findsOneWidget);
      expect(find.text('No. 2 us size'), findsWidgets);
    });
  });

  group('sizes are words, colours are pictures', () {
    testWidgets('a size axis draws no photographs', (tester) async {
      // The seller sends the same product shot for S as for XXL, so swatches
      // would be a row of identical thumbnails.
      await pump(tester, label: 'Size', variants: _sizes(4));

      expect(find.byType(Image), findsNothing);
      expect(find.text('No. 1 us size'), findsWidgets);
    });

    testWidgets('a colour axis keeps its swatches', (tester) async {
      await pump(tester, label: 'Color', variants: _colours(4));

      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('an axis with no images at all falls back to words', (
      tester,
    ) async {
      final unpictured = [
        for (final variant in _sizes(3))
          ProductVariant(
            label: variant.label.replaceAll('us size', 'style'),
            imageUrl: '',
            skuId: variant.skuId,
          ),
      ];

      await pump(tester, label: 'Style', variants: unpictured);

      expect(find.byType(Image), findsNothing);
    });
  });

  group('the row scrolls', () {
    /// The row's own scroll position. Asserted on rather than on where a chip
    /// sits, because the list is lazy: a size far enough to the right is not
    /// built at all until it is scrolled to, so "where is it" has no answer.
    ScrollPosition positionOf(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    testWidgets('more sizes than fit leave the row scrollable', (tester) async {
      await pump(tester, label: 'Size', variants: _sizes(12));

      expect(
        positionOf(tester).maxScrollExtent,
        greaterThan(0),
        reason: 'otherwise the rest of this group proves nothing',
      );
    });

    testWidgets('and swiping brings the far ones in', (tester) async {
      await pump(tester, label: 'Size', variants: _sizes(12));
      expect(find.text('No. 12 us size'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('No. 12 us size'),
        160,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();

      expect(positionOf(tester).pixels, greaterThan(0));
      expect(find.text('No. 12 us size'), findsOneWidget);
    });

    testWidgets('a hint says there is more, and goes at the end', (
      tester,
    ) async {
      // A row that ends flush with the screen reads as the end of the row.
      await pump(tester, label: 'Size', variants: _sizes(12));

      double fade() => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(IgnorePointer),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;

      expect(fade(), greaterThan(0), reason: 'more to the right');

      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(-4000, 0),
        6000,
      );
      await tester.pumpAndSettle();

      expect(
        fade(),
        0,
        reason: 'nothing left to hint at, so it never covers the last size',
      );
    });

    testWidgets('a row that fits shows no hint at all', (tester) async {
      // One chip, because the seller's wording is long enough that even two
      // of them overflow a 360pt phone.
      await pump(tester, label: 'Size', variants: _sizes(1));

      expect(positionOf(tester).maxScrollExtent, 0);
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byType(IgnorePointer),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        0,
      );
    });
  });

  group('choosing one', () {
    testWidgets('tapping a size reports its index', (tester) async {
      final taps = <int>[];
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: VariantPicker(
              label: 'Size',
              variants: _sizes(4),
              selectedIndex: 0,
              onSelected: taps.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(
        find.text('No. 3 us size'),
        120,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('No. 3 us size'));
      await tester.pump();

      expect(taps, [2], reason: 'the size swiped into view, not a nearer one');
    });

    testWidgets('a sold-out size cannot be chosen', (tester) async {
      final taps = <int>[];
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: VariantPicker(
              label: 'Size',
              variants: const [
                ProductVariant(label: 'S', imageUrl: '', skuId: 'a'),
                ProductVariant(
                  label: 'M',
                  imageUrl: '',
                  skuId: 'b',
                  inStock: false,
                ),
              ],
              selectedIndex: 0,
              onSelected: taps.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('M'), warnIfMissed: false);
      await tester.pump();

      expect(taps, isEmpty);
    });
  });
}

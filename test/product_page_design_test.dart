import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/assurance_row.dart';

import 'support/catalog.dart';

/// The shape the catalogue returns: the same facts in [specs] and
/// [highlights], with the card deciding how many of them are on screen.
ProductDetail _detail({int minOrder = 500, int specCount = 12}) {
  final specs = [
    for (var i = 0; i < specCount; i++) ProductSpec(_labels[i % 6], 'Value $i'),
  ];

  return ProductDetail(
    numIid: 'test-product',
    title: 'Transparent PVC suction cup',
    price: 2,
    rating: 4,
    reviewCount: 10,
    minOrder: minOrder,
    images: const ['https://example.invalid/a.jpg'],
    variants: const [],
    specs: specs,
    highlights: specs,
    description: 'Transparent PVC suction cup with vertical hole.',
    assurances: storeAssurances,
  );
}

const _labels = [
  'Product category',
  'Brand',
  'Size',
  'Item No.',
  'Origin',
  'Packing method',
];

Future<void> pump(WidgetTester tester, {ProductDetail? detail}) async {
  // Tall enough that the whole page is laid out: the sliver list builds
  // lazily, and a finder for something below the fold matches nothing at all.
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(
        product: sampleProduct,
        detail: detail ?? _detail(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('the minimum order', () {
    testWidgets('is stated on the price row, at the right', (tester) async {
      await pump(tester);

      expect(find.textContaining('Min. order:'), findsOneWidget);
      expect(find.textContaining('500 pcs'), findsOneWidget);

      final price = tester.getRect(find.text('Rs. 2').first);
      final pill = tester.getRect(find.textContaining('Min. order:'));

      // Beside the price rather than under it, and to its right.
      expect(pill.left, greaterThan(price.right));
      expect(pill.top, lessThan(price.bottom));
      expect(pill.bottom, greaterThan(price.top));
    });

    testWidgets('and is absent where a listing sells singles', (tester) async {
      // Nothing to say: "Min. order: 1 pcs" is noise on every retail row.
      await pump(tester, detail: _detail(minOrder: 1));

      expect(find.textContaining('Min. order:'), findsNothing);
    });
  });

  group('the guarantees', () {
    testWidgets('are named, and nothing else', (tester) async {
      await pump(tester);

      await tester.ensureVisible(find.byType(AssuranceRow));
      await tester.pumpAndSettle();

      expect(find.text('7-day returns'), findsOneWidget);
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(find.text('Quality checked'), findsOneWidget);

      // The sub-lines were removed by request. The terms are still one tap
      // away, which is where they were always written out in full.
      expect(find.text('Hassle free'), findsNothing);
      expect(find.text('Pay when you receive'), findsNothing);
      expect(find.text('Trusted products'), findsNothing);
    });

    testWidgets('and the three sit level, in equal thirds', (tester) async {
      await pump(tester);

      await tester.ensureVisible(find.byType(AssuranceRow));
      await tester.pumpAndSettle();

      final cells = [
        for (final label in [
          '7-day returns',
          'Cash on delivery',
          'Quality checked',
        ])
          tester.getRect(find.text(label)),
      ];

      for (final cell in cells.skip(1)) {
        expect(cell.top, closeTo(cells.first.top, 0.5), reason: 'level');
      }

      // Equally spaced: the gap between the first and second centres is the
      // gap between the second and third, so the three read as equal thirds
      // however wide the card is.
      final firstGap = cells[1].center.dx - cells[0].center.dx;
      final secondGap = cells[2].center.dx - cells[1].center.dx;
      expect(secondGap, closeTo(firstGap, 1));
    });

    testWidgets('and still open the terms on a tap', (tester) async {
      // The design change is the card; what the row is for is unchanged.
      await pump(tester);

      await tester.ensureVisible(find.text('7-day returns'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7-day returns'));
      await tester.pumpAndSettle();

      expect(find.textContaining('within 7 days of delivery'), findsOneWidget);
    });
  });

  group('the highlights card', () {
    testWidgets('shows the facts it was given', (tester) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Highlights'));
      await tester.pumpAndSettle();

      expect(find.text('Product category'), findsOneWidget);
      expect(find.text('Brand'), findsOneWidget);
      expect(find.text('Packing method'), findsOneWidget);
    });

    testWidgets('shows six of them, and offers the rest', (tester) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Highlights'));
      await tester.pumpAndSettle();

      // Twelve facts in the record, six on the card.
      expect(find.text('Value 5'), findsOneWidget);
      expect(find.text('Value 6'), findsNothing);
      expect(find.text('View more'), findsOneWidget);
    });

    testWidgets('View more shows the remaining facts, in place', (
      tester,
    ) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Highlights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View more'));
      await tester.pumpAndSettle();

      expect(find.text('Value 6'), findsOneWidget);
      expect(find.text('Value 11'), findsOneWidget);
      // The first six are still there: it expanded rather than paged.
      expect(find.text('Value 0'), findsOneWidget);
    });

    testWidgets('and View less puts it back', (tester) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Highlights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View more'));
      await tester.pumpAndSettle();

      expect(find.text('View more'), findsNothing);
      expect(find.text('View less'), findsOneWidget);

      await tester.tap(find.text('View less'));
      await tester.pumpAndSettle();

      expect(find.text('Value 6'), findsNothing);
      expect(find.text('View more'), findsOneWidget);
    });

    testWidgets('a listing with six or fewer offers nothing to open', (
      tester,
    ) async {
      // A control that reveals nothing is worse than no control.
      await pump(tester, detail: _detail(specCount: 6));

      await tester.ensureVisible(find.text('Highlights'));
      await tester.pumpAndSettle();

      expect(find.text('View more'), findsNothing);
      expect(find.text('View less'), findsNothing);
      expect(find.text('Value 5'), findsOneWidget);
    });

    testWidgets('and the Specifications panel is untouched by any of it', (
      tester,
    ) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Highlights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View more'));
      await tester.pumpAndSettle();

      // Still a closed panel below, with its own copy of the table inside it.
      expect(find.text('Specifications'), findsOneWidget);
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();

      expect(find.text('Value 7'), findsWidgets);
    });
  });

  group('what was asked to stay put', () {
    testWidgets('the Specifications panel is still a closed panel', (
      tester,
    ) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();

      // Closed: its rows are not on the page until it is opened.
      expect(find.text('Value 7'), findsNothing);

      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();

      expect(find.text('Value 7'), findsWidgets);
    });

    testWidgets('and nothing offers to translate anything', (tester) async {
      await pump(tester);

      expect(find.textContaining('Show original'), findsNothing);
      expect(find.textContaining('中文'), findsNothing);
      expect(find.textContaining('Translate'), findsNothing);
    });

    testWidgets('a listing with no description says so, in place', (
      tester,
    ) async {
      // Most of this catalogue: 1688 returns the description as a block of
      // images with no prose in it. The section stays where the design puts
      // it -- below Highlights -- and says what is true rather than
      // disappearing on one product and not the next.
      await pump(
        tester,
        detail: ProductDetail(
          numIid: 'test-product',
          title: 'No description',
          price: 2,
          rating: 4,
          reviewCount: 1,
          images: const ['https://example.invalid/a.jpg'],
          variants: const [],
          specs: const [ProductSpec('Brand', 'Hongkuang')],
          description: '',
          assurances: storeAssurances,
        ),
      );

      expect(find.text('Description'), findsOneWidget);
      expect(
        find.textContaining('has not written a description'),
        findsOneWidget,
      );
      // Nothing invented to fill it, and no control that opens onto nothing.
      expect(find.text('Read more'), findsNothing);
      expect(find.textContaining('the specifications'), findsOneWidget);
    });

    testWidgets('and the description sits directly below the highlights', (
      tester,
    ) async {
      await pump(tester);

      final highlights = tester.getRect(find.text('Highlights'));
      final description = tester.getRect(find.text('Description'));
      final specifications = tester.getRect(find.text('Specifications'));

      expect(description.top, greaterThan(highlights.top));
      expect(description.top, lessThan(specifications.top));
    });

    testWidgets('the description still opens and closes in place', (
      tester,
    ) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Description'));
      await tester.pumpAndSettle();

      expect(find.text('Read more'), findsOneWidget);
      await tester.tap(find.text('Read more'));
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);
    });
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_matrix_table.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_picker.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_tooltip.dart';

/// More colourways than a phone can show at 64pt a swatch.
List<ProductVariant> _many(int count) => [
  for (var i = 0; i < count; i++)
    ProductVariant(
      label: 'Colour $i',
      imageUrl: 'https://cdn.invalid/$i.jpg',
      skuId: 'sku-$i',
      axisValues: ['Colour $i'],
    ),
];

/// The shape of the ring in the reference: a handful of colours against more
/// US sizes than fit across a phone.
VariantMatrix _wideMatrix({int colours = 4, int sizes = 8}) =>
    VariantMatrix.from([
      for (var c = 0; c < colours; c++)
        for (var s = 0; s < sizes; s++)
          ProductVariant(
            label: 'Colour $c / No. $s us size',
            imageUrl: 'https://cdn.invalid/$c.jpg',
            skuId: 'sku-$c-$s',
            axisNames: const ['Color', 'Size'],
            axisValues: ['Colour $c', 'No. $s us size'],
          ),
    ])!;

/// Rests a mouse pointer on [finder], which is the only thing that raises
/// these tooltips now.
Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.pump();
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();
  return mouse;
}

void main() {
  /// A 360pt phone, which is the width this has to work on.
  Future<void> phone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('the grid says it can be swiped', () {
    Future<void> grid(WidgetTester tester, VariantMatrix matrix) => phone(
      tester,
      VariantMatrixTable(
        matrix: matrix,
        quantities: const {},
        total: 0,
        minOrder: 1,
        onChanged: (_, _) {},
      ),
    );

    testWidgets('it names the axis running past the edge', (tester) async {
      // Eight sizes do not fit a 360pt phone beside the colour names, so the
      // last columns are off screen with nothing saying so.
      await grid(tester, _wideMatrix());

      expect(find.text('Swipe left to see more sizes'), findsOneWidget);
      expect(find.byIcon(Icons.swipe_left_alt), findsOneWidget);
    });

    testWidgets('and says nothing about a grid that fits', (tester) async {
      // A standing instruction to swipe something that cannot move is noise.
      await grid(tester, _wideMatrix(sizes: 2));

      expect(find.textContaining('Swipe left'), findsNothing);
      expect(find.byIcon(Icons.swipe_left_alt), findsNothing);
    });

    testWidgets('it goes once the grid has been moved', (tester) async {
      await grid(tester, _wideMatrix());
      expect(find.text('Swipe left to see more sizes'), findsOneWidget);

      await tester.drag(find.byType(VariantMatrixTable), const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(
        find.text('Swipe left to see more sizes'),
        findsNothing,
        reason: 'the hint has done its job',
      );
    });

    testWidgets('it sits under the grid, not over it', (tester) async {
      await grid(tester, _wideMatrix());

      final hint = tester.getRect(find.text('Swipe left to see more sizes'));
      final cells = tester.getRect(find.text('Colour 0'));

      expect(hint.top, greaterThan(cells.bottom));
    });
  });

  group('every colourway can be reached', () {
    testWidgets('the last swatch is off screen to begin with', (tester) async {
      // If it were already visible the rest of this group would prove nothing.
      await phone(
        tester,
        VariantPicker(
          label: 'Colour',
          variants: _many(12),
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      );

      expect(find.bySemanticsLabel('Colour 11'), findsNothing);
    });

    testWidgets('swiping brings it in, and tapping it selects it', (
      tester,
    ) async {
      // The whole point: not just that the row moves, but that the option it
      // reveals is the right one and still selects the right variant.
      final taps = <int>[];
      await phone(
        tester,
        VariantPicker(
          label: 'Colour',
          variants: _many(12),
          selectedIndex: 0,
          onSelected: taps.add,
        ),
      );

      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(-900, 0),
        2000,
      );
      await tester.pumpAndSettle();

      final last = find.bySemanticsLabel('Colour 11');
      expect(last, findsOneWidget, reason: 'the last colourway is reachable');

      await tester.tap(last);
      await tester.pump();

      expect(taps, [
        11,
      ], reason: 'and it selects its own index, not a nearer one');
    });

    testWidgets('the selection stays marked while the row is scrolled', (
      tester,
    ) async {
      await phone(
        tester,
        VariantPicker(
          label: 'Colour',
          variants: _many(12),
          selectedIndex: 11,
          onSelected: (_) {},
        ),
      );

      // The heading names the selection wherever the row happens to sit.
      expect(find.text('Colour 11'), findsOneWidget);

      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(-900, 0),
        2000,
      );
      await tester.pumpAndSettle();

      expect(find.text('Colour 11'), findsOneWidget);
      // And the swatch itself is still the marked one.
      final marked = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(VariantPicker),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(marked, isNotNull);
    });

    testWidgets('the name still comes up on an option swiped into view', (
      tester,
    ) async {
      await phone(
        tester,
        VariantPicker(
          label: 'Colour',
          variants: _many(12),
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      );

      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(-900, 0),
        2000,
      );
      await tester.pumpAndSettle();

      await hover(tester, find.bySemanticsLabel('Colour 11'));

      expect(find.text('Colour 11'), findsWidgets);
      expect(find.byType(VariantTooltip), findsWidgets);
    });
  });

  group('every size can be reached', () {
    /// The grid builds every column whether or not it is on screen, so
    /// "is it there" proves nothing here -- where it sits does.
    const viewport = 360.0;

    Future<void> grid(WidgetTester tester, Map<String, int> orders) => phone(
      tester,
      VariantMatrixTable(
        matrix: _wideMatrix(),
        quantities: const {},
        total: 0,
        minOrder: 1,
        onChanged: (sku, qty) => orders[sku] = qty,
      ),
    );

    testWidgets('the far size starts beyond the right edge', (tester) async {
      await grid(tester, {});

      expect(
        tester.getTopLeft(find.text('No. 7 us size')).dx,
        greaterThan(viewport),
        reason: 'otherwise this group proves nothing',
      );
    });

    testWidgets('scrolling sideways brings it into view', (tester) async {
      await grid(tester, {});
      final before = tester.getTopLeft(find.text('No. 7 us size')).dx;

      await tester.drag(
        find.byType(VariantMatrixTable),
        const Offset(-500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(find.text('No. 7 us size')).dx;
      expect(after, lessThan(before), reason: 'the grid moved');
      expect(after, lessThan(viewport), reason: 'and the column is on screen');
    });

    testWidgets('a cell in the revealed column takes an order', (tester) async {
      // Reaching a column is worth nothing if its boxes cannot be used.
      final orders = <String, int>{};
      await grid(tester, orders);

      await tester.drag(
        find.byType(VariantMatrixTable),
        const Offset(-900, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '3');
      await tester.pump();

      expect(
        orders.keys.single.endsWith('-7'),
        isTrue,
        reason: 'the order landed on the far size, not a nearer one',
      );
      expect(orders.values.single, 3);
    });

    testWidgets('it scrolls when swiped from a quantity box', (tester) async {
      // The box is the biggest thing a finger can land on, and a text field
      // wins the gesture arena for a horizontal drag. Before this, a swipe
      // started on one moved nothing at all -- which is most of the grid, and
      // is why the sizes off to the right read as unreachable.
      await grid(tester, {});
      final before = tester.getTopLeft(find.text('No. 7 us size')).dx;

      await tester.drag(find.byType(TextField).first, const Offset(-500, 0));
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(find.text('No. 7 us size')).dx;
      expect(after, lessThan(before), reason: 'the grid moved');
      expect(
        after,
        lessThan(viewport),
        reason: 'and the far size is on screen',
      );
    });

    testWidgets('a swipe down a box still scrolls the page, not the grid', (
      tester,
    ) async {
      // The sideways sweep must not steal a finger travelling down the page.
      await grid(tester, {});
      final before = tester.getTopLeft(find.text('No. 7 us size')).dx;

      await tester.drag(find.byType(TextField).first, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('No. 7 us size')).dx,
        before,
        reason: 'the grid did not move sideways',
      );
    });

    testWidgets('tapping a box still focuses it and takes a number', (
      tester,
    ) async {
      // The Listener must cost the field nothing it had.
      final orders = <String, int>{};
      await grid(tester, orders);

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '4');
      await tester.pump();

      expect(orders.values.single, 4);
    });

    testWidgets('it scrolls when dragged from the size headers', (
      tester,
    ) async {
      // A shopper reaches for the row of size names, and those headers carry
      // a tooltip whose long press must not swallow the drag.
      await grid(tester, {});
      final before = tester.getTopLeft(find.text('No. 7 us size')).dx;

      await tester.drag(
        find.text('No. 1 us size'),
        const Offset(-500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('No. 7 us size')).dx,
        lessThan(before),
      );
    });

    testWidgets('the colour column stays put while the sizes move', (
      tester,
    ) async {
      // The whole point of reaching the fifteenth size is knowing which
      // colourway the box belongs to when you get there.
      await grid(tester, {});
      final colourBefore = tester.getTopLeft(find.text('Colour 0')).dx;
      final sizeBefore = tester.getTopLeft(find.text('No. 7 us size')).dx;

      await tester.drag(
        find.byType(VariantMatrixTable),
        const Offset(-500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('No. 7 us size')).dx,
        lessThan(sizeBefore),
        reason: 'the sizes moved',
      );
      expect(
        tester.getTopLeft(find.text('Colour 0')).dx,
        colourBefore,
        reason: 'and the colourway did not go with them',
      );
    });

    testWidgets('the colour column is still readable at the far end', (
      tester,
    ) async {
      await grid(tester, {});

      for (var i = 0; i < 4; i++) {
        await tester.drag(
          find.byType(VariantMatrixTable),
          const Offset(-500, 0),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }

      // Scrolled as far as it goes, every colourway is still named.
      for (var c = 0; c < 4; c++) {
        expect(
          find.text('Colour $c'),
          findsOneWidget,
          reason: 'Colour $c is still named',
        );
      }
    });

    testWidgets('it scrolls when dragged from a colour thumbnail', (
      tester,
    ) async {
      // The thumbnails open a larger image on tap; that must not cost the
      // drag either.
      await grid(tester, {});
      final before = tester.getTopLeft(find.text('No. 7 us size')).dx;

      await tester.drag(
        find.text('Colour 0'),
        const Offset(-500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('No. 7 us size')).dx,
        lessThan(before),
      );
    });
  });
}

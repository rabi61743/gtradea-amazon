import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_matrix_table.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_picker.dart';

import 'support/catalog.dart';

Widget _wrap(ProductDetail detail) => MaterialApp(
  theme: AppTheme.light,
  home: ProductDetailScreen(product: sampleProduct, detail: detail),
);

/// The grid sits below the gallery and the price block, so a short window
/// leaves it unbuilt and every finder below misses.
Future<void> _pump(WidgetTester tester, ProductDetail detail) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(detail));
  await tester.pump(const Duration(milliseconds: 300));
}

/// The quantity boxes, which are the only text fields on this page.
Finder get _cells => find.descendant(
  of: find.byType(VariantMatrixTable),
  matching: find.byType(TextField),
);

/// Types into the box for one combination.
///
/// Located by walking the grid the way a buyer does -- find the row, count
/// along it -- rather than by index into a flat list of every field on screen,
/// which would silently follow the layout if it ever changed.
Future<void> _enter(
  WidgetTester tester, {
  required String colour,
  required int column,
  required String quantity,
}) async {
  final row = find.byKey(ValueKey(variantRowKey(colour)));
  final inRow = find.descendant(of: row, matching: find.byType(TextField));
  await tester.enterText(inRow.at(column), quantity);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
  });

  group('VariantMatrix.from', () {
    test('pivots a two-axis listing into rows and columns', () {
      final matrix = VariantMatrix.from(gridDetail.variants);

      expect(matrix, isNotNull);
      expect(matrix!.rowLabel, 'Color');
      expect(matrix.columnLabel, 'Size');
      expect(matrix.rows.map((r) => r.value), [
        'White',
        'Wine red',
        'Ideal green',
      ], reason: 'the seller\'s own order, not alphabetical');
      expect(matrix.columns, hasLength(3));
    });

    test('leaves a combination the seller does not make empty', () {
      final matrix = VariantMatrix.from(gridDetail.variants)!;
      final xl = matrix.columns.last;

      // Eight SKUs across a nine-square grid. The ninth is a hole, and the
      // alternative -- inventing a SKU to fill it -- is an order the supplier
      // rejects rather than a display bug.
      expect(matrix.cells, hasLength(8));
      expect(matrix.at('Ideal green', xl), isNull);
      expect(matrix.at('White', xl), isNotNull);
    });

    test('tells "not made" apart from "sold out"', () {
      final matrix = VariantMatrix.from(gridDetail.variants)!;
      final xl = matrix.columns.last;

      // Both are unbuyable. Only one is worth coming back for, and the grid
      // draws them differently on the strength of this.
      expect(matrix.at('Wine red', xl)!.inStock, isFalse);
      expect(matrix.at('White', xl)!.inStock, isTrue);
      expect(matrix.buyable, hasLength(7));
    });

    test('carries the seller\'s stock through, for the ones running low', () {
      final matrix = VariantMatrix.from(gridDetail.variants)!;

      expect(matrix.at('White', matrix.columns.last)!.stock, 5);
      expect(matrix.at('White', matrix.columns.first)!.stock, 900);
    });

    test('notices that the sizes are priced apart', () {
      expect(VariantMatrix.from(gridDetail.variants)!.pricesVary, isTrue);
    });

    test('is null for a listing that is not a grid', () {
      // One axis: the strip picker already does this well, and a one-column
      // table is a list wearing a table's clothes.
      expect(VariantMatrix.from(sampleDetail.variants), isNull);
      expect(VariantMatrix.from(const []), isNull);

      const threeAxes = [
        ProductVariant(
          label: 'Red / M / Cotton',
          imageUrl: '',
          axisNames: ['Color', 'Size', 'Material'],
          axisValues: ['Red', 'M', 'Cotton'],
        ),
        ProductVariant(
          label: 'Red / L / Cotton',
          imageUrl: '',
          axisNames: ['Color', 'Size', 'Material'],
          axisValues: ['Red', 'L', 'Cotton'],
        ),
      ];
      expect(
        VariantMatrix.from(threeAxes),
        isNull,
        reason: 'three axes do not pivot into a plane',
      );
    });

    test('refuses a listing where only some SKUs carry two axes', () {
      // All or nothing: a nine-SKU listing where one carries three axes is not
      // a grid with a hole in it, and half-drawing it would misprice the odd
      // one out.
      const mixed = [
        ProductVariant(
          label: 'Red / M',
          imageUrl: '',
          axisNames: ['Color', 'Size'],
          axisValues: ['Red', 'M'],
        ),
        ProductVariant(
          label: 'Blue',
          imageUrl: '',
          axisNames: ['Color'],
          axisValues: ['Blue'],
        ),
      ];
      expect(VariantMatrix.from(mixed), isNull);
    });

    test('capitalises an axis the seller wrote in lower case', () {
      // The feed has both spellings, sometimes across two products in one
      // department, and a header capitalised on one and not the next reads as
      // a rendering bug.
      const lower = [
        ProductVariant(
          label: 'Red / M',
          imageUrl: '',
          axisNames: ['color', 'size'],
          axisValues: ['Red', 'M'],
        ),
        ProductVariant(
          label: 'Red / L',
          imageUrl: '',
          axisNames: ['color', 'size'],
          axisValues: ['Red', 'L'],
        ),
      ];
      final matrix = VariantMatrix.from(lower)!;
      expect(matrix.rowLabel, 'Color');
      expect(matrix.columnLabel, 'Size');
    });
  });

  group('shortVariantLabel', () {
    test('drops the fitting guide the seller wrote into the size', () {
      expect(shortVariantLabel('M【 50.5-57.5kg 】'), 'M');
      expect(shortVariantLabel('Xl【 65.5-75kg 】'), 'Xl');
      expect(shortVariantLabel('L (58-65kg)'), 'L');
      expect(shortVariantLabel('S [small]'), 'S');
    });

    test('leaves a label that is already short alone', () {
      expect(shortVariantLabel('XL'), 'XL');
      expect(shortVariantLabel('Wine red'), 'Wine red');
      // A slash is part of plenty of real size names and is not an aside.
      expect(shortVariantLabel('S/M'), 'S/M');
    });

    test('keeps something when the whole label is an aside', () {
      expect(shortVariantLabel('【 one size 】'), '【 one size 】');
    });
  });

  group('the grid on the page', () {
    testWidgets('a two-axis listing gets the grid and not the strip', (
      tester,
    ) async {
      await _pump(tester, gridDetail);

      expect(find.byType(VariantMatrixTable), findsOneWidget);
      expect(find.byType(VariantPicker), findsNothing);
    });

    testWidgets('a one-axis listing keeps the strip it always had', (
      tester,
    ) async {
      await _pump(tester, sampleDetail);

      expect(find.byType(VariantPicker), findsOneWidget);
      expect(find.byType(VariantMatrixTable), findsNothing);
    });

    testWidgets('a box for every combination that can be bought', (
      tester,
    ) async {
      await _pump(tester, gridDetail);

      // Seven, not nine: the combination that is not made and the one that is
      // sold out are drawn, but neither takes a quantity.
      expect(_cells, findsNWidgets(7));
    });

    testWidgets('headers are the sizes without their fitting guides', (
      tester,
    ) async {
      await _pump(tester, gridDetail);

      final table = find.byType(VariantMatrixTable);
      expect(find.descendant(of: table, matching: find.text('M')), findsOne);
      expect(find.descendant(of: table, matching: find.text('Xl')), findsOne);
      expect(
        find.textContaining('50.5-57.5kg'),
        findsNothing,
        reason: 'a header three times wider than the box under it',
      );
    });

    testWidgets('typing adds up across the whole grid', (tester) async {
      await _pump(tester, gridDetail);

      await _enter(tester, colour: 'White', column: 0, quantity: '3');
      await _enter(tester, colour: 'Wine red', column: 1, quantity: '2');

      // Two rows of the grid, priced from the SKUs: 3x250 + 2x250.
      expect(find.textContaining('5 pieces across 2 options'), findsWidgets);
      expect(find.text('Buy · Rs. 1,250'), findsOneWidget);
    });

    testWidgets('the XL row is priced at what XL costs', (tester) async {
      await _pump(tester, gridDetail);

      // The seller charges more for XL. Taking four of them has to cost four
      // times 300, not four times the headline 250.
      await _enter(tester, colour: 'White', column: 2, quantity: '4');
      expect(find.text('Buy · Rs. 1,200'), findsOneWidget);
    });

    testWidgets('nothing typed is nothing to buy', (tester) async {
      await _pump(tester, gridDetail);

      expect(find.text('Nothing selected yet'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Add to cart'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('add to cart makes one line per square with something in it', (
      tester,
    ) async {
      await _pump(tester, gridDetail);

      await _enter(tester, colour: 'White', column: 0, quantity: '3');
      await _enter(tester, colour: 'Wine red', column: 1, quantity: '2');
      await tester.tap(find.text('Add to cart'));
      await tester.pump();

      final lines = CartStore.instance.lines;
      expect(lines, hasLength(2));
      expect(
        lines.map((l) => l.skuId),
        containsAll(<String>['sku-White-M', 'sku-Wine red-L']),
        reason: 'the SKU is what the server orders upstream, not the colour',
      );
      expect(lines.map((l) => l.quantity), containsAll(<int>[3, 2]));
      // Each line carries its own colourway photograph, so the cart tells two
      // colours of one shirt apart.
      expect(lines.map((l) => l.imageUrl).toSet(), hasLength(2));
    });

    testWidgets('the minimum is counted across the order, not per square', (
      tester,
    ) async {
      await _pump(tester, gridDetail);

      // This seller's minimum is four. Two colours of two is an order of four,
      // and refusing it because neither square reaches four on its own would
      // be refusing a valid order.
      await _enter(tester, colour: 'White', column: 0, quantity: '2');
      await _enter(tester, colour: 'Wine red', column: 0, quantity: '2');
      await tester.tap(find.text('Add to cart'));
      await tester.pump();

      expect(CartStore.instance.lines, hasLength(2));
    });

    testWidgets(
      'an order under the seller\'s minimum is refused, and says so',
      (tester) async {
        await _pump(tester, gridDetail);

        await _enter(tester, colour: 'White', column: 0, quantity: '1');
        await tester.tap(find.text('Add to cart'));
        await tester.pump();

        expect(CartStore.instance.lines, isEmpty);
        expect(find.textContaining('orders of 4 or more'), findsWidgets);
      },
    );

    testWidgets('the grid empties once its order is in the cart', (
      tester,
    ) async {
      await _pump(tester, gridDetail);

      await _enter(tester, colour: 'White', column: 0, quantity: '4');
      await tester.tap(find.text('Add to cart'));
      await tester.pump();

      // Left full, the next tap would order the same four again.
      expect(find.text('Nothing selected yet'), findsOneWidget);
      expect(CartStore.instance.lines, hasLength(1));
    });

    testWidgets('Clear empties the grid without touching the cart', (
      tester,
    ) async {
      await _pump(tester, gridDetail);

      await _enter(tester, colour: 'White', column: 0, quantity: '4');
      // Clear sits under the grid rather than on the pinned bar, so on a phone
      // it is a scroll away.
      await tester.ensureVisible(find.text('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(find.text('Nothing selected yet'), findsOneWidget);
      expect(CartStore.instance.lines, isEmpty);
    });

    testWidgets('a grid of short names holds together at 2x text', (
      tester,
    ) async {
      // Every row of a table shares one height, measured from the longest
      // colour name in it. Short names are the case that height is smallest,
      // and 2x is where the boxes are largest -- so this is where the two are
      // closest to colliding.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final matrix = VariantMatrix.from(const [
        ProductVariant(
          label: 'Red / M',
          imageUrl: '',
          skuId: 'a',
          stock: 3,
          price: 100,
          axisNames: ['Color', 'Size'],
          axisValues: ['Red', 'M'],
        ),
        ProductVariant(
          label: 'Red / L',
          imageUrl: '',
          skuId: 'b',
          stock: 3,
          price: 100,
          axisNames: ['Color', 'Size'],
          axisValues: ['Red', 'L'],
        ),
      ])!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: VariantMatrixTable(
                  matrix: matrix,
                  quantities: const {},
                  total: 0,
                  onChanged: (_, _) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3 left'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a colourway running low says how many are left', (
      tester,
    ) async {
      await _pump(tester, gridDetail);

      // Five White in XL. The other 900s are not a constraint on any order
      // this seller would accept and are left unsaid.
      expect(find.text('5 left'), findsOneWidget);
      expect(find.textContaining('900 left'), findsNothing);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_matrix_table.dart';

import 'support/catalog.dart';

/// The grid against a real response, not a fixture written to suit it.
///
/// `test/fixtures/real_two_axis_product.json` is the untouched body
/// `https://gtradea.com/api/1688/product?num_iid=878016491892` returned, with
/// only the HTML description blob removed for size. Every SKU, price, stock
/// figure, photograph and axis name in it is the seller's.
///
/// This exists because the hand-written fixture next door was written by the
/// same person who wrote the parser, and agreeing with itself is not evidence.
/// What this catches is the feed being shaped differently from how it was
/// remembered -- which is the failure the whole grid rests on.
Map<String, dynamic> get _liveBody => jsonDecode(
  File('test/fixtures/real_two_axis_product.json').readAsStringSync(),
) as Map<String, dynamic>;

ProductDetail get _liveDetail =>
    ProductDetail.fromApi(_liveBody, fallback: sampleProduct);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
  });

  test('the live response still parses into 84 two-axis SKUs', () {
    final detail = _liveDetail;

    expect(detail.variants, hasLength(84));
    expect(
      detail.variants.every((v) => v.axisValues.length == 2),
      isTrue,
      reason:
          'a feed that stopped splitting colour from size would silently '
          'drop every listing back to the flat picker',
    );
    expect(detail.variants.first.axisNames, ['Color', 'Size']);
  });

  test('it pivots into the grid the seller actually sells', () {
    final matrix = VariantMatrix.from(_liveDetail.variants);

    expect(matrix, isNotNull);
    // 21 colours by 4 sizes. The seller stocks every combination of this one,
    // so the grid is full -- 84 cells for 84 SKUs, nothing dropped and nothing
    // invented.
    expect(matrix!.rows, hasLength(21));
    expect(matrix.columns, hasLength(4));
    expect(matrix.cells, hasLength(84));
    expect(matrix.rowLabel, 'Color');
    expect(matrix.columnLabel, 'Size');
  });

  test('every row carries the seller\'s own photograph', () {
    final matrix = VariantMatrix.from(_liveDetail.variants)!;

    expect(
      matrix.rows.where((r) => r.imageUrl.isEmpty),
      isEmpty,
      reason: 'a colourway with no picture is a row a buyer cannot choose from',
    );
    expect(
      matrix.rows.map((r) => r.imageUrl).toSet(),
      hasLength(21),
      reason: 'one photograph per colour, not the same shot 21 times',
    );
  });

  test('the sizes carry fitting guides, and the headers drop them', () {
    final matrix = VariantMatrix.from(_liveDetail.variants)!;

    // This is why shortVariantLabel exists rather than being tidiness: the
    // seller writes the weight range into the size itself.
    expect(matrix.columns.any((c) => c.contains('kg')), isTrue);
    expect(matrix.columns.map(shortVariantLabel).toList(), [
      'S',
      'M',
      'L',
      'Xl',
    ]);
  });

  test('prices come from the SKU table, not the headline', () {
    final matrix = VariantMatrix.from(_liveDetail.variants)!;

    expect(
      matrix.cells.values.every((v) => v.price != null),
      isTrue,
      reason: 'a cell with no price is a cell that adds nothing to the total',
    );

    // This listing is priced on two tiers -- 1554 and 1820 -- so the headline
    // price alone would misquote 48 of its 84 combinations.
    expect(matrix.pricesVary, isTrue);
    expect(matrix.cells.values.map((v) => v.price).toSet(), hasLength(2));
  });

  test('the price splits by colourway, so a row is one figure not a range', () {
    final matrix = VariantMatrix.from(_liveDetail.variants)!;

    // Which axis the money is on decides what the grid can show. Here every
    // colour holds one price across all four sizes, and every size spans both
    // prices -- so a price per row is a single figure, and a price per column
    // would have been a range on every column. The row was the right place to
    // put it, and this is the evidence rather than the hope.
    for (final row in matrix.rows) {
      final prices = matrix.columns
          .map((column) => matrix.at(row.value, column)?.price)
          .whereType<num>()
          .toSet();
      expect(prices, hasLength(1), reason: '${row.value} is priced twice');
    }

    for (final column in matrix.columns) {
      final prices = matrix.rows
          .map((row) => matrix.at(row.value, column)?.price)
          .whereType<num>()
          .toSet();
      expect(prices, hasLength(2), reason: '$column would need a range');
    }
  });

  testWidgets('the page draws the live listing as a grid', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductDetailScreen(product: sampleProduct, detail: _liveDetail),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(VariantMatrixTable), findsOneWidget);
    // 21 colours, six rows at a time, so the page is not 21 photographs long
    // before a buyer has decided they want any of them.
    expect(find.textContaining('Show all 21 color options'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

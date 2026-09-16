import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtradea_amazon/features/home/widgets/product_grid.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:gtradea_amazon/shared/widgets/artwork_panel.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

/// The recommendation shelf at the foot of the product page: "More in ...".
Finder get _shelf => find.byWidgetPredicate(
  (w) => w is ProductGrid && w.title.startsWith('More in'),
);

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    // The page fetches its own record, and only then asks for the shelf --
    // the department's other offers, from the keyword endpoint.
    api.on('GET', '/api/1688/product', body: detailResponseJson);
    api.on('GET', '/api/1688/search', body: {'items': feedRows(6)});
  });

  tearDown(clearApiStub);

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductDetailScreen(product: sampleProduct),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // The shelf is the last thing on a lazily built page, so it is not made
    // until the page is scrolled down to it.
    for (var i = 0; i < 30 && _shelf.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the cards sit at the Future Cart shelf\'s compact gap', (
    tester,
  ) async {
    await open(tester, const Size(430, 3000));
    expect(_shelf, findsOneWidget);

    final grid = tester.widget<ProductGrid>(_shelf);
    final spec = grid.spec(400);
    expect(spec.gap, 4, reason: 'across');
    expect(spec.rowGap, 4, reason: 'down');

    // Tighter than the grid this shelf used before, and the same measure the
    // Future Cart suggestions use.
    final standard = ResultGridSpec.standard(400);
    expect(spec.gap, lessThan(standard.gap));
    expect(spec.rowGap!, lessThan(standard.rowGap!));

    // The card itself is untouched: same columns, same padding inside.
    expect(spec.columns, standard.columns);
    expect(spec.cardPadding, standard.cardPadding);
  });

  testWidgets('the picture runs to the card\'s top, left and right edges', (
    tester,
  ) async {
    await open(tester, const Size(430, 3000));

    final card = find
        .descendant(of: _shelf, matching: find.byType(ProductResultCard))
        .first;
    expect(tester.widget<ProductResultCard>(card).imageFlush, isTrue);

    final cardBox = tester.getRect(card);
    final picture = tester.getRect(
      find.descendant(of: card, matching: find.byType(ArtworkPanel)).first,
    );
    // Flush to the card's edges, inside its own 1pt border and nothing else.
    expect(picture.left, closeTo(cardBox.left, 1), reason: 'flush left');
    expect(picture.right, closeTo(cardBox.right, 1), reason: 'flush right');
    expect(picture.top, closeTo(cardBox.top, 1), reason: 'flush top');
    // Square, as before, and inside the card: nothing spills or is clipped.
    expect(picture.width, closeTo(picture.height, 0.5));
    expect(picture.bottom, lessThan(cardBox.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('elsewhere the card keeps its padded picture', (tester) async {
    // The same card on another surface is untouched.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: ProductResultCard(product: sampleProduct),
          ),
        ),
      ),
    );
    await tester.pump();

    final cardBox = tester.getRect(find.byType(ProductResultCard));
    final picture = tester.getRect(find.byType(ArtworkPanel).first);
    expect(picture.left, greaterThan(cardBox.left));
    expect(picture.top, greaterThan(cardBox.top));
  });

  testWidgets('and the grid draws with those gaps, with nothing overflowing', (
    tester,
  ) async {
    for (final size in const [
      Size(390, 3000),
      Size(800, 3000),
      Size(1400, 3000),
    ]) {
      await open(tester, size);
      final delegate =
          tester
                  .widgetList<GridView>(
                    find.descendant(
                      of: _shelf,
                      matching: find.byType(GridView),
                    ),
                  )
                  .first
                  .gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisSpacing, 4, reason: '${size.width} dp across');
      expect(delegate.mainAxisSpacing, 4, reason: '${size.width} dp down');
      expect(tester.takeException(), isNull, reason: '${size.width} dp');
    }
  });
}

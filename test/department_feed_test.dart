import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/widgets/department_feed.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 4400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Category _department() => Category(
  cid: 'dept-1',
  name: 'Men',
  children: const [
    Category(cid: 'child-0', name: "Men's Sweaters", parentCid: 'dept-1'),
    Category(cid: 'child-1', name: "Men's Jackets", parentCid: 'dept-1'),
  ],
);

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

Future<void> _pump(
  WidgetTester tester, {
  void Function(Category child)? onSeeAllChild,
}) async {
  _tall(tester);
  await tester.pumpWidget(
    _wrap(
      DepartmentFeed(
        department: _department(),
        onSeeAll: () {},
        onSeeAllChild: onSeeAllChild,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The chip, not the heading. Once a subcategory is selected its name is on
/// screen twice -- as the selected chip and as the heading over its products --
/// so a bare text finder matches two widgets and the tap is ambiguous.
Finder _chip(String label) => find.widgetWithText(FilterChip, label);

/// Every category cid the app has asked products for, in order.
List<Object?> _asked() => api.calls
    .where((c) => c.path == '/search/products')
    .map((c) => c.query['category'])
    .toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CatalogStore.instance.resetForTest();
  });

  testWidgets('a department shows its subcategories and its products', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text("Men's Sweaters"), findsOneWidget);
    expect(find.text("Men's Jackets"), findsOneWidget);
    expect(find.text('Trending in Men'), findsOneWidget);
    expect(find.byType(ProductResultCard), findsWidgets);
  });

  testWidgets('tapping a subcategory stays on the page', (tester) async {
    // The whole point. It used to push a results screen, so comparing two
    // subcategories meant walking a navigation stack to do it.
    await _pump(tester);

    await tester.tap(_chip("Men's Sweaters"));
    await tester.pumpAndSettle();

    expect(find.byType(SearchResultsScreen), findsNothing);
    expect(find.byType(DepartmentFeed), findsOneWidget);
  });

  testWidgets('and asks the backend for that subcategory', (tester) async {
    await _pump(tester);

    await tester.tap(_chip("Men's Sweaters"));
    await tester.pumpAndSettle();

    // The search endpoint, not the trending one. Measured against production:
    // /feed/trending-products answers with an empty list for every subcategory
    // cid tried, including ones that demonstrably have products, so using it
    // here would have made every subcategory look empty.
    expect(_asked(), contains('child-0'));
    final trending = api.calls.where(
      (c) =>
          c.path == '/feed/trending-products' &&
          c.query['category_cid'] == 'child-0',
    );
    expect(trending, isEmpty);
  });

  testWidgets('the heading and the button follow the selection', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('See everything in Men'), findsOneWidget);

    await tester.tap(_chip("Men's Sweaters"));
    await tester.pumpAndSettle();

    expect(find.text('Trending in Men'), findsNothing);
    // Offering "everything in Men" while listing Men's Sweaters would widen the
    // results without saying it does.
    expect(find.text("See everything in Men's Sweaters"), findsOneWidget);
  });

  testWidgets('tapping the selected one widens back to the department', (
    tester,
  ) async {
    // A filter, not a menu: there is always a way back without hunting for one.
    await _pump(tester);

    await tester.tap(_chip("Men's Sweaters"));
    await tester.pumpAndSettle();
    expect(find.text('Trending in Men'), findsNothing);

    await tester.tap(_chip("Men's Sweaters"));
    await tester.pumpAndSettle();
    expect(find.text('Trending in Men'), findsOneWidget);
  });

  testWidgets('an empty subcategory says so and keeps the department', (
    tester,
  ) async {
    // Fourteen of the thirty-two subcategory tiles the home page shows are in
    // this state, so it is the common case rather than an edge one.
    stubSearchWith(
      api,
      (call) => call.query['category'] == 'child-0' ? const [] : feedRows(4),
    );

    await _pump(tester);
    await tester.tap(_chip("Men's Sweaters"));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Nothing in Men's Sweaters yet"),
      findsOneWidget,
    );
    // The chip clears itself rather than sitting selected over a blank grid.
    expect(find.text('Trending in Men'), findsOneWidget);
    expect(find.byType(ProductResultCard), findsWidgets);
  });

  testWidgets('only the See everything button leaves the page', (tester) async {
    Category? left;
    await _pump(tester, onSeeAllChild: (c) => left = c);

    await tester.tap(_chip("Men's Sweaters"));
    await tester.pumpAndSettle();
    expect(left, isNull, reason: 'the chip must not navigate');

    await tester.tap(find.text("See everything in Men's Sweaters"));
    await tester.pump();
    expect(left?.cid, 'child-0');
  });

  testWidgets('switching department drops the subcategory', (tester) async {
    // The old department's chip is not one of the new one's, so leaving it
    // selected would narrow the new tab by something not on screen.
    _tall(tester);

    Widget feedFor(Category department) =>
        _wrap(DepartmentFeed(department: department, onSeeAll: () {}));

    await tester.pumpWidget(feedFor(_department()));
    await tester.pumpAndSettle();
    await tester.tap(_chip("Men's Sweaters"));
    await tester.pumpAndSettle();
    expect(find.text('Trending in Men'), findsNothing);

    await tester.pumpWidget(
      feedFor(
        const Category(
          cid: 'dept-2',
          name: 'Toys',
          children: [
            Category(cid: 'child-9', name: 'Puzzles', parentCid: 'dept-2'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trending in Toys'), findsOneWidget);
  });
}

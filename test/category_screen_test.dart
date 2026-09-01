import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/presentation/category_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/subcategory_grid.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// Antenna, as the home page hands it over: cid and name only. Everything the
/// screen draws below it is fetched.
const _antenna = Category(cid: '10235', name: 'Antenna', parentCid: '57');

/// What production returns for Antenna's children -- real names, and a null
/// image on every one of them, which is the case at this depth.
List<Map<String, dynamic>> _children([int count = 6]) => [
  for (var i = 0; i < count; i++)
    {
      'cid': 'antenna-child-$i',
      'parent_cid': '10235',
      'name': 'Antenna kind $i',
      'image_url': null,
      'sort_order': count - i,
    },
];

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 4400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester) async {
  _tall(tester);
  await tester.pumpWidget(
    const MaterialApp(home: CategoryScreen(category: _antenna)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
  });

  testWidgets('asks the backend for that category own children', (
    tester,
  ) async {
    api.on('GET', '/alibaba-categories', body: _children());
    await _open(tester);
    await tester.pumpAndSettle();

    final call = api.calls.lastWhere((c) => c.path == '/alibaba-categories');
    expect(call.query['parent_cids'], '10235');
  });

  testWidgets('draws a tile per child, from the row the server sent', (
    tester,
  ) async {
    api.on('GET', '/alibaba-categories', body: _children());
    await _open(tester);
    await tester.pumpAndSettle();

    final grid = tester.widget<SubcategoryGrid>(find.byType(SubcategoryGrid));

    // All six, not the four a home block shows: this screen is the full list
    // of the level below.
    expect(grid.children, hasLength(6));
    expect(grid.shown, 6);
    expect(grid.children.map((c) => c.cid), [
      for (var i = 5; i >= 0; i--) 'antenna-child-$i',
    ], reason: 'in the sort order the server gave, not the order it listed');
  });

  testWidgets('a subcategory opens its own product listing', (tester) async {
    // The last leg of category -> subcategory -> products.
    api.on('GET', '/alibaba-categories', body: _children());
    await _open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Antenna kind 5'));
    await tester.pumpAndSettle();

    final screen = tester.widget<SearchResultsScreen>(
      find.byType(SearchResultsScreen),
    );
    expect(screen.categoryCid, 'antenna-child-5');
    // And its name, so the chip does not read the literal word "Department".
    // The tree the results page consults is two levels deep and this is the
    // third, so it cannot look the name up for itself.
    expect(screen.categoryName, 'Antenna kind 5');
  });

  testWidgets('an empty subcategory widens to the category above it', (
    tester,
  ) async {
    // Of the thirty-four subcategories under Antenna, Audio Devices, Capacitor
    // and Diode, two have any products at all -- so this is the common path,
    // not an edge one. The cached tree stops one level short of these, so the
    // listing cannot work the parent out for itself: this screen tells it.
    api.on('GET', '/alibaba-categories', body: _children());
    stubSearchWith(
      api,
      (call) =>
          call.query['category'] == 'antenna-child-5' ? const [] : feedRows(4),
    );

    await _open(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Antenna kind 5'));
    await tester.pumpAndSettle();

    final asked = api.calls
        .where((c) => c.path == '/search/products')
        .map((c) => c.query['category'])
        .toList();
    expect(asked, containsAllInOrder(['antenna-child-5', '10235']));

    // And it says which is which rather than passing one off as the other.
    expect(find.textContaining('Nothing in Antenna kind 5'), findsOneWidget);
    expect(find.textContaining('Showing all of Antenna'), findsOneWidget);
  });

  testWidgets('the listing names the subcategory on its chip', (tester) async {
    api.on('GET', '/alibaba-categories', body: _children());
    await _open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Antenna kind 5'));
    await tester.pumpAndSettle();

    expect(find.text('Department'), findsNothing);
    // The request carries the subcategory, so the listing is only its products.
    final call = api.calls.lastWhere((c) => c.path == '/search/products');
    expect(call.query['category'], 'antenna-child-5');
  });

  testWidgets('and the category itself is one button away', (tester) async {
    api.on('GET', '/alibaba-categories', body: _children());
    await _open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('See all products in Antenna'));
    await tester.pumpAndSettle();

    final screen = tester.widget<SearchResultsScreen>(
      find.byType(SearchResultsScreen),
    );
    expect(screen.categoryCid, '10235');
  });

  group('the states it can be in', () {
    testWidgets('loading holds the shape the tiles will take', (tester) async {
      api.on('GET', '/alibaba-categories', body: _children());
      await _open(tester);
      // Pumped once, not settled: this is the frame before the answer lands.
      await tester.pump();

      expect(find.byType(SubcategoryGrid), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Bones at the size of the real thing rather than a centred dot.
      expect(find.byType(Wrap), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('a leaf says so rather than showing an empty grid', (
      tester,
    ) async {
      // An ordinary answer: plenty of categories are the last level.
      api.on('GET', '/alibaba-categories', body: const []);
      await _open(tester);
      await tester.pumpAndSettle();

      expect(find.text('Antenna has no subcategories'), findsOneWidget);
      expect(find.byType(SubcategoryGrid), findsNothing);
      // And still a way to the products, so it is not a dead end.
      expect(find.text('See all products in Antenna'), findsOneWidget);
    });

    testWidgets('a failure says what happened and offers a retry', (
      tester,
    ) async {
      api.on(
        'GET',
        '/alibaba-categories',
        status: 500,
        body: {'error': 'categories are down'},
      );
      await _open(tester);
      await tester.pumpAndSettle();

      // The server's own words: a generic "something went wrong" is what makes
      // an outage indistinguishable from an empty catalogue.
      expect(find.text('categories are down'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('and the retry actually asks again', (tester) async {
      api.on(
        'GET',
        '/alibaba-categories',
        status: 500,
        body: {'error': 'categories are down'},
      );
      await _open(tester);
      await tester.pumpAndSettle();

      api.on('GET', '/alibaba-categories', body: _children(2));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(SubcategoryGrid), findsOneWidget);
      expect(find.text('2 subcategories'), findsOneWidget);
    });

    testWidgets('one child is not "1 subcategories"', (tester) async {
      api.on('GET', '/alibaba-categories', body: _children(1));
      await _open(tester);
      await tester.pumpAndSettle();

      expect(find.text('1 subcategory'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/presentation/discover_more_section.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/catalog/presentation/category_screen.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/home/widgets/product_carousel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

late FakeApi api;

Future<void> _pump(WidgetTester tester, {VoidCallback? onSeeAll}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(children: [DiscoverMoreSection(onSeeAll: onSeeAll)]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CatalogStore.instance.resetForTest();
    CartStore.instance.resetForTest();
  });

  tearDown(clearApiStub);

  testWidgets('offers what is selling and where to look, from the shop', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Discover more products'), findsOneWidget);
    expect(find.text('Trending on gtradea.com'), findsOneWidget);

    // The shelf is the catalogue's own, sorted by what sells.
    expect(find.byType(ProductCarousel), findsOneWidget);
    final sorted = api.calls.where((c) => c.query['sort'] != null);
    expect(sorted, isNotEmpty, reason: 'asked for the selling order');

    // And the departments are the server's, in the order it puts them.
    final names = stubDepartmentNames(3);
    expect(find.text(names.first), findsWidgets);
  });

  testWidgets('a department opens its own page', (tester) async {
    await _pump(tester);

    await tester.tap(find.text(stubDepartmentNames(1).first).first);
    await tester.pumpAndSettle();

    expect(find.byType(CategoryScreen), findsOneWidget);
  });

  testWidgets('See all is the caller\'s own, not a route this invents', (
    tester,
  ) async {
    var asked = false;
    await _pump(tester, onSeeAll: () => asked = true);

    await tester.tap(find.text('See all'));
    await tester.pump();
    expect(asked, isTrue);
  });

  testWidgets('and says nothing at all when the shop offers nothing', (
    tester,
  ) async {
    // A suggestion under somebody's history is not information they are owed:
    // a failed shelf is a shelf that is not drawn.
    clearApiStub();
    api = FakeApi();
    api.on('GET', '/api/1688/search', status: 500, body: const {});
    api.on('GET', '/categories', body: const []);

    await _pump(tester);

    expect(find.text('Discover more products'), findsNothing);
    expect(find.byType(ProductCarousel), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

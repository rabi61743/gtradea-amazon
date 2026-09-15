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
import 'support/catalog.dart';
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
    DiscoverMoreSection.resetForTest();
  });

  List<RecordedCall> shelfCalls() =>
      api.calls.where((c) => c.query['sort'] != null).toList();

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

  testWidgets('heading, See all and departments are brand blue', (
    tester,
  ) async {
    await _pump(tester, onSeeAll: () {});
    final blue = AppTheme.light.colorScheme.primary;

    final heading = tester.widget<Text>(find.text('Discover more products'));
    expect(heading.style?.color, blue);

    final seeAll = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('See all'),
        matching: find.byType(TextButton),
      ),
    );
    expect(seeAll.style!.foregroundColor!.resolve({}), blue);

    final department = tester.widget<Text>(
      find.text(stubDepartmentNames(1).first).first,
    );
    expect(department.style?.color, blue);
  });

  testWidgets('the cards and pictures are smaller than the storefront rail', (
    tester,
  ) async {
    await _pump(tester);

    final carousel = tester.widget<ProductCarousel>(
      find.byType(ProductCarousel),
    );
    expect(carousel.width, DiscoverMoreSection.cardWidth);
    expect(carousel.width, lessThan(ProductCarousel.cardWidth));
    final context = tester.element(find.byType(ProductCarousel));
    expect(
      ProductCarousel.heightFor(context, width: carousel.width),
      lessThan(ProductCarousel.heightFor(context)),
      reason: 'the card shrinks with its picture',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('one request, however often the section is rebuilt', (
    tester,
  ) async {
    await _pump(tester);
    expect(shelfCalls(), hasLength(1));

    // Scrolled away and back, or the page rebuilt: a new section, no request.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(find.byType(ProductCarousel), findsOneWidget);
    expect(shelfCalls(), hasLength(1));
  });

  testWidgets('fetched ahead of time, it draws on the first frame', (
    tester,
  ) async {
    // In real time, as the history screen does when it opens.
    await tester.runAsync(DiscoverMoreSection.prefetch);

    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ListView(children: const [DiscoverMoreSection()])),
      ),
    );

    // No bones, no wait: the products are already here.
    expect(find.byType(ProductCarouselSkeleton), findsNothing);
    expect(find.byType(ProductCarousel), findsOneWidget);
    await tester.pumpAndSettle();
    expect(shelfCalls(), hasLength(1));
  });

  testWidgets('bones hold the compact shape while the shelf is on its way', (
    tester,
  ) async {
    api.onCall(
      'GET',
      '/search/products',
      (_) => reply(feedRows(6), delay: const Duration(seconds: 2)),
    );
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ListView(children: const [DiscoverMoreSection()])),
      ),
    );
    await tester.pump();

    final bones = tester.widget<ProductCarouselSkeleton>(
      find.byType(ProductCarouselSkeleton),
    );
    expect(bones.width, DiscoverMoreSection.cardWidth);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(ProductCarouselSkeleton), findsNothing);
    expect(find.byType(ProductCarousel), findsOneWidget);
  });

  for (final size in const [Size(360, 740), Size(800, 1280), Size(1400, 900)]) {
    testWidgets('fits at ${size.width.toInt()} dp', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(children: [DiscoverMoreSection(onSeeAll: () {})]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProductCarousel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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

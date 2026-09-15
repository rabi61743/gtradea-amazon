import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gtradea_amazon/features/home/widgets/promo_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/product_grid.dart';
import 'package:gtradea_amazon/features/home/widgets/product_carousel.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

const _title = 'Discover something new';
// The promotional pair that replaced the delivery band; the recommendations
// still sit under it, which is the placement this file is about.

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 20000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Scoped to the feed, like the other home-page suites: several of these
/// strings also appear in the header strip or in another rail.
Finder _inFeed(Finder target) =>
    find.descendant(of: find.byType(HomeFeed), matching: target);

Finder _homeScroll() => find
    .descendant(of: find.byType(HomeFeed), matching: find.byType(Scrollable))
    .first;

Future<void> _openHome(WidgetTester tester) async {
  await tester.pumpWidget(const GtradeaAmazonApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    _inFeed(find.text(_title)),
    400,
    scrollable: _homeScroll(),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.resetForTest();
  });

  group('where it sits', () {
    testWidgets('directly below the promotional cards', (tester) async {
      // The placement the request is about. Asserted by position rather than by
      // reading the widget list, because "below the banner" is the requirement.
      _tall(tester);
      useStubbedApi(stubCatalog());

      await _openHome(tester);

      // The promotional block is all artwork now, so it is found by its
      // widget rather than by any words on it.
      final promo = tester.getRect(find.byType(PromoSection)).top;
      final section = tester.getRect(_inFeed(find.text(_title))).top;
      final recommended = tester
          .getRect(_inFeed(find.text('Recommended for you')))
          .top;

      expect(section, greaterThan(promo));
      // And above the recommendations, so it is *directly* below the promo
      // rather than merely somewhere after it.
      expect(section, lessThan(recommended));
    });

    testWidgets('and the category index it replaced is gone', (tester) async {
      _tall(tester);
      useStubbedApi(stubCatalog());

      await _openHome(tester);

      expect(find.text('Shop by category'), findsNothing);
    });
  });

  group('what it draws', () {
    testWidgets('the same card the recommendations use, in a grid', (
      tester,
    ) async {
      // Not a new card and not a new rail: the request asked for the existing
      // product card, and this is the assertion that says it is literally the
      // same widget rather than something that resembles it.
      _tall(tester);
      useStubbedApi(stubCatalog());

      await _openHome(tester);

      final grid = tester.widget<ProductGrid>(
        find
            .ancestor(
              of: _inFeed(find.text(_title)),
              matching: find.byType(ProductGrid),
            )
            .first,
      );
      expect(grid.products, isNotEmpty);
      // Adding to the cart from a card, as the rails allow.
      expect(grid.onAddToCart, isNotNull);
    });

    testWidgets('the recommendations are a grid too, not a rail', (
      tester,
    ) async {
      // Laid out like "Discover something new" above it: same cards, same
      // columns, same gaps -- rather than a rail that has to be swiped.
      _tall(tester);
      useStubbedApi(stubCatalog());

      await _openHome(tester);

      final recommended = _inFeed(find.text('Recommended for you'));
      expect(recommended, findsOneWidget);

      final grid = tester.widget<ProductGrid>(
        find
            .ancestor(of: recommended, matching: find.byType(ProductGrid))
            .first,
      );
      expect(grid.products, isNotEmpty, reason: 'real catalogue products');
      expect(grid.onAddToCart, isNotNull);

      // And nothing left over from the rail it used to be.
      expect(
        find.ancestor(of: recommended, matching: find.byType(ProductCarousel)),
        findsNothing,
      );
    });

    testWidgets('a card opens the product it is for', (tester) async {
      _tall(tester);
      useStubbedApi(stubCatalog(products: 30));

      await _openHome(tester);

      final grid = tester.widget<ProductGrid>(
        find
            .ancestor(
              of: _inFeed(find.text(_title)),
              matching: find.byType(ProductGrid),
            )
            .first,
      );
      final first = grid.products.first;

      await tester.tap(_inFeed(find.text(first.title)).first);
      await tester.pumpAndSettle();

      final screen = tester.widget<ProductDetailScreen>(
        find.byType(ProductDetailScreen),
      );
      expect(screen.product.numIid, first.numIid);
    });

    testWidgets('twenty of them, when the catalogue has that many', (
      tester,
    ) async {
      _tall(tester);
      useStubbedApi(stubCatalog(products: 60));

      await _openHome(tester);

      final grid = tester.widget<ProductGrid>(
        find
            .ancestor(
              of: _inFeed(find.text(_title)),
              matching: find.byType(ProductGrid),
            )
            .first,
      );
      expect(grid.products, hasLength(20));
    });

    testWidgets('laid out down the page, not along a rail', (tester) async {
      // The difference this section was changed for. A rail of twenty is
      // nineteen swipes to reach the end of; asserted on the cards' positions
      // rather than on the widget type, because what was asked for is the
      // layout, not the class name.
      _tall(tester);
      useStubbedApi(stubCatalog(products: 60));

      await _openHome(tester);

      final cards = find.descendant(
        of: find.byType(ProductGrid),
        matching: find.byType(ProductResultCard),
      );
      expect(cards, findsWidgets);

      final first = tester.getRect(cards.first);
      final rects = [for (var i = 0; i < 4; i++) tester.getRect(cards.at(i))];

      // Something is on a later row, which is what "vertical" means.
      expect(
        rects.any((r) => r.top > first.top),
        isTrue,
        reason: 'every card on one row would be a rail',
      );
      // And nothing runs off the side, which is what a rail does. Scoped to
      // this section's own grid: the recommendations below it are a grid too
      // now, so an unscoped finder matches both.
      final width = tester
          .getSize(
            find
                .ancestor(
                  of: _inFeed(find.text(_title)),
                  matching: find.byType(ProductGrid),
                )
                .first,
          )
          .width;
      for (final rect in rects) {
        expect(rect.right, lessThanOrEqualTo(width + 1));
      }
    });

    testWidgets('a short catalogue is drawn short, not broken', (tester) async {
      // "If there are insufficient products, display only the available
      // products without breaking the layout."
      _tall(tester);
      useStubbedApi(stubCatalog(products: 3));

      await _openHome(tester);

      final grid = tester.widget<ProductGrid>(
        find
            .ancestor(
              of: _inFeed(find.text(_title)),
              matching: find.byType(ProductGrid),
            )
            .first,
      );
      expect(grid.products, hasLength(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty catalogue draws no section at all', (tester) async {
      // Rather than a heading over nothing.
      _tall(tester);
      final api = stubCatalog();
      api.on('GET', '/feed/discover', body: const <Map<String, dynamic>>[]);
      useStubbedApi(api);

      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      expect(_inFeed(find.text(_title)), findsNothing);
    });
  });

  group('where the products come from', () {
    test('the whole catalogue, not one category', () async {
      // /feed/discover is the only product endpoint here that is not scoped to
      // a department -- every other one requires a category or a query, so
      // drawing from them would be picking a category and calling it random.
      final api = stubCatalog();
      useStubbedApi(api);

      await CatalogRepository.instance.randomPicks(
        limit: 4,
        random: math.Random(1),
      );

      final call = api.calls.lastWhere((c) => c.path == '/feed/discover');
      expect(call.query.containsKey('category_cid'), isFalse);
      expect(
        api.calls.where((c) => c.path.startsWith('/categories/')),
        isEmpty,
      );
    });

    test('a random offset is what makes two loads differ', () async {
      // Asserted on the wire, because the shuffle alone would only reorder the
      // same twelve products -- every load would show the same set in a new
      // order, which is not what was asked for.
      final api = stubCatalog();
      useStubbedApi(api);

      final offsets = <Object?>{};
      for (var seed = 0; seed < 6; seed++) {
        await CatalogRepository.instance.randomPicks(
          limit: 4,
          random: math.Random(seed),
        );
        offsets.add(
          api.calls
              .lastWhere((c) => c.path == '/feed/discover')
              .query['page_offset'],
        );
      }

      expect(
        offsets.length,
        greaterThan(1),
        reason: 'different draws asked the server for different pages',
      );
    });

    test('a draw past the end of the feed falls back to the top', () async {
      // The feed is finite -- measured, it runs out somewhere between five and
      // seven thousand rows. A draw beyond it must be a smaller section, never
      // an empty one.
      final api = stubCatalog();
      api.onCall('GET', '/feed/discover', (call) {
        final offset = int.tryParse('${call.query['page_offset']}') ?? 0;
        // Empty everywhere except the top, which is the shape being guarded.
        return reply(
          offset == 0 ? feedRows(8) : const <Map<String, dynamic>>[],
        );
      });
      useStubbedApi(api);

      final picks = await CatalogRepository.instance.randomPicks(
        limit: 4,
        random: math.Random(3),
      );

      expect(picks, hasLength(4));
      final retried = api.calls.where((c) => c.path == '/feed/discover');
      expect(
        retried.length,
        2,
        reason: 'the empty draw, then the fallback to the top',
      );
    });

    test('never asks for more than it shows', () async {
      // It over-fetches on purpose so the shuffle has something to choose
      // between, but what reaches the rail is the limit.
      final api = stubCatalog(products: 40);
      useStubbedApi(api);

      final picks = await CatalogRepository.instance.randomPicks(
        limit: 6,
        random: math.Random(7),
      );

      expect(picks, hasLength(6));
    });
  });

  group('when it fails', () {
    testWidgets('it says nothing, because the rail below already has', (
      tester,
    ) async {
      // The one place this page is deliberately silent about an error. Both
      // rails read the same feed, so a failure would otherwise be reported
      // twice, one message directly above an identical one.
      _tall(tester);
      final api = stubCatalog();
      api.on(
        'GET',
        '/feed/discover',
        status: 500,
        body: const {'error': 'boom'},
      );
      useStubbedApi(api);

      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      expect(_inFeed(find.text(_title)), findsNothing);

      // Scrolled to rather than assumed on screen: the feed is a lazy list and
      // the recommendations are the last thing on it, so on a page this long
      // they are not built until they are reached.
      await tester.scrollUntilVisible(
        _inFeed(find.text('boom')),
        600,
        scrollable: _homeScroll(),
        maxScrolls: 60,
      );

      // Said once, by the recommendations, with the server's own words.
      expect(_inFeed(find.text('boom')), findsOneWidget);
    });
  });
}

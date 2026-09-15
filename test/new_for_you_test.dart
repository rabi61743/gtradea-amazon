import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/data/recently_viewed_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/for_you/data/for_you_feed.dart';
import 'package:gtradea_amazon/features/for_you/data/interest_profile.dart';
import 'package:gtradea_amazon/features/for_you/presentation/new_for_you_screen.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/search/data/recent_search_store.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:gtradea_amazon/shared/widgets/app_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// A catalogue row with its own id, so every source's products can be told
/// apart -- the only way to prove what the feed mixed and what it dropped.
Map<String, dynamic> _row(String id) => {
  ...feedRowJson,
  'num_iid': id,
  'title': 'Product $id',
  'display_price': 300,
};

List<Map<String, dynamic>> _rows(String prefix, int from, int count) => [
  for (var i = 0; i < count; i++) _row('$prefix-${from + i}'),
];

int _int(Object? value, int fallback) =>
    int.tryParse('${value ?? ''}') ?? fallback;

/// Real signals, of the kinds the feed reads: a cart line, a saved product
/// and a search.
void _giveSignals() {
  CartStore.instance.add(
    const CartLine(
      productId: 'cart-1',
      title: 'Summer Men Polo Shirt Short Sleeve',
      unitPrice: 500,
      quantity: 3,
      category: 'Men',
    ),
  );
  WishlistStore.instance.toggle(
    const SavedProduct(
      id: 'saved-1',
      title: 'Toy Car Racing Set',
      price: 100,
      category: 'Toys',
    ),
  );
  RecentSearchStore.instance.record('lamp');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    RecentlyViewedStore.instance.resetForTest();
    RecentSearchStore.instance.resetForTest();
    OrderStore.instance.resetForTest();
    NewForYouScreen.clearCacheForTest();

    // `Men` is in the stub's department tree as `dept-1`; `Toys` is not, so
    // it is searched for instead -- both paths get exercised.
    api = stubCatalog();
    api.onCall('GET', '/categories/dept-1/products', (call) {
      final offset = _int(call.query['page_offset'], 0);
      final size = _int(call.query['page_size'], 12);
      return reply(_rows('men-${call.query['sort']}', offset, size));
    });
    api.onCall('GET', '/search/products', (call) {
      final offset = _int(call.query['page_offset'], 0);
      final size = _int(call.query['page_size'], 12);
      return reply(
        _rows('find-${call.query['q']}-${call.query['sort']}', offset, size),
      );
    });
    api.onCall('GET', '/api/1688/search', (call) {
      final page = _int(call.query['page'], 1);
      return reply({
        'items': _rows('kw-${call.query['q']}', (page - 1) * 24, 24),
      });
    });
    api.onCall('GET', '/feed/discover', (call) {
      final offset = _int(call.query['page_offset'], 0);
      final size = _int(call.query['page_size'], 20);
      return reply(_rows('disc', offset, size));
    });
    api.onCall(
      'GET',
      '/feed/trending-products',
      (_) => reply(_rows('trend', 0, 20)),
    );
  });

  tearDown(clearApiStub);

  group('the interests', () {
    test('a catalogue title becomes a short phrase worth searching', () {
      expect(
        InterestSignals.phraseOf(
          "Summer Men's Polo Shirt with a New Style Short-Sleeve 2026",
        ),
        "summer men's polo shirt",
      );
    });

    test('come from what the shopper actually did', () async {
      _giveSignals();
      final profile = await InterestSignals.read();

      expect(profile.departments, containsAllInOrder(['Men', 'Toys']));
      expect(profile.phrases, contains('lamp'));
      expect(profile.phrases, contains('summer men polo shirt'));
      expect(profile.known, containsAll(['cart-1', 'saved-1']));
    });

    test('a new shopper has none, and that is said', () async {
      final profile = await InterestSignals.read();
      expect(profile.isEmpty, isTrue);
    });
  });

  group('the feed', () {
    test('mixes the familiar with the new, and never repeats itself', () async {
      _giveSignals();
      final profile = await InterestSignals.read();
      final feed = await ForYouFeed.build(profile);

      final first = await feed.nextPage(size: 20);
      final second = await feed.nextPage(size: 20);
      final ids = [...first, ...second].map((p) => p.numIid).toList();

      expect(first, hasLength(20));
      expect(ids.toSet(), hasLength(ids.length), reason: 'nothing twice');
      expect(ids, isNot(contains('cart-1')), reason: 'not what is in the cart');
      expect(ids, isNot(contains('saved-1')), reason: 'not what is saved');

      final familiar = ids.where((id) => !id.startsWith('disc-')).length;
      final discovery = ids.where((id) => id.startsWith('disc-')).length;
      expect(discovery, greaterThan(0), reason: 'something new mixed in');
      expect(
        familiar,
        greaterThan(discovery),
        reason: 'mostly their interests',
      );
      expect(
        ids.where((id) => id.startsWith('men-')),
        isNotEmpty,
        reason: 'from the department they buy in',
      );
      expect(
        ids.where((id) => id.startsWith('kw-lamp')),
        isNotEmpty,
        reason: 'from what they searched for',
      );
    });

    test('passes over what the last visit showed', () async {
      _giveSignals();
      final profile = await InterestSignals.read();
      final before = await (await ForYouFeed.build(profile)).nextPage();
      final shown = before.map((p) => p.numIid).toSet();

      final again = await (await ForYouFeed.build(
        profile,
        recentlyShown: shown,
      )).nextPage();

      expect(again, isNotEmpty);
      expect(
        again.map((p) => p.numIid).toSet().intersection(shown),
        isEmpty,
        reason: 'a fresh set on the next visit',
      );
    });

    test('a new shopper still gets something to browse', () async {
      final profile = await InterestSignals.read();
      final page = await (await ForYouFeed.build(profile)).nextPage();
      expect(page, isNotEmpty);
      expect(page.every((p) => p.numIid.startsWith('disc-')), isTrue);
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const NewForYouScreen()),
      );
    }

    testWidgets('shows the cards, and loads more as it is scrolled', (
      tester,
    ) async {
      _giveSignals();
      await tester.runAsync(() async {
        await pump(tester);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('New for You'), findsOneWidget);
      expect(find.byType(ProductResultCard), findsWidgets);

      // Measured by the page growing, not by requests: each source fetches
      // ahead, so the next page is often already in hand.
      ScrollPosition position() =>
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final before = position().maxScrollExtent;
      await tester.runAsync(() async {
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -6000),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();
      expect(
        position().maxScrollExtent,
        greaterThan(before),
        reason: 'the next page was added under the first',
      );
    });

    testWidgets('says so, with a retry, when nothing can be loaded', (
      tester,
    ) async {
      for (final path in [
        '/categories/dept-1/products',
        '/search/products',
        '/api/1688/search',
        '/feed/discover',
        '/feed/trending-products',
      ]) {
        api.on('GET', path, status: 500, body: const {'error': 'down'});
      }
      await tester.runAsync(() async {
        await pump(tester);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('Recommendations could not be loaded.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('the discovery grid', () {
    test('is two columns on a phone, and wider cards as the window grows', () {
      // Two on anything phone-sized -- three would put a 110pt card under a
      // thumb.
      expect(ResultGridSpec.discovery(360).columns, 2);
      expect(ResultGridSpec.discovery(412).columns, 2);
      expect(ResultGridSpec.discovery(768).columns, greaterThanOrEqualTo(3));

      // This asserted the opposite first: that a wide window should take the
      // width in *more* columns than the results page. That is a row of
      // thumbnails rather than a marketplace, and it was reversed by request.
      // Fewer columns at a fixed width is what "wider cards" means, so both
      // halves are pinned -- the count and the width it buys.
      expect(
        ResultGridSpec.discovery(1280).columns,
        lessThan(ResultGridSpec.search(1280).columns),
      );
      expect(
        ResultGridSpec.discovery(1280).cardWidth(1280),
        greaterThan(ResultGridSpec.search(1280).cardWidth(1280)),
      );
    });

    test('closes the gutters up without dropping a column', () {
      // The whole point of the spec: the same two columns a phone had, with
      // the points that were air given back to the pictures.
      const width = 412.0;
      final discovery = ResultGridSpec.discovery(width);
      final search = ResultGridSpec.search(width);

      expect(discovery.columns, search.columns);
      expect(discovery.gap, lessThan(search.gap));
      expect(discovery.cardPadding, lessThan(search.cardPadding));
      expect(
        discovery.cardWidth(width) - discovery.cardPadding * 2,
        greaterThan(search.cardWidth(width) - search.cardPadding * 2),
        reason: 'more picture in the same two columns',
      );
    });

    testWidgets('a dense card is measured dense', (tester) async {
      // heightFor feeds the grid's mainAxisExtent. Measured roomy but drawn
      // dense, the row is taller than the card and the grid floats it; drawn
      // roomy and measured dense, it clips. The flag has to reach both.
      late double roomy;
      late double dense;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              roomy = ProductResultCard.heightFor(context, 180);
              dense = ProductResultCard.heightFor(context, 180, dense: true);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(dense, lessThan(roomy));
    });
  });

  group('the bottom bar', () {
    // New for You held the bar's second slot until it moved to the department
    // strip. These tests asserted that slot: six destinations, the label in the
    // bar, and index 1 opening the feed. They are rewritten rather than deleted
    // -- the coverage that matters is that the bar still fits and still routes,
    // and dropping the tests with the destination would drop that too.
    testWidgets('is five destinations, and New for You is not among them', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(
              currentIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.text('New for You'), findsNothing);
      for (final label in ['Home', 'Saved', 'Cart', 'Categories']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('and the slots after the gap still report their own index', (
      tester,
    ) async {
      // The half of the removal that fails silently: every destination past the
      // one taken out shifts down, and a handler left on the old numbers sends
      // each to its neighbour's page.
      var picked = -1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(
              currentIndex: 0,
              onSelected: (i) => picked = i,
              isSignedIn: true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Saved'));
      expect(picked, 1);
      await tester.tap(find.text('Account'));
      expect(picked, 2);
      await tester.tap(find.text('Cart'));
      expect(picked, 3);
      await tester.tap(find.text('Categories'));
      expect(picked, 4);
    });

    testWidgets('fits the narrowest phone at the type people use', (
      tester,
    ) async {
      // 320dp at 1.3x. This was the check that six labels did not push the row
      // apart; at five it should be comfortable, and it is worth keeping as the
      // guard against a sixth ever creeping back in unnoticed.
      tester.view.physicalSize = const Size(640, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              bottomNavigationBar: AppBottomNav(
                currentIndex: 0,
                onSelected: (_) {},
                cartCount: 12,
                savedCount: 3,
                isSignedIn: true,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
    });

    testWidgets('and holds its shape on a tablet and a desktop window', (
      tester,
    ) async {
      // The app has one layout. There is no navigation rail and no breakpoint
      // that moves a destination anywhere else, so the same bar is what a
      // tablet and a desktop window get.
      for (final width in [320.0, 412.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width * 2, 1600);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              bottomNavigationBar: AppBottomNav(
                currentIndex: 0,
                onSelected: (_) {},
                cartCount: 12,
                savedCount: 3,
                isSignedIn: true,
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull, reason: '${width}dp');
        expect(find.byType(NavigationDestination), findsNWidgets(5));

        // Full width at every size: a bar that stopped short would be a second
        // layout quietly appearing at one breakpoint.
        expect(
          tester.getSize(find.byType(NavigationBar)).width,
          width,
          reason: '${width}dp',
        );
      }
    });
  });
}

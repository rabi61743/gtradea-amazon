import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/shared/widgets/animated_search_hint.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/product_rail.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// The home feed is a set of network reads now, so every test here needs a
/// catalogue behind it. Stubbed at the HTTP layer rather than at the
/// repository, so the decoding and the error handling are exercised too.
late FakeApi api;

/// A window tall enough to build the whole feed.
///
/// The default 800x600 test view stops building partway down a ListView, so
/// anything below the flash sale -- which sits near the top of the page -- is
/// never constructed and the finders come back empty. This is about the
/// harness, not about the layout.
void _tall(WidgetTester tester) {
  // Taller than it was: the promotional block grew by about 1200dp of
  // banners, and everything this file checks lives below it.
  tester.view.physicalSize = const Size(1100, 16000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// The feed's own scroll view.
///
/// Not `Scrollable.first` any more: the department strip under the search bar
/// is a horizontal ListView, and it now wins that race, so scrolling it looks
/// for the rails and never finds them.
Finder homeScroll() => find
    .descendant(of: find.byType(HomeFeed), matching: find.byType(Scrollable))
    .first;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
  });

  testWidgets('home renders search, the feed and the nav', (tester) async {
    _tall(tester);
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    // The placeholder cycles through examples now, so its exact text depends
    // on where the animation has got to. What matters here is that the search
    // bar is on the page.
    expect(find.byType(AnimatedSearchHint), findsOneWidget);
    // Once: the bottom bar's destination. The header's third tile is messages
    // now, by request, and the cart's way in from the top of the page went with
    // it -- the bar is where it lives.
    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);

    // The feed itself. Scrolled to, because "Recommended for you" sits below
    // "Shop by category" now rather than near the top.
    await tester.scrollUntilVisible(
      find.text('Recommended for you'),
      400,
      scrollable: homeScroll(),
    );
    expect(find.text('Recommended for you'), findsOneWidget);
  });

  testWidgets('a catalogue that will not load says so and offers a retry', (
    tester,
  ) async {
    // The important half of "the feed comes from a server": when the server
    // is down the page has to say so rather than showing an empty storefront
    // that looks like a catalogue with nothing in it.
    //
    // Tall, because the panel that says so belongs to the recommendation rail
    // and that rail is at the foot of the page now.
    _tall(tester);
    final broken = FakeApi()
      ..on('GET', '/feed/discover', status: 500, body: {'error': 'boom'})
      ..on('GET', '/alibaba-categories', body: const [])
      ..on('GET', '/hero-banners', body: const []);
    useStubbedApi(broken);

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Try again'), findsWidgets);
  });

  testWidgets('one failing rail does not take the rest of the page with it', (
    tester,
  ) async {
    _tall(tester);
    final partly = stubCatalog();
    partly.on(
      'GET',
      '/feed/trending-products',
      status: 500,
      body: {'error': 'rail is down'},
    );

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    // The recommendation rail still loaded from a different endpoint.
    await tester.scrollUntilVisible(
      find.text('Recommended for you'),
      400,
      scrollable: homeScroll(),
    );
    expect(find.text('Recommended for you'), findsOneWidget);
  });

  testWidgets('the bottom bar is shortcuts, and Home stays the shell', (
    tester,
  ) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    // Every other destination opens on top of Home rather than switching a
    // tab, so the selection never moves off Home -- highlighting a destination
    // for a page that had since been popped would be a lie.
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    // The pushed screen carries the same name the destination did.
    expect(find.text('Categories'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('uses the GtradeA teal primary, not a Flutter default', (
    tester,
  ) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.colorScheme.primary, AppColors.primaryLight);
    await tester.pumpAndSettle();
  });

  testWidgets('stays on the white version even when the device is dark', (
    tester,
  ) async {
    // themeMode is pinned to light, so a dark platform brightness must not
    // flip the app -- that is what "white version" means here.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const GtradeaAmazonApp());
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, AppColors.backgroundLight);
    await tester.pumpAndSettle();
  });

  testWidgets('product cards show what the catalogue actually returned', (
    tester,
  ) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Recommended for you'),
      400,
      scrollable: homeScroll(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catalogue product 0'), findsWidgets);
    expect(find.text('Rs. 300'), findsWidgets);
  });

  testWidgets('no strike-through price is invented', (tester) async {
    // The feed publishes one price per product. A crossed-out "was" figure
    // would have to come from a markup nobody publishes, which makes it a
    // false saving rather than a missing feature.
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Recommended for you'),
      400,
      scrollable: homeScroll(),
    );
    await tester.pumpAndSettle();

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.decoration, isNot(TextDecoration.lineThrough));
    }
  });

  testWidgets('the department index is off the home page, not out of reach', (
    tester,
  ) async {
    // "Shop by category" used to close the feed. It was removed by request, and
    // this is the assertion that says the departments did not go with it: the
    // tab strip pinned to the header still names them, and the Browse screen
    // still lists every one.
    _tall(tester);
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    expect(find.text('Shop by category'), findsNothing);
    expect(find.text('Women'), findsWidgets);
  });

  testWidgets('each department gets a Browse section, and costs no request', (
    tester,
  ) async {
    // This used to assert the opposite: that every department fetched a rail
    // of its own best sellers. The rails are gone by request -- nine rails under
    // department headings was the same shape repeated down the page
    // was the same shape repeated down the page.
    //
    // What is left is worth pinning, because it is the reason the removal was
    // free: the Browse sections are built from the category tree that is
    // already in memory. If a department block ever starts fetching again, the
    // page silently goes back to nine requests nobody asked for.
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Browse Women'),
      500,
      scrollable: homeScroll(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Browse Women'), findsOneWidget);
    // The subcategory names the tree actually carries.
    expect(find.text('Women item 0'), findsWidgets);

    final railCalls = api.calls.where(
      (c) =>
          c.path == '/feed/trending-products' &&
          c.query['category_cid'] != null,
    );
    expect(railCalls, isEmpty, reason: 'a department block fetched a rail');
  });

  testWidgets('the catalogue is fetched without a credential', (tester) async {
    // Browsing is public. A guest session should not be carrying a bearer
    // token it has no use for.
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    for (final call in api.calls) {
      expect(call.authorization, isNull, reason: call.path);
    }
  });

  group('formatRupees', () {
    test('groups thousands', () {
      expect(formatRupees(8990), 'Rs. 8,990');
      expect(formatRupees(27590), 'Rs. 27,590');
      expect(formatRupees(1234567), 'Rs. 1,234,567');
    });

    test('leaves short values ungrouped and rounds to whole rupees', () {
      expect(formatRupees(999), 'Rs. 999');
      expect(formatRupees(0), 'Rs. 0');
      expect(formatRupees(1250.6), 'Rs. 1,251');
    });

    test('and a negative keeps its sign out of the grouping', () {
      // The separator was counted from the start of the string with the minus
      // sign included, so a four-character "-120" got one straight after the
      // sign: "-,120". Nothing showed it while the only figures were prices,
      // which are never negative. The coins page found it, printing what an
      // account had spent through the same grouper underneath this.
      expect(formatRupees(-120), 'Rs. -120');
      expect(formatRupees(-27590), 'Rs. -27,590');
      expect(formatRupees(-1), 'Rs. -1');
    });
  });

  testWidgets('Saved opens the wishlist without stealing the nav selection', (
    tester,
  ) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    // The wishlist is a page on top, so Home stays selected underneath.
    expect(find.text('Nothing saved yet'), findsOneWidget);
  });
}

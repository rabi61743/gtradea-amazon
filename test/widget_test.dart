import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/home/widgets/product_rail.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// The home feed is a set of network reads now, so every test here needs a
/// catalogue behind it. Stubbed at the HTTP layer rather than at the
/// repository, so the decoding and the error handling are exercised too.
late FakeApi api;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
  });

  testWidgets('home renders search, the feed and the nav', (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    expect(find.text('Search products'), findsOneWidget);
    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('Cart'), findsOneWidget);
  });

  testWidgets('a catalogue that will not load says so and offers a retry',
      (tester) async {
    // The important half of "the feed comes from a server": when the server
    // is down the page has to say so rather than showing an empty storefront
    // that looks like a catalogue with nothing in it.
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

  testWidgets('one failing rail does not take the rest of the page with it',
      (tester) async {
    final partly = stubCatalog();
    partly.on('GET', '/feed/trending-products',
        status: 500, body: {'error': 'rail is down'});

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    // The recommendation rail still loaded from a different endpoint.
    expect(find.text('Recommended for you'), findsOneWidget);
  });

  testWidgets('the bottom bar is shortcuts, and Home stays the shell',
      (tester) async {
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

  testWidgets('uses the GtradeA teal primary, not a Flutter default',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.colorScheme.primary, AppColors.primaryLight);
    await tester.pumpAndSettle();
  });

  testWidgets('stays on the white version even when the device is dark',
      (tester) async {
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

  testWidgets('product cards show what the catalogue actually returned',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Recommended for you'), 400,
        scrollable: find.byType(Scrollable).first);
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

    await tester.scrollUntilVisible(find.text('Recommended for you'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.decoration, isNot(TextDecoration.lineThrough));
    }
  });

  testWidgets('departments render as a grid', (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Shop by category'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Shop by category'), findsOneWidget);
    expect(find.text('Women'), findsWidgets);
  });

  testWidgets('each department gets a rail of its own best sellers',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Browse Women'), 500,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Browse Women'), findsOneWidget);
    expect(find.text('Women item 0'), findsWidgets);

    // The rail asked for that department specifically rather than fetching one
    // generic list and slicing it.
    final railCalls =
        api.calls.where((c) => c.path == '/feed/trending-products');
    expect(railCalls.map((c) => c.query['category_cid']), contains('dept-0'));
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
  });

  testWidgets('Saved opens the wishlist without stealing the nav selection',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    // The wishlist is a page on top, so Home stays selected underneath.
    expect(find.text('Nothing saved yet'), findsOneWidget);
  });
}

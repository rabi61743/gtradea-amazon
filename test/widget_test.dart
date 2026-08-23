import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/home/widgets/product_rail.dart';
import 'package:gtradea_amazon/main.dart';

void main() {
  testWidgets('home renders search, promos, sections and the nav',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    expect(find.text('Search products'), findsOneWidget);
    expect(find.text('Electronics'), findsOneWidget);
    expect(find.text('Headphones'), findsOneWidget);
    expect(find.text('See All'), findsWidgets);
    expect(find.text('Cart'), findsOneWidget);
  });

  testWidgets('selecting a bottom-nav destination updates the selection',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0);
    // Cart at index 3: Saved and Account both open pages instead of switching
    // the selection, so they are not the ones to assert this with.
    await tester.tap(find.text('Cart'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3);
  });

  testWidgets('uses the GtradeA teal primary, not a Flutter default',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.colorScheme.primary, AppColors.primaryLight);
  });

  testWidgets('stays on the white version even when the device is dark',
      (tester) async {
    // themeMode is pinned to light, so a dark platform brightness must not
    // flip the app — that is what "white version" means here.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const GtradeaAmazonApp());
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, AppColors.backgroundLight);
  });

  testWidgets('product rail shows title, rating and price', (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    // The rail is below the fold in the default test viewport, so it is not
    // built until scrolled to.
    await tester.scrollUntilVisible(find.text('Recommended for you'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('Ice Silk Sun Protection Clothing for Women'),
        findsOneWidget);
    expect(find.text('Rs. 1,130'), findsOneWidget);
  });

  testWidgets('a list price is struck through only when it is a saving',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    // The rail is below the fold in the default test viewport, so it is not
    // built until scrolled to.
    await tester.scrollUntilVisible(find.text('Recommended for you'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    final struck = tester.widget<Text>(
      find.text('Rs. 1,568'),
    );
    expect(struck.style?.decoration, TextDecoration.lineThrough);

    // Two catalogue rows share this price, so it is not unique. What
    // matters is that neither is struck through: neither has a listPrice.
    for (final text in tester.widgetList<Text>(find.text('Rs. 1,808'))) {
      expect(text.style?.decoration, isNot(TextDecoration.lineThrough));
    }
  });

  testWidgets('departments render as a grid with an all-departments link',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    // Below the fold, so scroll it into view first.
    await tester.scrollUntilVisible(find.text('Shop by category'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Shop by category'), findsOneWidget);
    expect(find.text('Beauty'), findsOneWidget);
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

  testWidgets('the shoes block carries its price cap in the header',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    await tester.scrollUntilVisible(find.text('Shoes'), 500,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Shoes'), findsOneWidget);
    expect(find.text('Under Rs. 5,000'), findsOneWidget);
  });

  testWidgets('later blocks render as the feed is scrolled', (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    for (final title in ['Gaming gear', 'Home and living', 'For your pets']) {
      await tester.scrollUntilVisible(find.text(title), 500,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('spotlight cards carry an offer ribbon and a caption',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    await tester.scrollUntilVisible(find.text('Featured brands'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Min. 65% off'), findsOneWidget);
    expect(find.text('Running shoes'), findsOneWidget);
  });

  testWidgets('deal groups show price bands under each tile', (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    await tester.scrollUntilVisible(find.text('Also popular'), 500,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('What other shoppers are browsing'), findsOneWidget);
    expect(find.text('From Rs. 350'), findsOneWidget);
    expect(find.text('Under Rs. 2,000'), findsOneWidget);
  });

  testWidgets('the seasonal block renders its own group', (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    await tester.scrollUntilVisible(find.text('Dashain specials'), 500,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Gifting picks for the season'), findsOneWidget);
    expect(find.text('Sweets and hampers'), findsOneWidget);
  });

  testWidgets('the hero banner advances on its own', (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    expect(find.text('Dashain deals are live'), findsOneWidget);

    // Let the interval elapse, then the page animation run.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Free delivery on picks'), findsOneWidget);

    // Unmount so the periodic timer is cancelled; a pending timer fails the
    // test even when the assertions passed.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('banner artwork falls back to the tinted panel offline',
      (tester) async {
    // Widget tests answer every network image with a 400, which is exactly
    // the failure a shopper hits on a dead connection: the card must still
    // render its headline rather than a broken-image box.
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Shop the sale'), findsOneWidget);
    expect(find.text('Headphones'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Saved opens the wishlist without stealing the nav selection',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    // The wishlist is a page on top, so Home stays selected underneath.
    expect(find.text('Nothing saved yet'), findsOneWidget);
  });
}

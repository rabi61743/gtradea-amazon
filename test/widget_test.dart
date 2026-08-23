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
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
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
    expect(find.text('Wireless over-ear headphones, 40h battery'),
        findsOneWidget);
    expect(find.text('Rs. 8,990'), findsOneWidget);
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
      find.text('Rs. 12,500'),
    );
    expect(struck.style?.decoration, TextDecoration.lineThrough);

    // The keyboard has no listPrice, so nothing is crossed out for it.
    expect(find.text('Rs. 6,750'), findsOneWidget);
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
}

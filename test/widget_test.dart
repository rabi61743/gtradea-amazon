import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/main.dart';

void main() {
  testWidgets('home renders search, promos, sections and the nav',
      (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());

    expect(find.text('Search products'), findsOneWidget);
    expect(find.text('Plug in with our electronics'), findsOneWidget);
    expect(find.text('Headphones'), findsOneWidget);
    expect(find.text('Shop more'), findsWidgets);
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
}

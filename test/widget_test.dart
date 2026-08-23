import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/main.dart';

void main() {
  testWidgets('app boots and shows the placeholder home', (tester) async {
    await tester.pumpWidget(const GtradeaAmazonApp());
    expect(find.text('GtradeA Amazon'), findsWidgets);
    expect(find.text('Primary action'), findsOneWidget);
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

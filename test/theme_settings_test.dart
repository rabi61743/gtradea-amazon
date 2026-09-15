import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/theme_settings.dart';
import 'package:gtradea_amazon/features/settings/presentation/theme_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's root, as `main.dart` builds it: the theme follows the setting.
Widget _app({Widget home = const ThemeScreen()}) => ListenableBuilder(
  listenable: ThemeSettings.instance,
  builder: (context, _) => MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeSettings.instance.mode,
    themeAnimationDuration: const Duration(milliseconds: 250),
    themeAnimationCurve: Curves.easeInOut,
    home: home,
  ),
);

Color _page(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(
        of: find.byType(Scaffold),
        matching: find.byType(Material),
      ).first,
    )
    .color!;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeSettings.instance.resetForTest();
  });

  group('the setting', () {
    test('is light until chosen, and remembers a choice', () async {
      await ThemeSettings.instance.load();
      expect(ThemeSettings.instance.mode, ThemeMode.light);

      await ThemeSettings.instance.setMode(ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('gtradea_theme_mode'), 'dark');

      // A fresh start reads it back.
      ThemeSettings.instance.resetForTest();
      await ThemeSettings.instance.load();
      expect(ThemeSettings.instance.mode, ThemeMode.dark);
    });

    test('an unknown stored value falls back to light', () async {
      SharedPreferences.setMockInitialValues({'gtradea_theme_mode': 'sepia'});
      await ThemeSettings.instance.load();
      expect(ThemeSettings.instance.mode, ThemeMode.light);
    });
  });

  group('the screen', () {
    testWidgets('offers the three, with the current one marked', (
      tester,
    ) async {
      await ThemeSettings.instance.load();
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      for (final label in ['Light', 'Dark', 'System']) {
        expect(find.text(label), findsOneWidget);
      }
      final selected = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.selected == true)
          .toList();
      expect(selected, hasLength(1));
    });

    testWidgets('a choice applies at once, with a short fade between', (
      tester,
    ) async {
      await ThemeSettings.instance.load();
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final light = _page(tester);
      expect(light, AppTheme.light.scaffoldBackgroundColor);

      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      // Midway: neither the old colour nor the new one -- a fade, not a cut.
      final midway = _page(tester);
      expect(midway, isNot(light));
      expect(midway, isNot(AppTheme.dark.scaffoldBackgroundColor));

      await tester.pumpAndSettle();
      expect(_page(tester), AppTheme.dark.scaffoldBackgroundColor);
      expect(ThemeSettings.instance.mode, ThemeMode.dark);
    });

    testWidgets('System follows the device, and switches when it does', (
      tester,
    ) async {
      await ThemeSettings.instance.load();
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpWidget(_app());
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(_page(tester), AppTheme.light.scaffoldBackgroundColor);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(_page(tester), AppTheme.dark.scaffoldBackgroundColor);
    });

    testWidgets('a saved Dark is dark on the very first frame', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'gtradea_theme_mode': 'dark'});
      await ThemeSettings.instance.load();
      await tester.pumpWidget(_app());
      // No settle: this is the first frame, with nothing to fade from.
      expect(_page(tester), AppTheme.dark.scaffoldBackgroundColor);
    });

    testWidgets('fits a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(640, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await ThemeSettings.instance.load();
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

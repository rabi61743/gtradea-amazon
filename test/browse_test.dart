import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/l10n/app_strings.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_content.dart';
import 'package:gtradea_amazon/features/catalog/presentation/browse_screen.dart';
import 'package:gtradea_amazon/features/catalog/widgets/category_nav.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/features/settings/presentation/language_screen.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

/// A phone-shaped window: the nav should be the horizontal strip.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// A desktop-shaped window: the nav should be the side rail.
void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(2600, 1800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Which department the navigator is showing as active.
int _activeIndex(WidgetTester tester) =>
    tester.widget<CategoryNav>(find.byType(CategoryNav)).active;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    LanguageStore.instance.resetForTest();
  });

  group('CatalogContent', () {
    test('every department has something in it', () {
      expect(CatalogContent.departments, isNotEmpty);
      for (final department in CatalogContent.departments) {
        expect(department.groups, isNotEmpty, reason: department.label);
        expect(department.entryCount, greaterThan(0), reason: department.label);
        for (final group in department.groups) {
          expect(group.entries, isNotEmpty,
              reason: '${department.label} / ${group.title}');
        }
      }
    });

    test('department names are unique', () {
      final labels = CatalogContent.departments.map((d) => d.label).toList();
      expect(labels.toSet().length, labels.length);
    });
  });

  group('translations', () {
    test('every department and group name has a Nepali translation', () {
      // A missing one falls back to English, which is safe but silent. This
      // makes adding a category without translating it a visible failure.
      final ne = AppStrings.ne;
      for (final department in CatalogContent.departments) {
        expect(ne.departmentNames, contains(department.label),
            reason: department.label);
        for (final group in department.groups) {
          expect(ne.groupNames, contains(group.title), reason: group.title);
        }
      }
    });

    test('an untranslated name falls back to English rather than blank', () {
      expect(AppStrings.ne.department('Brand new department'),
          'Brand new department');
      expect(AppStrings.en.department('Electronics'), 'Electronics');
    });

    test('counts are built by the language, not glued to a translated word',
        () {
      expect(AppStrings.en.categoryCount(12), '12 categories');
      expect(AppStrings.ne.categoryCount(12), contains('12'));
      expect(AppStrings.ne.categoryCount(12), isNot('12 categories'));
    });

    test('the store remembers the choice', () async {
      LanguageStore.instance.setLanguage(AppLanguage.nepali);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      LanguageStore.instance.resetForTest();
      await LanguageStore.instance.load();
      expect(LanguageStore.instance.language, AppLanguage.nepali);
    });

    test('an unknown stored code falls back to English', () async {
      SharedPreferences.setMockInitialValues({'gtradea_language': 'klingon'});
      LanguageStore.instance.resetForTest();
      await LanguageStore.instance.load();
      expect(LanguageStore.instance.language, AppLanguage.english);
    });
  });

  group('layout', () {
    testWidgets('a phone gets the horizontal strip', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      expect(tester.widget<CategoryNav>(find.byType(CategoryNav)).vertical,
          isFalse);
    });

    testWidgets('a wide window gets the side rail', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      expect(tester.widget<CategoryNav>(find.byType(CategoryNav)).vertical,
          isTrue);
    });

    testWidgets('every department is reachable in the navigator',
        (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      for (final department in CatalogContent.departments) {
        expect(find.text(department.label), findsWidgets,
            reason: department.label);
      }
    });
  });

  group('scroll tracking', () {
    testWidgets('opens on the first department', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();
      expect(_activeIndex(tester), 0);
    });

    testWidgets('scrolling down moves the active department along',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1400),
      );
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), greaterThan(0),
          reason: 'the navigator follows the scroll');
    });

    testWidgets('scrolling back up returns to the first department',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1400),
      );
      await tester.pumpAndSettle();
      expect(_activeIndex(tester), greaterThan(0));

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 3000),
      );
      await tester.pumpAndSettle();
      expect(_activeIndex(tester), 0);
    });

    testWidgets('tapping a department scrolls to it and marks it active',
        (tester) async {
      // The side rail, where every department is on screen without scrolling
      // the navigator itself first.
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final target = CatalogContent.departments[3];
      await tester.tap(find.descendant(
        of: find.byType(CategoryNav),
        matching: find.text(target.label),
      ));
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), 3);
      // Landing on it means its banner is on screen, not merely selected in
      // the navigator.
      expect(find.text(target.tagline), findsOneWidget);
    });

    testWidgets('the tracker does not flicker through sections en route',
        (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final seen = <int>{};
      await tester.tap(find.descendant(
        of: find.byType(CategoryNav),
        matching: find.text(CatalogContent.departments[5].label),
      ));

      // Sample the active index across the animation. It must go straight to
      // the target rather than sweeping through every department in between,
      // which is what makes a tap feel like a jump instead of a slot machine.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        seen.add(_activeIndex(tester));
      }
      await tester.pumpAndSettle();

      expect(seen, {5}, reason: 'the active item never left the target');
    });

    testWidgets('a tap still works after the shopper has scrolled by hand',
        (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byType(CategoryNav),
        matching: find.text(CatalogContent.departments.first.label),
      ));
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), 0);
      expect(find.text(CatalogContent.departments.first.tagline),
          findsOneWidget);
    });

    testWidgets('opening at a department starts there', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen(initialDepartment: 2)));
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), 2);
      expect(find.text(CatalogContent.departments[2].tagline), findsOneWidget);
    });

    testWidgets('an out-of-range index falls back rather than crashing',
        (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen(initialDepartment: 99)));
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), CatalogContent.departments.length - 1);
    });
  });

  group('content', () {
    testWidgets('a category tile searches for that category', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final entry = CatalogContent.departments.first.groups.first.entries.first;
      await tester.tap(find.text(entry.label).first);
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
    });

    testWidgets('the cart badge is live here too', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsNothing);

      CartStore.instance.add(const CartLine(
        productId: 'jacket',
        title: 'Ice silk jacket',
        unitPrice: 1130,
      ));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });
  });

  group('language', () {
    testWidgets('switching to Nepali renames the screen and the departments',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Electronics'), findsWidgets);

      LanguageStore.instance.setLanguage(AppLanguage.nepali);
      await tester.pumpAndSettle();

      expect(find.text('श्रेणीहरू'), findsOneWidget);
      expect(find.text('इलेक्ट्रोनिक्स'), findsWidgets);
      expect(find.text('Categories'), findsNothing);
    });

    testWidgets('the real app runs in Nepali without losing its framework '
        'localizations', (tester) async {
      // Setting MaterialApp.locale to a non-English code without registering
      // the delegates leaves Material widgets with nothing to read, and the
      // first nav bar or tooltip throws. The other tests here wrap screens in
      // their own MaterialApp, so only the real one catches it.
      _phone(tester);
      LanguageStore.instance.setLanguage(AppLanguage.nepali);

      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('श्रेणीहरू'), findsWidgets,
          reason: 'the bottom bar speaks Nepali too');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the picker offers each language in its own script',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const LanguageScreen()));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('नेपाली'), findsOneWidget);
      // The English name sits under the endonym so someone stuck in a script
      // they cannot read can still find their way back.
      expect(find.text('Nepali'), findsOneWidget);
    });

    testWidgets('choosing a language takes effect immediately', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const LanguageScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('नेपाली'));
      await tester.pumpAndSettle();

      expect(LanguageStore.instance.language, AppLanguage.nepali);
      expect(find.text('भाषा'), findsOneWidget);
    });
  });
}

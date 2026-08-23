import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_content.dart';
import 'package:gtradea_amazon/features/catalog/presentation/browse_screen.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
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
      final labels =
          CatalogContent.departments.map((d) => d.label).toList();
      expect(labels.toSet().length, labels.length);
    });

    test('popular samples across groups rather than repeating the first', () {
      // Electronics has three groups, so the strip should reach into more than
      // one of them -- otherwise it is just the first section shown twice.
      final electronics = CatalogContent.departments
          .firstWhere((d) => d.label == 'Electronics');
      final first = electronics.groups.first.entries.map((e) => e.label).toSet();
      final popular = electronics.popular.map((e) => e.label).toSet();

      expect(popular.length, greaterThan(1));
      expect(
        popular.any((label) => !first.contains(label)),
        isTrue,
        reason: 'the strip should sample the whole department',
      );
    });

    test('popular is capped so the strip stays a sample', () {
      for (final department in CatalogContent.departments) {
        expect(department.popular.length, lessThanOrEqualTo(6),
            reason: department.label);
      }
    });

    test('a department with one small group still works', () {
      // The sampler walks two levels deep across groups; a department with a
      // single three-entry group must not trip it.
      final beauty =
          CatalogContent.departments.firstWhere((d) => d.label == 'Beauty');
      expect(beauty.groups.length, 1);
      expect(beauty.popular.length, 2);
    });
  });

  group('BrowseScreen', () {
    testWidgets('opens on the first department with its groups', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final first = CatalogContent.departments.first;
      expect(find.text(first.tagline), findsOneWidget);
      expect(find.text('${first.entryCount} categories'), findsOneWidget);
      for (final group in first.groups) {
        expect(find.text(group.title), findsOneWidget, reason: group.title);
      }
    });

    testWidgets('every department is listed in the rail', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      // The rail is scrollable, so later departments are found by scrolling
      // rather than assumed to be laid out.
      for (final department in CatalogContent.departments) {
        await tester.scrollUntilVisible(
          find.text(department.label).first,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(department.label), findsWidgets,
            reason: department.label);
      }
    });

    testWidgets('picking a department swaps the pane', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final second = CatalogContent.departments[1];
      await tester.tap(find.text(second.label).first);
      await tester.pumpAndSettle();

      expect(find.text(second.tagline), findsOneWidget);
      expect(find.text(CatalogContent.departments.first.tagline), findsNothing);
    });

    testWidgets('an initial department can be opened directly', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen(initialDepartment: 2)));
      await tester.pumpAndSettle();

      expect(find.text(CatalogContent.departments[2].tagline), findsOneWidget);
    });

    testWidgets('an out-of-range index falls back rather than crashing',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen(initialDepartment: 99)));
      await tester.pumpAndSettle();

      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(
        find.text(CatalogContent.departments.last.tagline),
        findsOneWidget,
      );
    });

    testWidgets('a category tile searches for that category', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final entry = CatalogContent.departments.first.groups.first.entries.first;
      // The label appears in both the popular strip and the grid; either is a
      // legitimate route to the same search.
      await tester.tap(find.text(entry.label).first);
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
    });

    testWidgets('the pane ends by saying so rather than trailing off',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final first = CatalogContent.departments.first;
      // The pane, found by its key: the rail and the horizontal popular strip
      // are Scrollables too, and picking one of those scrolls nothing useful.
      await tester.scrollUntilVisible(
        find.text('That is everything in ${first.label}.'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(ValueKey(first.label)),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text('That is everything in ${first.label}.'),
        findsOneWidget,
      );
    });

    testWidgets('the cart badge is live here too', (tester) async {
      _useTallWindow(tester);
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
}

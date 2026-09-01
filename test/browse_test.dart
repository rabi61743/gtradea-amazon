import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/l10n/app_strings.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/catalog/data/department.dart';
import 'package:gtradea_amazon/features/catalog/presentation/browse_screen.dart';
import 'package:gtradea_amazon/features/catalog/widgets/category_nav.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/features/settings/presentation/language_screen.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:gtradea_amazon/shared/widgets/artwork_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

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

/// How many departments the stub serves. Seven, so the index-based assertions
/// below have somewhere to scroll to.
const _departmentCount = 7;

final _names = stubDepartmentNames(_departmentCount);

/// The departments as the screen builds them, for asserting against.
List<Department> _departments() => departmentsFrom(
  CatalogStore.instance.categories.value ?? const <Category>[],
  onOpen: (_) {},
);

/// The stub currently behind the app, so a test can count what was asked of it.
late FakeApi api;

/// Replaces the stub mid-test, for the cases that need a differently shaped
/// catalogue than the default.
void restub({
  int departments = _departmentCount,
  int childrenEach = 3,
  bool childImages = true,
}) {
  api = stubCatalog(
    departments: departments,
    childrenEach: childrenEach,
    childImages: childImages,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    LanguageStore.instance.resetForTest();
    restub();
  });

  group('the browse tree', () {
    test('every department the server sends becomes a section', () async {
      await CatalogStore.instance.categories.load();
      final departments = _departments();

      expect(departments, hasLength(_departmentCount));
      for (final department in departments) {
        expect(department.groups, isNotEmpty, reason: department.label);
        expect(department.entryCount, greaterThan(0), reason: department.label);
      }
    });

    test('a department with no subcategories still appears', () async {
      // The server has leaf departments, and dropping them would hide part of
      // the catalogue from browse entirely.
      final departments = departmentsFrom(const [
        Category(cid: 'x', name: 'Odds and ends'),
      ], onOpen: (_) {});

      expect(departments.single.label, 'Odds and ends');
      expect(departments.single.groups, isEmpty);
      expect(departments.single.tagline, contains('Odds and ends'));
    });

    test('the tagline names what is actually inside', () async {
      final departments = departmentsFrom([
        Category(cid: 'p', name: 'Home').withChildren(const [
          Category(cid: 'a', name: 'Kitchen'),
          Category(cid: 'b', name: 'Bedding'),
          Category(cid: 'c', name: 'Lighting'),
          Category(cid: 'd', name: 'Storage'),
        ]),
      ], onOpen: (_) {});

      expect(
        departments.single.tagline,
        'Kitchen, Bedding, Lighting and 1 more',
      );
    });

    test('a subcategory tile opens that category, not a text search', () {
      // Searching the words "Kitchen" and browsing the Kitchen category are
      // different queries, and only one of them is what was tapped.
      Category? opened;
      final departments = departmentsFrom([
        Category(
          cid: 'p',
          name: 'Home',
        ).withChildren(const [Category(cid: 'kitchen', name: 'Kitchen')]),
      ], onOpen: (category) => opened = category);

      departments.single.groups.single.entries.single.onTap!();
      expect(opened?.cid, 'kitchen');
    });
  });

  group('translations', () {
    test('an untranslated name falls back to English rather than blank', () {
      // Department names come from the server now, so most of them will never
      // have a translation. Falling back to the server's own wording is the
      // only workable answer -- a blank tile is not.
      expect(
        AppStrings.ne.department('Brand new department'),
        'Brand new department',
      );
      expect(AppStrings.en.department('Electronics'), 'Electronics');
    });

    test(
      'counts are built by the language, not glued to a translated word',
      () {
        expect(AppStrings.en.categoryCount(12), '12 categories');
        expect(AppStrings.ne.categoryCount(12), contains('12'));
        expect(AppStrings.ne.categoryCount(12), isNot('12 categories'));
      },
    );

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

      expect(
        tester.widget<CategoryNav>(find.byType(CategoryNav)).vertical,
        isFalse,
      );
    });

    testWidgets('a wide window gets the side rail', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      expect(
        tester.widget<CategoryNav>(find.byType(CategoryNav)).vertical,
        isTrue,
      );
    });

    testWidgets('every department is reachable in the navigator', (
      tester,
    ) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      for (final name in _names) {
        expect(find.text(name), findsWidgets, reason: name);
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

    testWidgets('scrolling down moves the active department along', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1400),
      );
      await tester.pumpAndSettle();

      expect(
        _activeIndex(tester),
        greaterThan(0),
        reason: 'the navigator follows the scroll',
      );
    });

    testWidgets('scrolling back up returns to the first department', (
      tester,
    ) async {
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

    testWidgets('tapping a department scrolls to it and marks it active', (
      tester,
    ) async {
      // The side rail, where every department is on screen without scrolling
      // the navigator itself first.
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final target = _departments()[3];
      await tester.tap(
        find.descendant(
          of: find.byType(CategoryNav),
          matching: find.text(target.label),
        ),
      );
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), 3);
      // Landing on it means its banner is on screen, not merely selected in
      // the navigator.
      expect(find.text(target.tagline), findsOneWidget);
    });

    testWidgets('the tracker does not flicker through sections en route', (
      tester,
    ) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final seen = <int>{};
      await tester.tap(
        find.descendant(
          of: find.byType(CategoryNav),
          matching: find.text(_names[5]),
        ),
      );

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

    testWidgets('a tap still works after the shopper has scrolled by hand', (
      tester,
    ) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(CategoryNav),
          matching: find.text(_names.first),
        ),
      );
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), 0);
      expect(find.text(_departments().first.tagline), findsOneWidget);
    });

    testWidgets('opening at a department starts there', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen(initialDepartment: 2)));
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), 2);
      expect(find.text(_departments()[2].tagline), findsOneWidget);
    });

    testWidgets('an out-of-range index falls back rather than crashing', (
      tester,
    ) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen(initialDepartment: 99)));
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), _departmentCount - 1);
    });
  });

  group('content', () {
    testWidgets('a category tile searches for that category', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final entry = _departments().first.groups.first.entries.first;
      await tester.tap(find.text(entry.label).first);
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
    });

    testWidgets('the cart badge is live here too', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsNothing);

      CartStore.instance.add(
        const CartLine(
          productId: 'jacket',
          title: 'Ice silk jacket',
          unitPrice: 1130,
        ),
      );
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });
  });

  group('language', () {
    testWidgets('switching to Nepali renames the screen and the departments', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      // 'Women', not 'Electronics'. The translation map is keyed by the names
      // the server actually sends, and the department it used to assert on was
      // a leftover key from a hardcoded catalogue that no longer exists -- it
      // matched nothing, so this assertion was passing on a name no shopper
      // would ever have seen translated.
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Women'), findsWidgets);

      LanguageStore.instance.setLanguage(AppLanguage.nepali);
      await tester.pumpAndSettle();

      expect(find.text('श्रेणीहरू'), findsOneWidget);
      expect(find.text('महिला'), findsWidgets);
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
      // Settled rather than pumped once: the home feed fires a request per
      // department rail, and a half-finished one is a pending timer at
      // teardown.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('श्रेणीहरू'),
        findsWidgets,
        reason: 'the bottom bar speaks Nepali too',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the picker offers each language in its own script', (
      tester,
    ) async {
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

  group('subcategory pictures', () {
    testWidgets('a tile is given the picture the server sent for it', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      // The tiles used to draw a keyword-matched glyph and throw this away.
      expect(_childImages(tester), isNotEmpty);
    });

    testWidgets('a subcategory with no picture still gets its glyph', (
      tester,
    ) async {
      restub(departments: 2, childImages: false);
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final tiles = _tilePanels(tester);
      expect(tiles, isNotEmpty);
      // Null is what ArtworkPanel already draws as a tinted panel, so a
      // catalogue without artwork looks exactly as it did before.
      expect(tiles.every((panel) => panel.imageUrl == null), isTrue);
    });

    testWidgets('departments far down the page do not fetch until neared', (
      tester,
    ) async {
      // The catalogue is built all at once so the navigator can measure it.
      // Every tile that exists resolves its image whether or not anyone can
      // see it, so without the viewport gate this screen would open by asking
      // for a thousand photographs.
      restub(departments: 20);
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final atTop = _childImages(tester).length;
      expect(atTop, greaterThan(0), reason: 'the visible ones do load');
      expect(atTop, lessThan(20 * 3), reason: 'but not all sixty of them');

      await tester.fling(_catalogue, const Offset(0, -6000), 4000);
      await tester.pumpAndSettle();

      expect(_childImages(tester).length, greaterThan(atTop));
    });
  });

  group('a department with nothing under it', () {
    testWidgets('says so rather than leaving a heading over blank space', (
      tester,
    ) async {
      restub(departments: 2, childrenEach: 0);
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('No subcategories here yet'), findsWidgets);
    });

    testWidgets('opens the department itself, not a text search for its name', (
      tester,
    ) async {
      restub(departments: 1, childrenEach: 0);
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('No subcategories here yet'));
      await tester.pumpAndSettle();

      // Browsing a category and searching its name as words are two different
      // queries, and the first is the one that was asked for.
      final results = tester.widget<SearchResultsScreen>(
        find.byType(SearchResultsScreen),
      );
      expect(results.categoryCid, 'dept-0');
      expect(results.query, isEmpty);
    });
  });

  group('staying current', () {
    testWidgets('pulling down asks the server again', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrowseScreen()));
      await tester.pumpAndSettle();

      final before = _treeRequests();

      await tester.fling(_catalogue, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(_treeRequests(), greaterThan(before));
    });
  });
}

/// The catalogue's own scroll view. Named because the screen holds more than
/// one scrollable and a bare byType finder would pick whichever came first.
final Finder _catalogue = find.descendant(
  of: find.byType(RefreshIndicator),
  matching: find.byType(SingleChildScrollView),
);

/// Every artwork panel belonging to a subcategory tile.
///
/// Filtered by URL rather than by position: the department banner is an
/// ArtworkPanel too, and it is not gated.
List<ArtworkPanel> _tilePanels(WidgetTester tester) => tester
    .widgetList<ArtworkPanel>(find.byType(ArtworkPanel))
    .where((panel) => panel.aspectRatio == 1)
    .toList();

List<String> _childImages(WidgetTester tester) =>
    _tilePanels(tester)
        .map((panel) => panel.imageUrl)
        .whereType<String>()
        .toList();

int _treeRequests() =>
    api.calls.where((c) => c.path == '/alibaba-categories').length;

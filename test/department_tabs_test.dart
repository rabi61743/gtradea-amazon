import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/catalog/presentation/catalog_visuals.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/department_tabs.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

late FakeApi api;

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

List<Category> _departments(int count) => [
  for (var i = 0; i < count; i++)
    Category(cid: 'cid-$i', name: 'Department $i', sortOrder: i),
];

/// Which tab the strip is showing as chosen, or null for "For You".
String? selectedName(WidgetTester tester) {
  final tabs = tester.widget<DepartmentTabs>(find.byType(DepartmentTabs));
  for (final category in tabs.categories) {
    if (category.cid == tabs.selectedCid) return category.name;
  }
  return null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CatalogStore.instance.resetForTest();
  });

  group('the strip', () {
    testWidgets('leads with For You, then the departments', (tester) async {
      // Somebody who has not decided yet should not have to pick a department
      // to see the storefront.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(4),
            selectedCid: null,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Department 0'), findsOneWidget);
      expect(find.text('Department 3'), findsOneWidget);
      // The glyphs come from the shared keyword map, so a department reads the
      // same here as it does in browse and in search. Five, not four: For You
      // has one too.
      expect(find.byType(Icon), findsNWidgets(5));
    });

    testWidgets('caps a forty-eight department catalogue', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(48),
            selectedCid: 'cid-0',
            onSelected: (_) {},
          ),
        ),
      );

      // Forty-eight is a horizontal scroll nobody finishes; the rest stay one
      // tap away in "Shop by category".
      expect(find.text('Department ${DepartmentTabs.maxItems}'), findsNothing);
      expect(find.text('Department 0'), findsOneWidget);
    });

    testWidgets('marks the chosen one as selected for a screen reader', (
      tester,
    ) async {
      _phone(tester);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(3),
            selectedCid: 'cid-1',
            onSelected: (_) {},
          ),
        ),
      );

      // Not colour and an underline alone: the state has to reach someone who
      // cannot see either.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Department 1')),
        isSemantics(isSelected: true, isButton: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Department 0')),
        isSemantics(isSelected: false, isButton: true),
      );

      handle.dispose();
    });

    testWidgets('For You is the selected tab when nothing else is', (
      tester,
    ) async {
      _phone(tester);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(3),
            selectedCid: null,
            onSelected: (_) {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('For You')),
        isSemantics(isSelected: true, isButton: true),
      );

      handle.dispose();
    });

    testWidgets('reports the tap', (tester) async {
      _phone(tester);
      Category? picked;
      var reported = false;

      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(4),
            selectedCid: null,
            onSelected: (c) {
              picked = c;
              reported = true;
            },
          ),
        ),
      );

      await tester.tap(find.text('Department 2'));
      await tester.pumpAndSettle();
      expect(picked?.cid, 'cid-2');

      // Null is a real answer here, not "nothing happened" -- it is how the
      // strip says For You.
      await tester.tap(find.text('For You'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);
      expect(picked, isNull);
    });

    testWidgets('keeps its height when the type is scaled up', (tester) async {
      // A height computed from a hardcoded font size clips the label at large
      // type, and this strip is above the fold on every page load.
      _phone(tester);
      for (final scale in [1.0, 1.8, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: DepartmentTabs(
                  categories: _departments(6),
                  selectedCid: 'cid-0',
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at ${scale}x');
      }
    });

    testWidgets('stays compact enough to leave the products visible', (
      tester,
    ) async {
      // The whole reason this replaced a two-line picker: it sits above the
      // fold on every load, so every point it takes is a point of storefront.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(6),
            selectedCid: 'cid-0',
            onSelected: (_) {},
          ),
        ),
      );

      expect(tester.getSize(find.byType(DepartmentTabs)).height, lessThan(90));
    });
  });

  group('the glyphs', () {
    test('the busiest departments do not collapse onto one icon', () {
      // Women, Men, Kidswear and Toys sit next to each other in the strip.
      // They used to resolve to two glyphs between them -- a hanger and a toy
      // car -- so four adjacent tabs read as two.
      final icons = {
        for (final name in ['Women', 'Men', 'Kidswear', 'Toys'])
          name: iconForCategory(name),
      };
      expect(icons.values.toSet(), hasLength(4), reason: '$icons');
    });

    test('a womens department is not given the mens icon', () {
      // "women" contains "men", so testing the shorter one first matches every
      // women's department in the catalogue.
      expect(iconForCategory('Women'), isNot(iconForCategory('Men')));
      expect(iconForCategory("Women's Sweaters"), iconForCategory('Women'));
    });

    test('an unrecognised department still gets something', () {
      expect(iconForCategory('Rubber and plastic'), isNotNull);
      expect(iconForCategory(null), isNotNull);
      expect(iconForCategory(''), isNotNull);
    });
  });

  group('on the home page', () {
    /// Taps a department tab, scrolling the strip to it first.
    ///
    /// The strip scrolls horizontally, so the later tabs are off-screen on any
    /// realistic window -- which is the point of it, and something a test
    /// should go through rather than around.
    Future<void> tapDepartment(WidgetTester tester, String name) async {
      final tab = find.descendant(
        of: find.byType(DepartmentTabs),
        matching: find.text(name),
      );
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
    }

    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 3400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();
    }

    testWidgets('sits directly under the search bar', (tester) async {
      // Not a block partway down the feed: it has to stay reachable however
      // far down the page the shopper is, which means outside the scroll view.
      await pumpHome(tester);

      expect(find.byType(DepartmentTabs), findsOneWidget);
      expect(find.text('For You'), findsOneWidget);
    });

    testWidgets('opens on For You, not on a department', (tester) async {
      await pumpHome(tester);
      expect(selectedName(tester), isNull);
      // The storefront, not one department's listing.
      expect(find.textContaining('Trending in'), findsNothing);
    });

    testWidgets('choosing a department lists that department', (tester) async {
      await pumpHome(tester);
      // Index 6 is past the five rails the For You feed builds, so nothing has
      // already fetched it -- picking one of the first five would be answered
      // from memory and prove nothing.
      final names = stubDepartmentNames(7);

      final before = api.calls
          .where((c) => c.path == '/feed/trending-products')
          .length;

      await tapDepartment(tester, names[6]);

      expect(selectedName(tester), names[6]);
      expect(find.text('Trending in ${names[6]}'), findsOneWidget);
      expect(
        api.calls.where((c) => c.path == '/feed/trending-products').length,
        greaterThan(before),
      );
    });

    testWidgets('and For You brings the storefront back', (tester) async {
      await pumpHome(tester);
      final names = stubDepartmentNames(3);

      await tapDepartment(tester, names[1]);
      expect(find.text('Trending in ${names[1]}'), findsOneWidget);

      await tapDepartment(tester, 'For You');

      expect(selectedName(tester), isNull);
      expect(find.textContaining('Trending in'), findsNothing);
      // The storefront's own blocks are back. Scrolled to, because the
      // recommendation rail sits below the banner and the flash sale.
      await tester.scrollUntilVisible(
        find.text('Recommended for you'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(HomeFeed),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Recommended for you'), findsWidgets);
    });

    testWidgets('going back to one already seen does not refetch it', (
      tester,
    ) async {
      // The rails are memoised per department by CatalogStore, which is what
      // makes flicking between two of them feel instant.
      await pumpHome(tester);
      final names = stubDepartmentNames(3);

      await tapDepartment(tester, names[1]);
      await tapDepartment(tester, names[0]);

      final settled = api.calls
          .where((c) => c.path == '/feed/trending-products')
          .length;

      await tapDepartment(tester, names[1]);

      expect(
        api.calls.where((c) => c.path == '/feed/trending-products').length,
        settled,
        reason: 'nothing was re-fetched',
      );
    });

    testWidgets('a department with nothing trending says so', (tester) async {
      api.on('GET', '/feed/trending-products', body: const []);
      await pumpHome(tester);

      await tapDepartment(tester, stubDepartmentNames(2)[1]);

      expect(find.textContaining('Nothing trending in'), findsOneWidget);
      // Not a dead end: nothing trending is not the same as nothing in it.
      expect(find.textContaining('See everything in'), findsOneWidget);
    });
  });
}

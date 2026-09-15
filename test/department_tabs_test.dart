import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/catalog/presentation/catalog_visuals.dart';
import 'package:gtradea_amazon/features/for_you/presentation/new_for_you_screen.dart';
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

  group('the active shadow travels', () {
    /// Where the one selection mark is, and how many there are.
    ///
    /// It was a hard drop shadow while the strip lived on the header's teal
    /// band. The strip is its own light section now, where that read as a grey
    /// slab, so the mark is a wash of the active colour instead -- which is
    /// what this looks for.
    List<Rect> shadows(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .toList(growable: false)
        .asMap()
        .entries
        .where((entry) {
          final decoration = entry.value.decoration;
          return decoration is BoxDecoration &&
              decoration.color ==
                  AppColors.commerceOrange.withValues(alpha: 0.10);
        })
        .map((entry) => tester.getRect(find.byType(DecoratedBox).at(entry.key)))
        .toList(growable: false);

    Future<void> strip(
      WidgetTester tester, {
      String? selected,
      required ValueChanged<Category?> onSelected,
    }) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(4),
            selectedCid: selected,
            onSelected: onSelected,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('there is exactly one, wherever the selection is', (
      tester,
    ) async {
      // It used to be wrapped around the first tab, so "For You" wore it even
      // when a department was chosen -- two tabs claiming to be current.
      await strip(tester, onSelected: (_) {});
      expect(shadows(tester), hasLength(1));

      await strip(tester, selected: 'cid-2', onSelected: (_) {});
      expect(shadows(tester), hasLength(1));
    });

    testWidgets('it starts under For You', (tester) async {
      await strip(tester, onSelected: (_) {});

      final tab = tester.getRect(find.text('For You'));
      final shadow = shadows(tester).single;

      expect(shadow.left, lessThanOrEqualTo(tab.left));
      expect(shadow.right, greaterThanOrEqualTo(tab.right));
    });

    testWidgets('and lands under whichever department is chosen', (
      tester,
    ) async {
      await strip(tester, selected: 'cid-1', onSelected: (_) {});

      final tab = tester.getRect(find.text('Department 1'));
      final shadow = shadows(tester).single;

      expect(shadow.left, lessThanOrEqualTo(tab.left));
      expect(shadow.right, greaterThanOrEqualTo(tab.right));
    });

    testWidgets('it slides rather than jumping', (tester) async {
      // Halfway through the change it should be between the two tabs, not
      // already arrived and not still where it started.
      await strip(tester, onSelected: (_) {});
      final from = shadows(tester).single.left;

      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(4),
            selectedCid: 'cid-2',
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));

      final midway = shadows(tester).single.left;
      await tester.pumpAndSettle();
      final to = shadows(tester).single.left;

      expect(midway, greaterThan(from), reason: 'it has left the old tab');
      expect(midway, lessThan(to), reason: 'and has not arrived yet');
    });

    testWidgets('the tabs still do their job', (tester) async {
      // The shadow moved out of the tab; the tap must not have moved with it.
      Category? picked;
      var forYou = 0;
      await strip(
        tester,
        selected: 'cid-1',
        onSelected: (category) {
          picked = category;
          if (category == null) forYou++;
        },
      );

      await tester.tap(find.text('Department 3'));
      await tester.pump();
      expect(picked?.cid, 'cid-3');

      await tester.tap(find.text('For You'));
      await tester.pump();
      expect(forYou, 1);
    });

    testWidgets('a department off the strip is marked by nothing', (
      tester,
    ) async {
      // Chosen from "Shop by category" rather than here: there is no tab to
      // sit under, and a shadow parked at the left edge would claim For You.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: _departments(4),
            selectedCid: 'cid-off-strip',
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(shadows(tester), isEmpty);
    });
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

  group('the New for You tab', () {
    List<Category> named(List<String> names) => [
      for (var i = 0; i < names.length; i++)
        Category(cid: 'cid-$i', name: names[i], sortOrder: i),
    ];

    /// The one selection mark, as the shadow group finds it.
    List<Rect> shadows(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .toList(growable: false)
        .asMap()
        .entries
        .where((entry) {
          final decoration = entry.value.decoration;
          return decoration is BoxDecoration &&
              decoration.color ==
                  AppColors.commerceOrange.withValues(alpha: 0.10);
        })
        .map((entry) => tester.getRect(find.byType(DecoratedBox).at(entry.key)))
        .toList(growable: false);

    Future<void> strip(
      WidgetTester tester, {
      List<String> names = const ['Women', 'Men', 'Kidswear'],
      String? selected,
      VoidCallback? onNewForYou,
    }) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: named(names),
            selectedCid: selected,
            onSelected: (_) {},
            onNewForYou: onNewForYou,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    double xOf(WidgetTester tester, String label) =>
        tester.getRect(find.text(label)).center.dx;

    testWidgets('sits immediately after Men, displacing nothing', (
      tester,
    ) async {
      await strip(tester, onNewForYou: () {});

      // Ordered by where they actually are, not by the index they were built
      // from: the point of the feature is the position on screen.
      expect(xOf(tester, 'For You'), lessThan(xOf(tester, 'Women')));
      expect(xOf(tester, 'Women'), lessThan(xOf(tester, 'Men')));
      expect(xOf(tester, 'Men'), lessThan(xOf(tester, 'New for You')));
      expect(xOf(tester, 'New for You'), lessThan(xOf(tester, 'Kidswear')));
    });

    testWidgets('is found by name, so a reordered catalogue still fits it', (
      tester,
    ) async {
      // The strip is the server's list in the server's order. Pinned to a
      // number, this would follow whatever happened to be third.
      await strip(
        tester,
        names: ['Toys', 'Kidswear', 'Men', 'Women'],
        onNewForYou: () {},
      );

      expect(xOf(tester, 'Men'), lessThan(xOf(tester, 'New for You')));
      expect(xOf(tester, 'New for You'), lessThan(xOf(tester, 'Women')));
    });

    testWidgets('goes last when there is no Men to follow', (tester) async {
      // The one position that cannot push a department out of its place.
      await strip(tester, names: ['Women', 'Toys'], onNewForYou: () {});

      expect(find.text('New for You'), findsOneWidget);
      expect(xOf(tester, 'Toys'), lessThan(xOf(tester, 'New for You')));
    });

    testWidgets('is left out entirely when there is nowhere to send anyone', (
      tester,
    ) async {
      // Rather than drawn dead. A tab that looks like the others and does
      // nothing is worse than no tab.
      await strip(tester);

      expect(find.text('New for You'), findsNothing);
      expect(find.text('Men'), findsOneWidget);
    });

    testWidgets('reports the tap', (tester) async {
      var opened = 0;
      await strip(tester, onNewForYou: () => opened++);

      await tester.tap(find.text('New for You'));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('never draws as selected, because it is not a filter', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await strip(tester, onNewForYou: () {});

      expect(
        tester.getSemantics(find.bySemanticsLabel('New for You')),
        isSemantics(isSelected: false, isButton: true),
      );

      handle.dispose();
    });

    testWidgets('and a department past it still gets the mark', (tester) async {
      // The off-by-one this feature could most easily introduce: inserting a
      // tab shifts every slot after it, and the selection shadow is positioned
      // by slot. Kidswear sits past the inserted tab, so if the arithmetic
      // slipped the wash would sit under its neighbour instead.
      await strip(tester, selected: 'cid-2', onNewForYou: () {});

      final tab = tester.getRect(find.text('Kidswear'));
      final shadow = shadows(tester).single;

      expect(shadow.left, lessThanOrEqualTo(tab.left));
      expect(shadow.right, greaterThanOrEqualTo(tab.right));
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

    testWidgets('the New for You tab opens the personalised feed', (
      tester,
    ) async {
      await pumpHome(tester);

      // Scoped to the strip: the bottom bar carries the same words, and an
      // unscoped finder would match two widgets and tap whichever came first.
      final tab = find.descendant(
        of: find.byType(DepartmentTabs),
        matching: find.text('New for You'),
      );
      expect(tab, findsOneWidget);

      // After Men on the real catalogue, not only on a fixture.
      final men = find.descendant(
        of: find.byType(DepartmentTabs),
        matching: find.text('Men'),
      );
      expect(
        tester.getRect(tab).center.dx,
        greaterThan(tester.getRect(men).center.dx),
      );

      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();

      // The screen the bottom bar's second slot opens -- one destination, not
      // a second copy of the feed.
      expect(find.byType(NewForYouScreen), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/subcategory_grid.dart';
import 'package:gtradea_amazon/features/catalog/presentation/category_screen.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// The department, and the four of its children the block shows. Real cids and
/// the names production gives them today.
/// The line under the heading. Unique on the page, unlike the department name,
/// which is also a tab in the header strip and a tile in "Shop by category" --
/// so this is what the tests anchor on.
const _subtitle = 'Components and modules by category.';

const _parent = '57';
const _wanted = {
  '10235': 'Antenna',
  '202058705': 'Audio Devices',
  '127676048': 'Capacitor',
  '200804003': 'Diode',
};

/// Children the tree also returns, sorted in among the wanted ones -- so a
/// "first four" implementation would pick the wrong set and this would catch it.
const _alsoThere = {
  '1033273': 'Cabling Products',
  '202059412': 'Circuit Board',
  '10343': 'connection equipment',
};

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 12000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Scoped to the feed. Every one of these department names is also a label in
/// the tab strip pinned to the header, so a bare text finder matches twice and
/// the tap or the scroll is ambiguous.
Finder _inFeed(Finder target) =>
    find.descendant(of: find.byType(HomeFeed), matching: target);

Finder _homeScroll() => find
    .descendant(of: find.byType(HomeFeed), matching: find.byType(Scrollable))
    .first;

/// A catalogue with the electronics department and [children] under it.
FakeApi _tree({
  Map<String, String> children = const {..._wanted, ..._alsoThere},
  String departmentName = 'Electronic components',
}) {
  final stub = stubCatalog();
  stub.onCall('GET', '/alibaba-categories', (call) {
    if (call.query['parent_cid'] == 'null') {
      return reply([
        {
          'cid': _parent,
          'parent_cid': null,
          'name': departmentName,
          'image_url': 'https://example.invalid/$_parent.jpg',
          'sort_order': 0,
        },
      ]);
    }
    // Alphabetical, as production returns them.
    final sorted = children.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return reply([
      for (final (i, entry) in sorted.indexed)
        {
          'cid': entry.key,
          'parent_cid': _parent,
          'name': entry.value,
          'image_url': 'https://cdn.invalid/${entry.key}.jpg',
          'sort_order': i,
        },
    ]);
  });
  return stub;
}

Future<SubcategoryGrid> _openTo(WidgetTester tester) async {
  await tester.pumpWidget(const GtradeaAmazonApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    _inFeed(find.text(_subtitle)),
    400,
    scrollable: _homeScroll(),
  );
  await tester.pumpAndSettle();

  return tester.widget<SubcategoryGrid>(
    find
        .ancestor(
          of: find.text(_subtitle),
          matching: find.byType(SubcategoryGrid),
        )
        .first,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.resetForTest();
  });

  testWidgets('shows the four named, not the first four alphabetically', (
    tester,
  ) async {
    // The tree sorts children alphabetically and these four are the 1st, 2nd,
    // 4th and 11th of about thirty, so "take(4)" gives Antenna, Audio Devices,
    // Cabling Products and Capacitor -- three right and one wrong.
    _tall(tester);
    useStubbedApi(_tree());

    final grid = await _openTo(tester);

    expect(grid.children.map((c) => c.name), _wanted.values);
    // Asserted on the grid's own children rather than on the page: the same
    // department also gets a Browse section further down, and that one does
    // show its first four -- Cabling Products among them.
    expect(grid.children.map((c) => c.cid), _wanted.keys);
  });

  testWidgets('every tile is drawn from the backend row', (tester) async {
    // Name, picture and destination all off the category the tree returned.
    // Nothing about a tile is typed into the app.
    _tall(tester);
    useStubbedApi(_tree());

    final grid = await _openTo(tester);

    for (final child in grid.children) {
      expect(_wanted.containsKey(child.cid), isTrue, reason: child.cid);
      expect(child.name, _wanted[child.cid]);
      expect(child.imageUrl, 'https://cdn.invalid/${child.cid}.jpg');
    }
  });

  testWidgets('the heading is the department name the server sent', (
    tester,
  ) async {
    _tall(tester);
    useStubbedApi(_tree(departmentName: 'Renamed in the backoffice'));

    final grid = await _openTo(tester);

    expect(grid.actionLabel, 'Shop more');
    // The heading follows the backoffice. Nothing in the app types this name.
    expect(grid.title, 'Renamed in the backoffice');
  });

  testWidgets('a tile opens that category, not a product list', (tester) async {
    // Category -> subcategory -> products. Each of these four holds a level of
    // its own in the catalogue -- Antenna six, Capacitor twelve -- and going
    // straight to a listing threw that level away.
    _tall(tester);
    useStubbedApi(_tree());

    await _openTo(tester);
    await tester.tap(_inFeed(find.text('Capacitor')).first);
    await tester.pumpAndSettle();

    expect(find.byType(SearchResultsScreen), findsNothing);
    final screen = tester.widget<CategoryScreen>(find.byType(CategoryScreen));
    expect(screen.category.cid, '127676048');
    expect(screen.category.name, 'Capacitor');
  });

  testWidgets('sits directly below the fashion block', (tester) async {
    _tall(tester);
    // Both blocks need their departments present, so this tree carries the
    // fashion cids as well.
    final stub = stubCatalog();
    stub.onCall('GET', '/alibaba-categories', (call) {
      if (call.query['parent_cid'] == 'null') {
        return reply([
          for (final (i, cid) in ['10166', '97', _parent].indexed)
            {
              'cid': cid,
              'parent_cid': null,
              'name': cid == _parent ? 'Electronic components' : 'Dept $cid',
              'image_url': 'https://example.invalid/$cid.jpg',
              'sort_order': i,
            },
        ]);
      }
      return reply([
        for (final entry in _wanted.entries)
          {
            'cid': entry.key,
            'parent_cid': _parent,
            'name': entry.value,
            'image_url': 'https://cdn.invalid/${entry.key}.jpg',
            'sort_order': 0,
          },
      ]);
    });
    useStubbedApi(stub);

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    final fashion = tester
        .getRect(_inFeed(find.text('Fashion favourites')))
        .top;
    final electronics = tester
        .getRect(_inFeed(find.text('Electronic components')).first)
        .top;
    expect(electronics, greaterThan(fashion));
  });

  testWidgets('a department missing them draws nothing', (tester) async {
    _tall(tester);
    useStubbedApi(_tree(children: _alsoThere));

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    // No section, though the name still appears as a tab and as an index tile.
    expect(_inFeed(find.text(_subtitle)), findsNothing);
  });
}

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

/// The line under the heading. Unique on the page, unlike the department name,
/// which is also a tab in the header strip and a tile in "Shop by category" --
/// so this is what the tests anchor on.
const _subtitle = 'Kitchen, laundry and living.';

const _parent = '6';

/// The department, and the four of its children the block shows. Real cids and
/// the names production gives them today.
const _wanted = {
  '653': 'Kitchen Appliance',
  '652': 'Living appliances',
  '1047393': 'Big appliances',
  '1047981': 'Two seasons appliances',
};

/// Children the tree also returns, sorted in among the wanted ones -- so a
/// "first four" implementation would pick the wrong set and this would catch
/// it. Two of these are the ones production rules out: Audio-visual appliances
/// has no products under it, and Smart Home System has no subcategories.
const _alsoThere = {
  '1047104': 'Audio-visual appliances',
  '125012004': 'Smart Home System',
  '1047893': 'Health appliances',
};

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 20000);
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

/// A catalogue with the appliances department and [children] under it.
FakeApi _tree({
  Map<String, String> children = const {..._wanted, ..._alsoThere},
  String departmentName = 'Home appliance',
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
    // Sorted alphabetically the tree leads with Audio-visual appliances and Big
    // appliances, so "take(4)" would put back one of the two children this
    // block deliberately leaves out.
    _tall(tester);
    useStubbedApi(_tree());

    final grid = await _openTo(tester);

    expect(grid.children.map((c) => c.name), _wanted.values);
    expect(grid.children.map((c) => c.cid), _wanted.keys);
  });

  testWidgets('the two production rules out never appear', (tester) async {
    // Audio-visual appliances returns no products at all from the category
    // endpoint, and Smart Home System is a leaf -- a tile for it would open a
    // category page with no level under it. Both are in the stubbed tree, so
    // this fails the moment either is picked up.
    _tall(tester);
    useStubbedApi(_tree());

    final grid = await _openTo(tester);

    expect(grid.children.map((c) => c.cid), isNot(contains('1047104')));
    expect(grid.children.map((c) => c.cid), isNot(contains('125012004')));
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
    // It reads "Home appliance" today. If the backoffice renames cid 6 to
    // "Home Appliances" the heading follows on its own -- which is the whole
    // reason it is not typed here.
    _tall(tester);
    useStubbedApi(_tree(departmentName: 'Renamed in the backoffice'));

    final grid = await _openTo(tester);

    expect(grid.actionLabel, 'Shop more');
    expect(grid.title, 'Renamed in the backoffice');
  });

  testWidgets('a tile opens that category, not a product list', (tester) async {
    // Category -> subcategory -> products. Each of these four holds a level of
    // its own -- Kitchen Appliance seventy-three subcategories, Two seasons
    // thirty-one -- and going straight to a listing would throw that away.
    _tall(tester);
    useStubbedApi(_tree());

    await _openTo(tester);
    await tester.tap(_inFeed(find.text('Kitchen Appliance')).first);
    await tester.pumpAndSettle();

    expect(find.byType(SearchResultsScreen), findsNothing);
    final screen = tester.widget<CategoryScreen>(find.byType(CategoryScreen));
    expect(screen.category.cid, '653');
    expect(screen.category.name, 'Kitchen Appliance');
  });

  testWidgets('sits directly below the sports block', (tester) async {
    // The placement the request is actually about. Both blocks need their
    // departments present, so this tree carries the sports cids as well.
    _tall(tester);
    const sportsParent = '18';
    const sportsChildren = {
      '281904': 'Mountain, Camping Supplies',
      '1048070': 'Outdoor Clothing',
      '2040': 'Sport Protective Gear',
      '1044819': 'Badminton and tennis equipment',
    };

    final stub = stubCatalog();
    stub.onCall('GET', '/alibaba-categories', (call) {
      if (call.query['parent_cid'] == 'null') {
        return reply([
          // Sports first in the tree as well as on the page, so this cannot
          // pass by accident on a page that simply mirrors catalogue order.
          for (final (i, cid) in [sportsParent, _parent].indexed)
            {
              'cid': cid,
              'parent_cid': null,
              'name': cid == _parent ? 'Home appliance' : 'Sports Outdoors',
              'image_url': 'https://example.invalid/$cid.jpg',
              'sort_order': i,
            },
        ]);
      }
      return reply([
        for (final entry in {..._wanted, ...sportsChildren}.entries)
          {
            'cid': entry.key,
            'parent_cid': _wanted.containsKey(entry.key)
                ? _parent
                : sportsParent,
            'name': entry.value,
            'image_url': 'https://cdn.invalid/${entry.key}.jpg',
            'sort_order': 0,
          },
      ]);
    });
    useStubbedApi(stub);

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    // Anchored on each block's subtitle rather than its heading: the department
    // names are also tabs and index tiles, and the subtitles are not.
    final sports = tester
        .getRect(_inFeed(find.text('Camping, training and match-day kit.')))
        .top;
    final appliances = tester.getRect(_inFeed(find.text(_subtitle))).top;

    expect(appliances, greaterThan(sports));

    // And *directly* below, which is the part "below" alone does not say. The
    // generic Browse sections follow the curated blocks, so the new one landing
    // above them is what places it in the curated run rather than at the foot
    // of the page.
    final firstBrowse = _inFeed(find.textContaining('Browse '));
    expect(firstBrowse, findsWidgets);
    expect(appliances, lessThan(tester.getRect(firstBrowse.first).top));
  });

  testWidgets('a department missing them draws nothing', (tester) async {
    _tall(tester);
    useStubbedApi(_tree(children: _alsoThere));

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    // No section, though the name still appears as a tab and as an index tile.
    expect(_inFeed(find.text(_subtitle)), findsNothing);
  });

  testWidgets('and a catalogue without the department draws nothing', (
    tester,
  ) async {
    // The guard that matters if cid 6 is ever deactivated in the backoffice:
    // an absent department is a missing section, not a broken one.
    _tall(tester);
    useStubbedApi(stubCatalog());

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    expect(_inFeed(find.text(_subtitle)), findsNothing);
  });
}

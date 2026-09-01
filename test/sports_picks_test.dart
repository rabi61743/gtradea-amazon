import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/catalog/presentation/category_screen.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/department_grid.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// The line under the heading. Unique on the page, unlike the department name,
/// which is also a tab in the header strip and a tile in "Shop by category".
const _subtitle = 'Camping, training and match-day kit.';

const _parent = '18';
const _wanted = {
  '281904': 'Mountain, Camping Supplies',
  '1048070': 'Outdoor Clothing',
  '2040': 'Sport Protective Gear',
  '1044819': 'Badminton and tennis equipment',
};

/// Children the tree also returns, ahead of the wanted ones in its own order --
/// so a "first four" implementation would pick these, and this would catch it.
const _alsoThere = {
  '1044658': 'Fishing Supplies',
  '2009': 'Fitness Equipment Supplies',
  '1048023': 'Swimming supplies',
};

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 14000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Finder _inFeed(Finder target) =>
    find.descendant(of: find.byType(HomeFeed), matching: target);

Finder _homeScroll() => find
    .descendant(of: find.byType(HomeFeed), matching: find.byType(Scrollable))
    .first;

FakeApi _tree({
  Map<String, String> children = const {..._alsoThere, ..._wanted},
  String departmentName = 'Sports Outdoors',
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
    return reply([
      for (final (i, entry) in children.entries.indexed)
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

Future<DepartmentGrid> _openTo(WidgetTester tester) async {
  await tester.pumpWidget(const GtradeaAmazonApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    _inFeed(find.text(_subtitle)),
    400,
    scrollable: _homeScroll(),
  );
  await tester.pumpAndSettle();

  return tester.widget<DepartmentGrid>(
    find
        .ancestor(
          of: find.text(_subtitle),
          matching: find.byType(DepartmentGrid),
        )
        .first,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.resetForTest();
  });

  testWidgets('shows the four chosen, not the first four the tree returns', (
    tester,
  ) async {
    _tall(tester);
    useStubbedApi(_tree());

    final grid = await _openTo(tester);

    expect(grid.entries.map((e) => e.label), _wanted.values);
    expect(
      grid.entries.map((e) => e.label),
      isNot(contains('Fishing Supplies')),
    );
  });

  testWidgets('every tile is drawn from the backend row', (tester) async {
    _tall(tester);
    useStubbedApi(_tree());

    final grid = await _openTo(tester);

    for (final entry in grid.entries) {
      expect(_wanted.containsValue(entry.label), isTrue, reason: entry.label);
      final cid = _wanted.entries.firstWhere((e) => e.value == entry.label).key;
      expect(entry.imageUrl, 'https://cdn.invalid/$cid.jpg');
    }
  });

  testWidgets('the heading is the department name the server sent', (
    tester,
  ) async {
    _tall(tester);
    useStubbedApi(_tree(departmentName: 'Renamed in the backoffice'));

    final grid = await _openTo(tester);

    expect(grid.title, 'Renamed in the backoffice');
    expect(grid.actionLabel, 'Shop more');
  });

  testWidgets('it is drawn differently from the two blocks above it', (
    tester,
  ) async {
    // Three identical grids down one page is a page that stops being read. This
    // one puts the name under the picture rather than across it, which also
    // suits names that run to "Badminton and tennis equipment".
    _tall(tester);
    useStubbedApi(_tree());

    final grid = await _openTo(tester);
    expect(grid.columns, 2);
  });

  testWidgets('a tile opens that category rather than a product list', (
    tester,
  ) async {
    _tall(tester);
    useStubbedApi(_tree());

    await _openTo(tester);
    await tester.tap(_inFeed(find.text('Outdoor Clothing')).first);
    await tester.pumpAndSettle();

    final screen = tester.widget<CategoryScreen>(find.byType(CategoryScreen));
    expect(screen.category.cid, '1048070');
    expect(screen.category.name, 'Outdoor Clothing');
  });

  testWidgets('a catalogue without them draws nothing', (tester) async {
    _tall(tester);
    useStubbedApi(_tree(children: _alsoThere));

    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    expect(_inFeed(find.text(_subtitle)), findsNothing);
  });
}

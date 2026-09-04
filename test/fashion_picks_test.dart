import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/subcategory_grid.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// The four real cids the curated block is keyed on, with the names production
/// gives them today.
const _picks = {
  '10166': 'Women',
  '10165': 'Men',
  '1042954': 'Bags & Leather',
  '97': 'Beauty Skincare/Makeup',
};

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 4400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Finder _homeScroll() => find
    .descendant(of: find.byType(HomeFeed), matching: find.byType(Scrollable))
    .first;

/// A catalogue whose top level is exactly [cids], named by [nameOf].
FakeApi _treeOf(Iterable<String> cids, {String Function(String)? nameOf}) {
  final stub = stubCatalog();
  stub.onCall('GET', '/alibaba-categories', (call) {
    if (call.query['parent_cid'] == 'null') {
      return reply([
        for (final (i, cid) in cids.indexed)
          {
            'cid': cid,
            'parent_cid': null,
            'name': nameOf?.call(cid) ?? _picks[cid] ?? 'Department $i',
            'image_url': 'https://example.invalid/$cid.jpg',
            'sort_order': i,
          },
      ]);
    }
    return reply([
      for (final cid in cids)
        for (var c = 0; c < 4; c++)
          {
            'cid': '$cid-child-$c',
            'parent_cid': cid,
            'name': '$cid child $c',
            'sort_order': c,
          },
    ]);
  });
  return stub;
}

Future<void> _openHome(WidgetTester tester, FakeApi stub) async {
  _tall(tester);
  useStubbedApi(stub);
  await tester.pumpWidget(const GtradeaAmazonApp());
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 400, scrollable: _homeScroll());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.resetForTest();
  });

  testWidgets('sits under the sale and above the browse sections', (
    tester,
  ) async {
    // Tall enough to build the sale, the picks and the first Browse section at
    // once. Scrolling to the picks would unbuild the sale above them, and a
    // finder cannot measure a widget the list has already thrown away.
    tester.view.physicalSize = const Size(1100, 20000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    useStubbedApi(_treeOf(_picks.keys));
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    final edit = tester.getRect(find.text('Fashion favourites')).top;
    // The countdown card, which is all that is left of the sale on this page:
    // the "Dashain Specials" panel that used to sit under it is gone.
    final sale = tester.getRect(find.text('Flash Sales')).top;
    final browse = tester.getRect(find.textContaining('Browse ').first).top;

    expect(edit, greaterThan(sale));
    expect(edit, lessThan(browse));
  });

  testWidgets('shows the four it names, two across, with Shop more', (
    tester,
  ) async {
    await _openHome(tester, _treeOf(_picks.keys));
    await _scrollTo(tester, find.text('Fashion favourites'));

    final grid = tester.widget<SubcategoryGrid>(
      find
          .ancestor(
            of: find.text('Fashion favourites'),
            matching: find.byType(SubcategoryGrid),
          )
          .first,
    );

    // Two across, not the index's three: four tiles meant to be looked at.
    expect(SubcategoryGrid.columns, 2);
    expect(grid.actionLabel, 'Shop more');
    expect(grid.children.map((c) => c.name), _picks.values);
  });

  testWidgets('names them from the tree rather than from the code', (
    tester,
  ) async {
    // The cids are the key; the names beside them in the source say which is
    // which. What is drawn is whatever the backoffice calls them today, so a
    // rename shows up instead of being papered over.
    await _openHome(
      tester,
      _treeOf(_picks.keys, nameOf: (cid) => 'Renamed $cid'),
    );
    await _scrollTo(tester, find.text('Fashion favourites'));

    expect(find.text('Renamed 10166'), findsWidgets);
    expect(find.text('Women'), findsNothing);
  });

  testWidgets('a catalogue without them draws nothing', (tester) async {
    // Two tiles is the floor. A "picks" block showing one thing is not a
    // selection, and a half-empty grid reads as a section that failed to load.
    await _openHome(tester, _treeOf(['other-1', 'other-2', 'other-3']));

    expect(find.text('Fashion favourites'), findsNothing);
  });

  testWidgets('a catalogue with only two of them still shows', (tester) async {
    await _openHome(tester, _treeOf(['10166', '97', 'other-1']));
    await _scrollTo(tester, find.text('Fashion favourites'));

    final grid = tester.widget<SubcategoryGrid>(
      find
          .ancestor(
            of: find.text('Fashion favourites'),
            matching: find.byType(SubcategoryGrid),
          )
          .first,
    );
    expect(grid.children.map((c) => c.name), [
      'Women',
      'Beauty Skincare/Makeup',
    ]);
  });
}

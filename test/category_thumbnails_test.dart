import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/data/category_thumbnails.dart';
import 'package:gtradea_amazon/features/home/widgets/subcategory_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// Level-3 electronics categories as production returns them: a real name, and
/// no artwork at all.
Category _bare(String cid, String name) => Category(cid: cid, name: name);

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _grid(List<Category> children, {bool fill = true}) => _wrap(
  SubcategoryGrid(
    children: children,
    shown: children.length,
    fillMissingImages: fill,
    onSelected: (_) {},
  ),
);

/// Every keyword the app has searched, in order.
List<Object?> _searched() => api.calls
    .where((c) => c.path.contains('/api/1688/search'))
    .map((c) => c.query['q'])
    .toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CategoryThumbnails.instance.resetForTest();
  });

  testWidgets('a category with no picture gets one, matched by its name', (
    tester,
  ) async {
    // The catalogue has no `image_url` on any of Antenna's six children, and
    // between them they hold one product -- so there is nothing to borrow from
    // the category itself. The keyword search does rank properly: "TV antenna"
    // returns a TV antenna.
    api.on('GET', '/api/1688/search', body: {'items': feedRows(3)});

    await tester.pumpWidget(_grid([_bare('1035221', 'TV antenna')]));
    await tester.pumpAndSettle();

    expect(_searched(), ['TV antenna']);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a category that has its own picture is left alone', (
    tester,
  ) async {
    // The point is to fill gaps, never to override what the catalogue provides.
    await tester.pumpWidget(
      _grid([
        const Category(
          cid: 'own',
          name: 'Hanfu',
          imageUrl: 'https://example.invalid/hanfu.jpg',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_searched(), isEmpty);
  });

  testWidgets('off by default, so the home page asks for nothing', (
    tester,
  ) async {
    // Every tile on the home page comes from the department tree, where the
    // artwork is complete. Searching there would be a request per tile for
    // nothing.
    await tester.pumpWidget(_grid([_bare('a', 'Antenna kind')], fill: false));
    await tester.pumpAndSettle();

    expect(_searched(), isEmpty);
  });

  testWidgets('one request per category, however often the grid rebuilds', (
    tester,
  ) async {
    api.on('GET', '/api/1688/search', body: {'items': feedRows(2)});

    final children = [
      _bare('c1', 'ceramic capacitor'),
      _bare('c2', 'Zener Diode'),
    ];

    await tester.pumpWidget(_grid(children));
    await tester.pumpAndSettle();
    // Rebuilt with the same categories -- a scroll, a setState above it.
    await tester.pumpWidget(_grid(children));
    await tester.pumpAndSettle();

    expect(_searched(), ['ceramic capacitor', 'Zener Diode']);
  });

  testWidgets('and nothing found is remembered, not retried forever', (
    tester,
  ) async {
    stubSearch(api, const []);
    api.on('GET', '/api/1688/search', body: {'items': const []});

    await tester.pumpWidget(_grid([_bare('x', 'Other Diodes')]));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_grid([_bare('x', 'Other Diodes')]));
    await tester.pumpAndSettle();

    expect(_searched(), ['Other Diodes'], reason: 'asked once');
    // And the tile is the designed panel rather than a broken image.
    expect(find.byType(Image), findsNothing);
    expect(find.text('Other Diodes'), findsOneWidget);
  });

  testWidgets('a failed search leaves the tile drawn, not broken', (
    tester,
  ) async {
    // A thumbnail is decoration. A category that cannot get one still lists its
    // name and still opens.
    api.on(
      'GET',
      '/api/1688/search',
      status: 500,
      body: {'error': 'search is down'},
    );

    await tester.pumpWidget(_grid([_bare('y', 'PIN Diode')]));
    await tester.pumpAndSettle();

    expect(find.text('PIN Diode'), findsOneWidget);
    expect(find.text('search is down'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the service hands back a category own image without asking', () async {
    final url = await CategoryThumbnails.instance.forCategory(
      const Category(cid: 'z', name: 'Hanfu', imageUrl: 'https://a/b.jpg'),
    );

    expect(url, 'https://a/b.jpg');
    expect(api.calls, isEmpty);
  });
}

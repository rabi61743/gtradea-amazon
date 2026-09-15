import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart'
    show Category;
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/catalog/presentation/browse_screen.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/department_grid.dart';
import 'package:gtradea_amazon/features/home/widgets/product_carousel.dart';
import 'package:gtradea_amazon/features/home/widgets/subcategory_grid.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:gtradea_amazon/shared/widgets/section_header.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// A window tall enough to build the whole feed, as `widget_test.dart` uses.
void _tall(WidgetTester tester) {
  // Taller than it was: the promotional block grew by about 1200dp of
  // banners, and everything this file checks lives below it.
  tester.view.physicalSize = const Size(1100, 16000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Finder homeScroll() => find
    .descendant(of: find.byType(HomeFeed), matching: find.byType(Scrollable))
    .first;

Widget _wrap(Widget child, {double scale = 1.0}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Product _product(int i) =>
    Product(numIid: 'p$i', title: 'Product $i', displayPrice: 1000 + i);

Category _child(int i) => Category(
  cid: 'child-$i',
  name: 'Subcategory $i',
  parentCid: 'dept',
  imageUrl: 'https://example.invalid/child-$i.jpg',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.resetForTest();
    api = stubCatalog();
  });

  group('the product rail', () {
    testWidgets('reserves exactly what the card needs, at any text scale', (
      tester,
    ) async {
      // The rail used to reserve `268 * textScale.clamp(1.0, 1.5)` -- a guessed
      // constant, which is the bug this codebase has already corrected three
      // times. It asks the card now, so the two cannot drift.
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = const Size(900, 3000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _wrap(
            ProductCarousel(
              title: 'Recommended for you',
              products: [for (var i = 0; i < 4; i++) _product(i)],
            ),
            scale: scale,
          ),
        );
        await tester.pump();

        final rail = tester.getSize(
          find
              .ancestor(
                of: find.byType(ProductResultCard).first,
                matching: find.byType(SizedBox),
              )
              .last,
        );
        final card = tester.getSize(find.byType(ProductResultCard).first);

        expect(
          card.height,
          lessThanOrEqualTo(rail.height),
          reason: 'at $scale',
        );
        expect(tester.takeException(), isNull, reason: 'at $scale');
      }
    });

    testWidgets('uses the same card as the rest of the app', (tester) async {
      // Not a card of its own with a five-star row on it. This catalogue
      // publishes no ratings, so those stars were blank on every card ever
      // rendered -- and a second card meant a second price colour on the page.
      await tester.pumpWidget(
        _wrap(
          ProductCarousel(
            title: 'Recommended for you',
            products: [for (var i = 0; i < 4; i++) _product(i)],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ProductResultCard), findsNWidgets(4));
      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
    });
  });

  group('the browse section', () {
    testWidgets('shows the real names and pictures from the tree', (
      tester,
    ) async {
      // The names and the images come from `/alibaba-categories`, fetched with
      // the department tree. Nothing here invents a shortcut, so this asserts
      // on what the stub served rather than on anything the widget made up.
      await tester.pumpWidget(
        _wrap(
          SubcategoryGrid(
            children: [for (var i = 0; i < 4; i++) _child(i)],
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Subcategory 0'), findsOneWidget);
      expect(find.text('Subcategory 3'), findsOneWidget);

      // The provider is wrapped in a ResizeImage -- the panel decodes at the
      // size it will draw -- so this reads through the wrapper rather than
      // casting to NetworkImage and finding out the hard way.
      final providers = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .map((p) => p is ResizeImage ? p.imageProvider : p)
          .whereType<NetworkImage>()
          .map((n) => n.url);
      expect(providers, contains('https://example.invalid/child-0.jpg'));
    });

    testWidgets('fits its measured height at any text scale', (tester) async {
      for (final scale in [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(
          _wrap(
            SubcategoryGrid(
              children: [for (var i = 0; i < 6; i++) _child(i)],
              onSelected: (_) {},
            ),
            scale: scale,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'at $scale');
      }
    });

    testWidgets('shows four however long the tree is', (tester) async {
      // A department has about forty children. Four is a look at what is in
      // there; "See All" is how somebody who wants the other thirty-six gets
      // to them.
      await tester.pumpWidget(
        _wrap(
          SubcategoryGrid(
            children: [for (var i = 0; i < 40; i++) _child(i)],
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(InkWell), findsNWidgets(SubcategoryGrid.defaultShown));
      expect(find.text('Subcategory 3'), findsOneWidget);
      expect(find.text('Subcategory 4'), findsNothing);
    });

    testWidgets('a category with no picture gets a designed tile, not a scrim', (
      tester,
    ) async {
      // Artwork at the third level of this catalogue is patchy -- Hanfu has it
      // on four of five children, every one of Antenna's six is null. The photo
      // treatment laid over nothing reads as an image that failed to load,
      // which is exactly what it looked like.
      await tester.pumpWidget(
        _wrap(
          SubcategoryGrid(
            children: const [
              Category(cid: 'bare', name: 'communication antenna'),
            ],
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      // No photograph was asked for, so nothing is loading and failing.
      expect(find.byType(Image), findsNothing);
      expect(find.text('communication antenna'), findsOneWidget);

      // And the name is dark on the tint rather than white with a drop shadow,
      // which on a plain panel was both wrong-looking and hard to read.
      final label = tester.widget<Text>(find.text('communication antenna'));
      expect(label.style?.color, isNot(Colors.white));
      expect(label.style?.shadows, anyOf(isNull, isEmpty));
    });

    testWidgets('and one with a picture still gets the photo treatment', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(SubcategoryGrid(children: [_child(0)], onSelected: (_) {})),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      final label = tester.widget<Text>(find.text('Subcategory 0'));
      expect(label.style?.color, Colors.white);
    });

    testWidgets('the name is inside the tile, not under it', (tester) async {
      // The reason it moved. Under the picture the label belonged to the grid
      // rather than to the tile, and a long name -- this catalogue is full of
      // them -- ran past the bottom of its cell and was cut off mid-word.
      // Inside a square frame there is nothing for it to overflow.
      await tester.pumpWidget(
        _wrap(
          SubcategoryGrid(
            children: [
              Category(
                cid: 'long',
                name: "Children's Knitted Sweaters and Cardigans for Autumn",
                parentCid: 'dept',
                imageUrl: 'https://example.invalid/long.jpg',
              ),
              _child(1),
            ],
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      final label = find.textContaining("Children's Knitted");
      final tile = find.byType(InkWell).first;

      // The text is drawn within the tile's own bounds, top and bottom.
      final labelBox = tester.getRect(label);
      final tileBox = tester.getRect(tile);
      expect(labelBox.top, greaterThanOrEqualTo(tileBox.top));
      expect(labelBox.bottom, lessThanOrEqualTo(tileBox.bottom + 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the tiles are square, at any text scale', (tester) async {
      // With the caption inside the frame there is nothing below the picture
      // for a text scale to grow, so the tile's height is its width -- which
      // is what makes the old clipping impossible rather than merely unlikely.
      for (final scale in [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(
          _wrap(
            SubcategoryGrid(
              children: [for (var i = 0; i < 4; i++) _child(i)],
              onSelected: (_) {},
            ),
            scale: scale,
          ),
        );
        await tester.pump();

        final tile = tester.getSize(find.byType(InkWell).first);
        expect(tile.width, closeTo(tile.height, 0.5), reason: 'at $scale');
        expect(tester.takeException(), isNull, reason: 'at $scale');
      }
    });

    testWidgets('is a named Browse section with its own way through', (
      tester,
    ) async {
      // The heading is what makes the grid a section rather than a loose block
      // of pictures under the rail above it, and the action is how somebody
      // who wants the whole department rather than a corner of it gets there.
      var sawAll = 0;
      await tester.pumpWidget(
        _wrap(
          SubcategoryGrid(
            title: 'Browse Women',
            children: [for (var i = 0; i < 4; i++) _child(i)],
            onSelected: (_) {},
            onSeeAll: () => sawAll++,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Browse Women'), findsOneWidget);

      await tester.tap(find.text('See All'));
      await tester.pump();
      expect(sawAll, 1);
    });

    testWidgets('every department on the page gets one', (tester) async {
      _tall(tester);
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      // Taken from the stub rather than typed out, so this cannot quietly
      // start asserting on a department the stub no longer serves. The live
      // catalogue's first five are Women, Men, Kidswear, Toys and Beauty; the
      // stub's are its own, and the claim is the same either way -- every
      // department with a rail gets a Browse section under it.
      //
      // Scrolled to individually because the feed builds lazily and they are
      // far apart on the page.
      for (final name in stubDepartmentNames(3)) {
        await tester.scrollUntilVisible(
          find.text('Browse $name'),
          400,
          scrollable: homeScroll(),
        );
        await tester.pumpAndSettle();
        expect(find.text('Browse $name'), findsOneWidget, reason: name);
      }
    });

    testWidgets('departments chosen by cid get a section wherever they sit', (
      tester,
    ) async {
      // Bags & Leather, Machine tools, Instruments and Agriculture sit at
      // positions 16, 19, 26 and 31 in the live tree, which is sorted for a
      // clothing shopper. Reaching them by showing more of the head of the
      // catalogue would mean twenty-seven departments on the page to get four
      // wanted ones, so they are named individually.
      //
      // Their real cids, so this fails if the constant in the feed drifts from
      // the catalogue rather than only if the feature is deleted.
      const featured = {
        '1042954': 'Bags & Leather',
        '1426': 'Machine tools',
        '10208': 'Instruments',
        '1': 'Agriculture',
      };

      _tall(tester);
      final stub = stubCatalog(departments: 5);
      stub.onCall('GET', '/alibaba-categories', (call) {
        if (call.query['parent_cid'] == 'null') {
          return reply([
            // Five ordinary departments, then the featured four buried well
            // past where the feed's head reaches.
            for (var i = 0; i < 5; i++)
              {
                'cid': 'dept-$i',
                'parent_cid': null,
                'name': 'Department $i',
                'sort_order': i,
              },
            for (final (i, entry) in featured.entries.indexed)
              {
                'cid': entry.key,
                'parent_cid': null,
                'name': entry.value,
                'sort_order': 20 + i,
              },
          ]);
        }
        return reply([
          for (final parent in [
            for (var i = 0; i < 5; i++) 'dept-$i',
            ...featured.keys,
          ])
            for (var c = 0; c < 4; c++)
              {
                'cid': '$parent-child-$c',
                'parent_cid': parent,
                'name': '$parent child $c',
                'sort_order': c,
              },
        ]);
      });
      useStubbedApi(stub);

      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      for (final name in featured.values) {
        await tester.scrollUntilVisible(
          find.text('Browse $name'),
          400,
          scrollable: homeScroll(),
        );
        await tester.pumpAndSettle();
        expect(find.text('Browse $name'), findsOneWidget, reason: name);
      }
    });

    testWidgets('a featured department already near the top is not repeated', (
      tester,
    ) async {
      // Agriculture is cid '1'. If the catalogue is ever reordered so a
      // featured department lands in the head, it must not get two sections.
      _tall(tester);
      final stub = stubCatalog(departments: 3);
      stub.onCall('GET', '/alibaba-categories', (call) {
        if (call.query['parent_cid'] == 'null') {
          return reply([
            {
              'cid': '1',
              'parent_cid': null,
              'name': 'Agriculture',
              'sort_order': 0,
            },
          ]);
        }
        return reply([
          for (var c = 0; c < 4; c++)
            {
              'cid': '1-child-$c',
              'parent_cid': '1',
              'name': 'Agriculture child $c',
              'sort_order': c,
            },
        ]);
      });
      useStubbedApi(stub);

      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Browse Agriculture'),
        400,
        scrollable: homeScroll(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Browse Agriculture'), findsOneWidget);
    });

    testWidgets('a tap opens the child it names', (tester) async {
      // Tall enough for both rows. Two-by-two squares at the default 800x600
      // put the second row off the bottom, and a tap that lands outside the
      // viewport tells you about the harness rather than about the widget.
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      Category? opened;
      await tester.pumpWidget(
        _wrap(
          SubcategoryGrid(
            children: [for (var i = 0; i < 4; i++) _child(i)],
            onSelected: (c) => opened = c,
          ),
        ),
      );
      await tester.pump();

      // The caption, which is drawn over the picture -- so this also proves the
      // scrim and the label are not swallowing the tile's own gesture.
      await tester.tap(find.text('Subcategory 2'));
      await tester.pump();

      expect(opened?.cid, 'child-2');
    });
  });

  group('the department grid', () {
    testWidgets('measures its tiles rather than guessing a ratio', (
      tester,
    ) async {
      // childAspectRatio: 1.28 was a guess that had to hold at every text
      // scale. It does not, and the label was the part that got clipped.
      for (final scale in [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(
          _wrap(
            DepartmentGrid(
              title: 'Shop by category',
              entries: [
                for (var i = 0; i < 6; i++)
                  DepartmentEntry(
                    label: 'Department $i',
                    icon: Icons.category,
                    tint: const Color(0xFF267488),
                  ),
              ],
            ),
            scale: scale,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'at $scale');
      }
    });

    // The "shows a bounded set of a large catalogue" case that used to sit here
    // is gone with its subject: the index grid it measured is no longer on the
    // home page, so there is no bound left to assert. What it was really
    // protecting -- that every department stays reachable -- is the test below.

    testWidgets('every department is still reachable from the home page', (
      tester,
    ) async {
      // This used to go through the index grid's own "See All", and that grid
      // has been removed from the feed. The Categories tab is what carries the
      // guarantee now -- and it is the better place for it, because it does not
      // depend on which departments the catalogue happens to return. The
      // curated blocks all do: Fashion favourites needs two of its four cids
      // present before it draws a "Shop more" at all.
      _tall(tester);
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      expect(find.text('Shop by category'), findsNothing);

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      expect(find.byType(BrowseScreen), findsOneWidget);
    });
  });

  group('the page holds one rhythm', () {
    testWidgets('every section heading is the same style', (tester) async {
      // Two heading sizes on one page -- titleMedium here, titleLarge in the
      // sale panel -- is what made the feed read as blocks that were each
      // designed on their own.
      _tall(tester);
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      // Compared with each other, not with a style read off the theme: the
      // theme's titleMedium carries no explicit fontSize -- it picks one up
      // from the typography when it resolves -- so asserting against it is
      // asserting null against 16.
      final headings = tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .toList();
      expect(headings.length, greaterThan(2));

      TextStyle? styleOf(SectionHeader heading) => tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byWidget(heading),
                  matching: find.text(heading.title),
                )
                .first,
          )
          .style;

      final reference = styleOf(headings.first);
      expect(reference?.fontSize, isNotNull);

      for (final heading in headings.skip(1)) {
        final style = styleOf(heading);
        expect(style?.fontSize, reference?.fontSize, reason: heading.title);
        expect(style?.fontWeight, reference?.fontWeight, reason: heading.title);
      }

      // The sale panel used to draw its own heading, a size larger than
      // everything else here, and this is where that was pinned back to the
      // page's one size. The panel is off the home page now -- only the
      // countdown card is left, and it carries no section heading -- so there
      // is nothing further to compare. The loop above is the whole check.
      expect(
        find.text('Dashain Specials'),
        findsNothing,
        reason: 'the sale panel no longer sits on the home page',
      );
    });

    testWidgets('See All sits on the page margin', (tester) async {
      // It used to sit half a step past it: the row's right padding was 8 to
      // absorb the button's own, so the action was inset differently from every
      // other block on the page.
      _tall(tester);
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      final header = find.byType(SectionHeader).first;
      final headerRight = tester.getRect(header).right;
      final actionRight = tester
          .getRect(
            find
                .descendant(of: header, matching: find.byType(TextButton))
                .first,
          )
          .right;

      // Whatever margin this section sits on, rather than a number typed here.
      // The category sections take the page's 97% measure now and the rails
      // still take the flat edge, and the claim is the same for both: the
      // action lines up with the words above it rather than half a step inside.
      final margin =
          tester.widget<SectionHeader>(header).margin ?? SectionHeader.edge;
      expect(
        headerRight - actionRight,
        closeTo(margin, 0.5),
        reason: 'the action is not on the margin',
      );
    });
  });
}

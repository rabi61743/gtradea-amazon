import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart'
    show Category;
import 'package:gtradea_amazon/features/home/widgets/department_grid.dart';
import 'package:gtradea_amazon/features/home/widgets/subcategory_grid.dart';
import 'package:gtradea_amazon/shared/widgets/page_width.dart';
import 'package:gtradea_amazon/shared/widgets/section_header.dart';

/// The home page's category sections sit on the page's own 97% measure.
///
/// Measured here rather than on the live feed, deliberately: these sections sit
/// below about 1200dp of banners, so a test that pumped the whole home page in
/// a 1500dp window would never build them and would pass by measuring nothing.
/// What is pinned is the widget's own contract -- the margin it is given is the
/// margin the heading *and* the tiles take -- plus the default that every other
/// caller in the app still relies on.

/// Categories with no artwork, so the tiles draw their plain variant and
/// nothing reaches for the network.
List<Category> _children(int count) => [
  for (var i = 0; i < count; i++) Category(cid: 'c$i', name: 'Child $i'),
];

List<DepartmentEntry> _entries(int count) => [
  for (var i = 0; i < count; i++)
    DepartmentEntry(
      label: 'Department $i',
      icon: Icons.category_outlined,
      tint: const Color(0xFF267488),
    ),
];

Future<void> _pump(WidgetTester tester, Widget child, double width) async {
  tester.view.physicalSize = Size(width * 2, 4000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

/// The box the tiles are laid out in.
Rect _gridBox(WidgetTester tester) =>
    tester.getRect(find.byType(GridView).first);

/// The heading's own inset: the padding the row sits on.
///
/// Read off the [Padding] rather than off the title's position. The heading
/// draws a leading icon and an 8pt gap before the words, so measuring where the
/// text starts reports the inset plus 26 -- which is a fact about the icon, not
/// about the margin the section keeps.
double _headingInset(WidgetTester tester) {
  final padding = tester.widget<Padding>(
    find
        .descendant(
          of: find.byType(SectionHeader).first,
          matching: find.byType(Padding),
        )
        .first,
  );
  return padding.padding.resolve(TextDirection.ltr).left;
}

void main() {
  // A phone, a tablet and a desktop window.
  const widths = [360.0, 768.0, 1280.0];

  group('the category sections take 97% of the width', () {
    testWidgets('SubcategoryGrid, at every size', (tester) async {
      for (final width in widths) {
        final margin = width * (1 - PageWidth.factor) / 2;

        await _pump(
          tester,
          SubcategoryGrid(
            title: 'Browse Women',
            margin: margin,
            children: _children(4),
            onSelected: (_) {},
            onSeeAll: () {},
          ),
          width,
        );

        final grid = _gridBox(tester);
        expect(
          grid.width,
          closeTo(width * PageWidth.factor, 1),
          reason: '97% at ${width}dp',
        );
        expect(grid.left, closeTo(margin, 0.5), reason: 'left at ${width}dp');
        expect(
          width - grid.right,
          closeTo(margin, 0.5),
          reason: 'right at ${width}dp',
        );
        // Balanced, which is what "centred" means when both are measured.
        expect(
          grid.left,
          closeTo(width - grid.right, 0.5),
          reason: 'even margins at ${width}dp',
        );
        expect(tester.takeException(), isNull, reason: 'no overflow');
      }
    });

    testWidgets('DepartmentGrid, at every size', (tester) async {
      for (final width in widths) {
        final margin = width * (1 - PageWidth.factor) / 2;

        await _pump(
          tester,
          DepartmentGrid(
            title: 'Sport and outdoors',
            margin: margin,
            columns: 2,
            entries: _entries(4),
            onSeeAll: () {},
          ),
          width,
        );

        final grid = _gridBox(tester);
        expect(
          grid.width,
          closeTo(width * PageWidth.factor, 1),
          reason: '97% at ${width}dp',
        );
        expect(grid.left, closeTo(margin, 0.5), reason: 'left at ${width}dp');
        expect(tester.takeException(), isNull, reason: 'no overflow');
      }
    });

    testWidgets('and the heading starts where the tiles do', (tester) async {
      // The half that makes it a section rather than a heading with a grid
      // under it: both sit on the one inset.
      for (final width in widths) {
        final margin = width * (1 - PageWidth.factor) / 2;

        await _pump(
          tester,
          SubcategoryGrid(
            title: 'Browse Women',
            margin: margin,
            children: _children(4),
            onSelected: (_) {},
            onSeeAll: () {},
          ),
          width,
        );

        expect(
          _headingInset(tester),
          closeTo(_gridBox(tester).left, 0.5),
          reason: 'heading and tiles on one line at ${width}dp',
        );
      }
    });
  });

  group('the stacked sections carry a tighter rhythm', () {
    /// The room above and below the heading, off the rendered padding.
    EdgeInsets headingGaps(WidgetTester tester) {
      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(SectionHeader).first,
              matching: find.byType(Padding),
            )
            .first,
      );
      return padding.padding.resolve(TextDirection.ltr);
    }

    testWidgets('dense takes room off the heading, top and bottom', (
      tester,
    ) async {
      // Thirteen sections stack down the home feed, so every point here is
      // paid twelve times more than the rhythm was designed for.
      await _pump(
        tester,
        SubcategoryGrid(
          title: 'Browse Women',
          dense: true,
          children: _children(4),
          onSelected: (_) {},
          onSeeAll: () {},
        ),
        360,
      );

      final gaps = headingGaps(tester);
      expect(gaps.top, SectionHeader.denseGapAbove);
      expect(gaps.bottom, SectionHeader.denseGapBelow);
      // Tighter than the page default, which is the point, and not zero --
      // compact rather than cramped.
      expect(gaps.top, lessThan(SectionHeader.gapAbove));
      expect(gaps.bottom, lessThan(SectionHeader.gapBelow));
      expect(gaps.top, greaterThan(8));
    });

    testWidgets('and DepartmentGrid does the same', (tester) async {
      await _pump(
        tester,
        DepartmentGrid(
          title: 'Sport and outdoors',
          dense: true,
          columns: 2,
          entries: _entries(4),
          onSeeAll: () {},
        ),
        360,
      );

      final gaps = headingGaps(tester);
      expect(gaps.top, SectionHeader.denseGapAbove);
      expect(gaps.bottom, SectionHeader.denseGapBelow);
    });

    testWidgets('but the default rhythm is untouched without it', (
      tester,
    ) async {
      // The rails, the cart, the category screen and the two skeletons all
      // draw this heading and none of them asked to move.
      await _pump(
        tester,
        SubcategoryGrid(
          title: 'Browse Women',
          children: _children(4),
          onSelected: (_) {},
          onSeeAll: () {},
        ),
        360,
      );

      final gaps = headingGaps(tester);
      expect(gaps.top, SectionHeader.gapAbove);
      expect(gaps.bottom, SectionHeader.gapBelow);
    });
  });

  group('the Browse sections are denser', () {
    testWidgets('three across, six tiles, on a tighter gap', (tester) async {
      // What the width freed by the 97% measure is meant to buy: more of the
      // department on screen, not bigger pictures with more air between them.
      const width = 360.0;
      await _pump(
        tester,
        SubcategoryGrid(
          title: 'Browse Women',
          margin: width * (1 - PageWidth.factor) / 2,
          dense: true,
          columns: 3,
          shown: 6,
          children: _children(12),
          onSelected: (_) {},
          onSeeAll: () {},
        ),
        width,
      );

      // Scoped to the grid: the heading's "See All" is a TextButton, which
      // builds an InkWell of its own, so a bare byType finder counts seven for
      // six tiles -- and every index after the first would be off by one.
      final tiles = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      );
      expect(tiles, findsNWidgets(6));

      // Three tiles on the first row, and the gap between them is the tight
      // one rather than the page default.
      final first = tester.getRect(tiles.at(0));
      final second = tester.getRect(tiles.at(1));
      final third = tester.getRect(tiles.at(2));

      expect(first.top, second.top, reason: 'one row');
      expect(second.top, third.top, reason: 'three across');
      expect(
        second.left - first.right,
        closeTo(SubcategoryGrid.denseGap, 0.5),
        reason: 'the tight gap, not the default 12',
      );

      // And the row below sits on the same measure, so it reads as a grid.
      final fourth = tester.getRect(tiles.at(3));
      expect(
        fourth.top - first.bottom,
        closeTo(SubcategoryGrid.denseGap, 0.5),
        reason: 'rows as close as the columns',
      );
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });

    testWidgets('and the tiles are wider than the gap by a long way', (
      tester,
    ) async {
      // The failure this guards: space distributed between cards rather than
      // given to them. Three tiles and two gaps must be overwhelmingly tile.
      const width = 360.0;
      await _pump(
        tester,
        SubcategoryGrid(
          title: 'Browse Women',
          margin: width * (1 - PageWidth.factor) / 2,
          dense: true,
          columns: 3,
          shown: 6,
          children: _children(6),
          onSelected: (_) {},
          onSeeAll: () {},
        ),
        width,
      );

      final tile = tester
          .getRect(
            find
                .descendant(
                  of: find.byType(GridView),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .width;
      final gaps = SubcategoryGrid.denseGap * 2;
      expect(
        tile * 3,
        greaterThan(gaps * 10),
        reason: 'the width is in the cards, not between them',
      );
    });

    testWidgets('the curated blocks stay two across', (tester) async {
      // Fashion Favourites, Electronic Components, Home Appliances and Sport
      // and Outdoors each hold exactly four, which three across would break
      // into a row of three and an orphan.
      await _pump(
        tester,
        SubcategoryGrid(
          title: 'Fashion favourites',
          dense: true,
          children: _children(4),
          onSelected: (_) {},
        ),
        360,
      );

      final tiles = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      );
      final first = tester.getRect(tiles.at(0));
      final second = tester.getRect(tiles.at(1));
      final third = tester.getRect(tiles.at(2));

      expect(first.top, second.top, reason: 'two on the first row');
      expect(third.top, greaterThan(first.bottom), reason: 'and two below');
    });
  });

  group('every other caller is untouched', () {
    testWidgets('SubcategoryGrid keeps the flat edge when given no margin', (
      tester,
    ) async {
      // The category screen lays this out itself and passes nothing, so the
      // default has to stay exactly what it was.
      await _pump(
        tester,
        SubcategoryGrid(
          title: 'Browse Women',
          children: _children(4),
          onSelected: (_) {},
        ),
        360,
      );

      expect(_gridBox(tester).left, closeTo(SectionHeader.edge, 0.5));
      expect(_headingInset(tester), closeTo(SectionHeader.edge, 0.5));
    });

    testWidgets('DepartmentGrid does too', (tester) async {
      await _pump(
        tester,
        DepartmentGrid(title: 'Shop by category', entries: _entries(6)),
        360,
      );

      expect(_gridBox(tester).left, closeTo(SectionHeader.edge, 0.5));
    });
  });
}

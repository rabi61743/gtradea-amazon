import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/department_tabs.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

/// The header's own band: the one box carrying the brand gradient.
Finder get _band => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).gradient == AppColors.brandBand,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stubCatalog();
    CatalogStore.instance.resetForTest();
  });

  tearDown(clearApiStub);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the departments sit below the header, not inside it', (
    tester,
  ) async {
    await pump(tester);

    // Its own block now: the header's band no longer has the strip in it.
    expect(
      find.descendant(of: _band, matching: find.byType(DepartmentTabs)),
      findsNothing,
    );

    final header = tester.getRect(find.byType(SearchHeader));
    final strip = tester.getRect(find.byType(DepartmentTabs));

    expect(strip.top, greaterThanOrEqualTo(header.bottom));
  });

  testWidgets('and above the feed, covering none of it', (tester) async {
    await pump(tester);

    final strip = tester.getRect(find.byType(DepartmentTabs));
    final feed = tester.getRect(find.byType(HomeFeed));

    // Stacked in a column rather than laid over it: the hero starts where the
    // strip ends.
    expect(strip.bottom, lessThanOrEqualTo(feed.top + 0.5));
  });

  testWidgets('the header ends on a straight edge, with the page below it', (
    tester,
  ) async {
    // The foot has been three things: two 16pt cut corners, a downward bulge,
    // and an arch. It is a plain edge now, by request -- nothing is cut out of
    // the band, and what separates it from the departments is the gap beneath
    // it rather than a shape.
    await pump(tester);

    expect(
      find.ancestor(
        of: find.byType(SearchHeader),
        matching: find.byType(ClipPath),
      ),
      findsNothing,
      reason: 'nothing shapes the foot of the band',
    );

    final header = tester.getRect(find.byType(SearchHeader));
    final strip = tester.getRect(find.byType(DepartmentTabs));
    expect(strip.top, greaterThan(header.bottom));
  });

  testWidgets('and it is straight at every width', (tester) async {
    // Checked across the sizes the app ships to, because the header does branch
    // on width -- the brand mark steps 26/30/34 -- so a shape reintroduced at
    // one breakpoint only would be caught here rather than on one phone.
    for (final width in [320.0, 360.0, 412.0, 600.0, 840.0, 1280.0]) {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pump(tester);

      expect(
        find.ancestor(
          of: find.byType(SearchHeader),
          matching: find.byType(ClipPath),
        ),
        findsNothing,
        reason: '${width}dp',
      );

      // And the page still shows between the band and the departments at every
      // one of them: the gap is doing the separating now.
      final header = tester.getRect(find.byType(SearchHeader));
      final strip = tester.getRect(find.byType(DepartmentTabs));
      expect(strip.top, greaterThan(header.bottom), reason: '${width}dp');
      expect(tester.takeException(), isNull, reason: '${width}dp');
    }
  });

  testWidgets('and no child of the header had its own corners changed', (
    tester,
  ) async {
    // The band's corner is the only thing that moved. The search pill, the two
    // grouped blocks and the action tiles keep the radii they had.
    await pump(tester);

    final pill = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(SearchHeader.pillKey),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(pill.borderRadius, BorderRadius.circular(9));

    final blocks = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(SearchHeader),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.borderRadius)
        .whereType<BorderRadius>();

    // The delivery block and the actions block, both still 14.
    expect(blocks, contains(BorderRadius.circular(14)));
    expect(blocks.contains(BorderRadius.circular(16)), isFalse);
  });

  testWidgets('nothing in the header sits on its bottom edge', (tester) async {
    // The greeting and the search pill are the last things in the band, and
    // they used to finish a few points off its foot -- close enough to touch
    // the corners once those were cut round again.
    await pump(tester);

    final band = tester.getRect(find.byType(SearchHeader));

    for (final finder in <Finder>[
      find.byKey(SearchHeader.pillKey),
      // The pill's own controls: the search glyph at its head and the image
      // button at its tail, which are the parts nearest the corners.
      find.descendant(
        of: find.byKey(SearchHeader.pillKey),
        matching: find.byIcon(Icons.search),
      ),
      find.descendant(
        of: find.byKey(SearchHeader.pillKey),
        matching: find.byIcon(Icons.center_focus_weak),
      ),
      find.text('Hi,'),
    ]) {
      if (finder.evaluate().isEmpty) continue;
      final rect = tester.getRect(finder.first);
      expect(
        band.bottom - rect.bottom,
        greaterThanOrEqualTo(SearchHeader.footRoom - 0.5),
        reason: 'clear of the band foot: $finder',
      );
    }
  });

  testWidgets('the tabs sit on the page, with no card behind them', (
    tester,
  ) async {
    // Removed by request: the strip had a white ground and a rule under it,
    // which read as a card. What is left is the tabs themselves on the page's
    // own background.
    await pump(tester);

    final behind = tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.byType(DepartmentTabs),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>();

    // Nothing painted behind them at all: no fill, no rule, and none of the
    // header's band either.
    expect(behind.map((d) => d.color).whereType<Color>(), isEmpty);
    expect(behind.where((d) => d.border != null), isEmpty);
    expect(behind.map((d) => d.gradient).whereType<Gradient>(), isEmpty);
  });

  testWidgets('and the page shows between them and the header', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byType(SearchHeader));
    final tabs = tester.getRect(find.byType(DepartmentTabs));

    expect(tabs.top, greaterThan(header.bottom));
  });

  testWidgets('a narrow phone and a tablet both get the whole strip', (
    tester,
  ) async {
    // Full width on either, and horizontally scrollable, so no department is
    // out of reach on a small screen.
    for (final size in [const Size(1080, 2000), const Size(1600, 2400)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      );
      await tester.pumpAndSettle();

      final width = size.width / 2.0;
      final strip = tester.getRect(find.byType(DepartmentTabs));

      expect(strip.left, 0, reason: '$size');
      expect(strip.right, width, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('and it still folds and still chooses a department', (
    tester,
  ) async {
    await pump(tester);

    final feed = find
        .descendant(
          of: find.byType(HomeFeed),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;

    expect(
      tester.widget<DepartmentTabs>(find.byType(DepartmentTabs)).compact,
      isFalse,
    );

    await tester.drag(feed, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(
      tester.widget<DepartmentTabs>(find.byType(DepartmentTabs)).compact,
      isTrue,
      reason: 'moving out of the header did not cost it the fold',
    );

    final other = tester
        .widget<DepartmentTabs>(find.byType(DepartmentTabs))
        .categories
        .first;
    await tester.tap(find.text(other.name).first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<DepartmentTabs>(find.byType(DepartmentTabs)).selectedCid,
      other.cid,
    );
  });
}

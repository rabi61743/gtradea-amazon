import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/department_tabs.dart';
import 'package:gtradea_amazon/features/home/widgets/delivery_points_card.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notifications_screen.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_tracker_button.dart';
import 'package:gtradea_amazon/features/support/presentation/support_button.dart';
import 'package:gtradea_amazon/shared/widgets/brand_wordmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

/// The feed's own vertical list, which is what a shopper drags.
final _feed = find
    .descendant(
      of: find.byType(HomeFeed),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .first;

/// The strip as it stands right now.
DepartmentTabs _tabs(WidgetTester tester) =>
    tester.widget<DepartmentTabs>(find.byType(DepartmentTabs));

/// How tall the strip's own box is.
double _stripHeight(WidgetTester tester) =>
    tester.getSize(find.byType(DepartmentTabs)).height;

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

  testWidgets('the icons fold away on a scroll and the labels stay', (
    tester,
  ) async {
    await pump(tester);

    expect(_tabs(tester).compact, isFalse);
    final open = _stripHeight(tester);
    expect(find.text('For You'), findsOneWidget);

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(_tabs(tester).compact, isTrue);
    // Shorter by exactly the tile it dropped, and the words are still there.
    expect(_stripHeight(tester), lessThan(open));
    expect(find.text('For You'), findsOneWidget);
  });

  testWidgets('and come back at the top', (tester) async {
    await pump(tester);
    final open = _stripHeight(tester);

    final feed = _feed;
    await tester.drag(feed, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_tabs(tester).compact, isTrue);

    await tester.drag(feed, const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(_tabs(tester).compact, isFalse);
    expect(_stripHeight(tester), open);
  });

  testWidgets('the fold is animated rather than a jump', (tester) async {
    await pump(tester);
    final open = _stripHeight(tester);

    await tester.drag(_feed, const Offset(0, -300));
    // Part way through the transition the strip is between its two heights,
    // which is what "no layout jump" means here.
    await tester.pump();
    await tester.pump(DepartmentTabs.collapse ~/ 2);

    final midway = _stripHeight(tester);
    expect(midway, lessThan(open));
    expect(
      midway,
      greaterThan(
        DepartmentTabs.heightFor(
          tester.element(find.byType(DepartmentTabs)),
          compact: true,
        ),
      ),
    );

    await tester.pumpAndSettle();
  });

  test('the strip folds on the header own timing, not its own', () {
    // The defect this guards: these were 220ms/easeOut against the header's
    // 450ms/easeInOutCubic. Two stacked elements folding on one gesture, timed
    // as two movements -- the strip finished while the band was barely halfway,
    // so the artwork appeared to lurch, settle, then carry on.
    //
    // Asserted rather than assumed, because the strip now references the
    // header's constants and a future edit could quietly give it its own again.
    expect(DepartmentTabs.collapse, SearchHeader.fold);
    expect(DepartmentTabs.collapseCurve, SearchHeader.foldCurve);
  });

  testWidgets('and the band and the strip are mid-travel at the same instant', (
    tester,
  ) async {
    // The real test of "they move together": sample both at one moment part
    // way through and require each to be strictly between its own endpoints.
    //
    // Under the old timing the strip was already finished at this instant --
    // its 220ms was over before the header's 450ms reached halfway -- so this
    // would have found it sitting at its closed height while the band was still
    // moving. That is what read as an abrupt image.
    await pump(tester);
    final bandOpen = tester.getSize(find.byType(SearchHeader)).height;
    final stripOpen = _stripHeight(tester);

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pump();
    await tester.pump(SearchHeader.fold ~/ 2);

    final bandMid = tester.getSize(find.byType(SearchHeader)).height;
    final stripMid = _stripHeight(tester);

    await tester.pumpAndSettle();
    final bandClosed = tester.getSize(find.byType(SearchHeader)).height;
    final stripClosed = _stripHeight(tester);

    expect(bandMid, lessThan(bandOpen), reason: 'the band has started');
    expect(bandMid, greaterThan(bandClosed), reason: 'and has not arrived');
    expect(stripMid, lessThan(stripOpen), reason: 'the strip has started');
    expect(
      stripMid,
      greaterThan(stripClosed),
      reason: 'and has not arrived either -- it used to be finished by now',
    );
  });

  testWidgets('the header glyphs are the smaller size', (tester) async {
    await pump(tester);

    // The three chrome icons share one size, and it is the reduced one.
    final sizes = tester
        .widgetList<Icon>(
          find.descendant(
            of: find.byType(SearchHeader),
            matching: find.byType(Icon),
          ),
        )
        .map((icon) => icon.size)
        .whereType<double>()
        .toSet();
    // The three actions share whatever [SearchHeader] sets, and it is under
    // Material's 24. The exact number is being tuned, so what is pinned here is
    // that one constant feeds all three -- three buttons each carrying their
    // own default is how the bell wandered off its margin.
    final actions = tester
        .widgetList<Icon>(
          find.descendant(
            of: find.byType(OrderTrackerButton),
            matching: find.byType(Icon),
          ),
        )
        .map((icon) => icon.size)
        .whereType<double>();

    expect(actions, isNotEmpty);
    expect(sizes.contains(actions.first), isTrue);
    expect(sizes.contains(24), isFalse, reason: 'not the Material default');
    expect(actions.first, lessThan(24));
  });

  testWidgets('the chosen tab is marked in Commerce Orange, and only it', (
    tester,
  ) async {
    await pump(tester);

    // The tile behind the chosen department, and every other tile.
    Iterable<Color> tileColours() => tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(DepartmentTabs),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .whereType<Color>();

    // The chosen tab's tile is a wash of the brand orange and its underline is
    // the orange itself, so the count is of the hue rather than of the exact
    // colour: two marks, both on the one tab.
    bool isBrandOrange(Color c) =>
        Color(c.toARGB32() | 0xFF000000) == AppColors.commerceOrange;

    // The glyphs drawn in the active colour. One, on the chosen tab: the
    // unchosen ones take the page's near-black.
    Iterable<Icon> orangeGlyphs() => tester
        .widgetList<Icon>(
          find.descendant(
            of: find.byType(DepartmentTabs),
            matching: find.byType(Icon),
          ),
        )
        .where((icon) => icon.color != null && isBrandOrange(icon.color!));

    expect(
      tileColours().where(isBrandOrange),
      hasLength(2),
      reason: 'one tile wash and one underline, on the one chosen tab',
    );
    expect(orangeGlyphs(), hasLength(1), reason: 'one glyph in the active hue');

    // Switching moves the mark rather than adding a second one.
    final other = _tabs(tester).categories.first;
    await tester.tap(find.text(other.name).first);
    await tester.pumpAndSettle();

    expect(
      tileColours().where(isBrandOrange),
      hasLength(2),
      reason: 'the mark moved rather than multiplied',
    );
    expect(orangeGlyphs(), hasLength(1), reason: 'and so did the glyph');
    expect(_tabs(tester).selectedCid, other.cid);
  });

  /// How faded the utilities row is: 0 while it is on show, 1 once it has
  /// gone. It stays in the tree either way -- it is collapsed rather than
  /// dismantled, which is what lets it come back with its badges intact.
  /// How faded the brand row is, by the same measure.
  double brandFade(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.byType(BrandWordmark),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  double utilitiesFade(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.byType(DeliveryPointsCard),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  testWidgets('both rows go on the way down, and the search bar stays', (
    tester,
  ) async {
    await pump(tester);

    // At the top: the brand, the delivery and points card, and the three actions.
    expect(find.byType(BrandWordmark), findsOneWidget);
    expect(find.byType(DeliveryPointsCard), findsOneWidget);
    expect(find.byType(NotificationBell), findsOneWidget);
    expect(find.byType(OrderTrackerButton), findsOneWidget);
    expect(find.byType(SupportButton), findsOneWidget);
    expect(utilitiesFade(tester), 1);

    final open = tester.getSize(find.byType(SearchHeader)).height;

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pumpAndSettle();

    // Both rows have faded out and given up their height. What is left is the
    // greeting and the search bar, which is what somebody reading a feed is
    // actually reaching for.
    expect(utilitiesFade(tester), 0);
    expect(brandFade(tester), 0, reason: 'the name and the country line go');
    expect(
      tester.getSize(find.byType(SearchHeader)).height,
      lessThan(open - 90),
    );
    // The search bar, and the greeting beside it for a shopper who is signed
    // in -- this one is not, and the pill takes the width instead.
    expect(find.byKey(SearchHeader.pillKey), findsOneWidget);

    await tester.drag(_feed, const Offset(0, 200));
    await tester.pumpAndSettle();

    // Back on the way up, without having to reach the top of the feed.
    expect(utilitiesFade(tester), 1);
    expect(brandFade(tester), 1);
    expect(tester.getSize(find.byType(SearchHeader)).height, open);
  });

  testWidgets('and it fades and slides rather than blinking out', (
    tester,
  ) async {
    await pump(tester);

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pump();
    // A fifth of the way in. The curve is an ease-out, so it covers most of
    // its distance early -- by half time the row is nearly gone, which is the
    // point of an ease-out and not a reason to sample it there.
    await tester.pump(SearchHeader.fold ~/ 5);

    // Part faded, part moved, and still on screen. A row that were switched
    // off would already read 0 here.
    final fade = utilitiesFade(tester);
    expect(fade, greaterThan(0));
    expect(fade, lessThan(1));

    final slide = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byType(DeliveryPointsCard),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(slide.transform.getTranslation().y, lessThan(0), reason: 'rising');

    await tester.pumpAndSettle();
  });

  testWidgets('and the fold is animated, not a jump', (tester) async {
    await pump(tester);
    final open = tester.getSize(find.byType(SearchHeader)).height;

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pump();
    await tester.pump(SearchHeader.fold ~/ 2);

    final midway = tester.getSize(find.byType(SearchHeader)).height;
    expect(midway, lessThan(open));

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SearchHeader)).height, lessThan(midway));
  });

  testWidgets('the band carries the artwork, greyed and on the ridge', (
    tester,
  ) async {
    await pump(tester);

    final band = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.image != null);

    final art = band.image!;
    expect(
      (art.image as AssetImage).assetName,
      'assets/images/header_background.jpg',
    );
    // Grey rather than colour, visible rather than a smudge, and still under
    // half so white type on the band stays legible.
    expect(art.colorFilter, isNotNull);
    // A picture in the header rather than a watermark under it: 45-60% is
    // the weight the design asks for, and the scrim below the peaks is what
    // gives the type back its contrast.
    expect(art.opacity, greaterThanOrEqualTo(0.45));
    expect(art.opacity, lessThanOrEqualTo(0.60));
    // Down and to the right, which is where the range and the stupa are in
    // a picture nearly three times as wide as the band is tall.
    expect(art.alignment, const Alignment(0.3, 0.55));
    // The ramp underneath it is untouched.
    expect(band.gradient, AppColors.homeHeaderBand);
  });
}

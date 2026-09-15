import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

/// The band leaves gently and comes back promptly.
///
/// Two separate claims, and each is the reason the other is safe: folding away
/// is unprompted, so it can take its time and ease in; coming back answers a
/// reach for the search bar, so it stays quick. A single shared pace cannot be
/// right for both, which is what this file exists to stop anyone "tidying"
/// back into one constant.

final _feed = find
    .descendant(
      of: find.byType(HomeFeed),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .first;

double _headerHeight(WidgetTester tester) =>
    tester.getSize(find.byType(SearchHeader)).height;

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

  test('leaving is slower than arriving, and eased at both ends', () {
    // The pace. Pinned as a relationship rather than as two numbers, so either
    // can be tuned without this test becoming a copy of the constants.
    expect(
      SearchHeader.fold,
      greaterThan(SearchHeader.reveal * 2),
      reason: 'the fold is unhurried against a prompt return',
    );
    // An ease-in-out on the way out: the gradual start is what stops the band
    // bolting ahead of the page the instant a scroll begins.
    expect(SearchHeader.foldCurve, Curves.easeInOutCubic);
    // And an ease-out on the way back, where a gradual start would read as lag.
    expect(SearchHeader.revealCurve, Curves.easeOutCubic);
  });

  testWidgets('the fold starts gently rather than bolting', (tester) async {
    await pump(tester);
    final open = _headerHeight(tester);

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pump();
    // A fifth of the way in. An ease-out would already have covered most of
    // its distance by here -- that is the "rushed" this replaced. An ease-in-out
    // has barely started.
    await tester.pump(SearchHeader.fold ~/ 5);

    final early = _headerHeight(tester);
    final travelled = open - early;
    await tester.pumpAndSettle();
    final total = open - _headerHeight(tester);

    expect(total, greaterThan(0), reason: 'it did fold');
    expect(
      travelled / total,
      lessThan(0.35),
      reason: 'barely underway a fifth of the way in, not most of the way',
    );
  });

  testWidgets('and still finishes, without a jolt at the end', (tester) async {
    await pump(tester);
    final open = _headerHeight(tester);

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pump();
    // Four fifths through, an ease-in-out is nearly home: the last stretch is
    // the slow one, which is what keeps the finish from landing as a stop.
    await tester.pump(SearchHeader.fold * 4 ~/ 5);

    final late = _headerHeight(tester);
    await tester.pumpAndSettle();
    final folded = _headerHeight(tester);

    expect(late, lessThan(open));
    expect(
      late - folded,
      lessThan((open - folded) * 0.25),
      reason: 'most of the way home before the end, so it eases out of it',
    );
  });

  testWidgets('coming back is still prompt', (tester) async {
    // The half that must not regress: the slower fold is for leaving only.
    await pump(tester);
    final open = _headerHeight(tester);

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_headerHeight(tester), lessThan(open));

    await tester.drag(_feed, const Offset(0, 200));
    await tester.pump();
    await tester.pump(SearchHeader.reveal);

    expect(
      _headerHeight(tester),
      closeTo(open, 1),
      reason: 'home inside its own duration, which the fold no longer is',
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

/// The header must settle once per gesture, not chatter.
///
/// The fold itself is already animated and already has a dead-zone; what this
/// file is about is *when the decision is taken*. A fling keeps producing
/// scroll notifications after the finger has gone -- momentum, the settle at
/// the end of it, and the overscroll a RefreshIndicator allows -- and a
/// reversal of more than the dead-zone in any of those flips the header back
/// with nobody touching the glass.

/// The feed's own vertical list, which is what a shopper drags.
final _feed = find
    .descendant(
      of: find.byType(HomeFeed),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .first;

/// Whether the header is folded right now, read off the widget rather than off
/// private state.
bool _folded(WidgetTester tester) =>
    tester.widget<SearchHeader>(find.byType(SearchHeader)).compact;

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

  /// Every value [compact] takes while the frames run, in order.
  ///
  /// The count is the point: one change per gesture is a fold, several is the
  /// chatter this is about.
  Future<List<bool>> record(
    WidgetTester tester,
    Future<void> Function() gesture,
  ) async {
    final seen = <bool>[_folded(tester)];
    void sample() {
      final now = _folded(tester);
      if (now != seen.last) seen.add(now);
    }

    await gesture();
    // Step the frames by hand rather than settling in one go: pumpAndSettle
    // runs to quiescence and would hide every intermediate flip.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      sample();
    }
    await tester.pumpAndSettle();
    sample();
    return seen;
  }

  testWidgets('a fling down folds the header once and leaves it folded', (
    tester,
  ) async {
    await pump(tester);
    expect(_folded(tester), isFalse);

    // A fling, not a drag: the finger leaves the glass and the momentum,
    // the settle and any overscroll all keep reporting afterwards.
    final states = await record(
      tester,
      () => tester.fling(_feed, const Offset(0, -600), 3000),
    );

    expect(states.last, isTrue, reason: 'it ends folded');
    expect(
      states.length,
      lessThanOrEqualTo(2),
      reason: 'one change of mind for one gesture, not a flap: saw $states',
    );
  });

  testWidgets('and a fling back up unfolds it once', (tester) async {
    await pump(tester);
    await tester.fling(_feed, const Offset(0, -600), 3000);
    await tester.pumpAndSettle();
    expect(_folded(tester), isTrue);

    final states = await record(
      tester,
      () => tester.fling(_feed, const Offset(0, 400), 3000),
    );

    expect(states.last, isFalse, reason: 'it ends open');
    expect(
      states.length,
      lessThanOrEqualTo(2),
      reason: 'one change of mind for one gesture, not a flap: saw $states',
    );
  });

  testWidgets('overscrolling at the top does not flap it', (tester) async {
    // The feed sits in a RefreshIndicator, so dragging down past the top is a
    // real gesture that reports scroll the whole way. At the top the header is
    // open and must simply stay open.
    await pump(tester);
    expect(_folded(tester), isFalse);

    final states = await record(
      tester,
      () => tester.fling(_feed, const Offset(0, 300), 2000),
    );

    expect(states, [isFalse], reason: 'never folded at all: saw $states');
  });

  testWidgets('a sideways rail does not move the header', (tester) async {
    // Every rail in the feed scrolls horizontally. One of them must not be
    // able to fold the header, whatever offsets it reports.
    await pump(tester);
    expect(_folded(tester), isFalse);

    final rail = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        )
        .first;
    if (rail.evaluate().isEmpty) {
      markTestSkipped('no horizontal rail in the stubbed feed');
      return;
    }

    await tester.fling(rail, const Offset(-400, 0), 2000);
    await tester.pumpAndSettle();

    expect(_folded(tester), isFalse);
  });

  testWidgets('the gesture direction is what the feed reports', (tester) async {
    // A guard on the mechanism rather than the effect: the notifications the
    // header listens to carry a real direction, so the decision can be taken
    // from the gesture instead of inferred from position deltas.
    await pump(tester);

    final directions = <ScrollDirection>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            directions.add(n.direction);
            return false;
          },
          child: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(_feed, const Offset(0, -600), 3000);
    await tester.pumpAndSettle();

    expect(
      directions,
      contains(ScrollDirection.reverse),
      reason: 'dragging up the page reports reverse',
    );
  });
}

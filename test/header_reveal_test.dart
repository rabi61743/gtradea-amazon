import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

/// The header answers an upward scroll faster than it gets out of the way.
///
/// Both halves of that are pinned here, because either one alone is a header
/// that feels wrong in the other direction: a quick return with a twitchy
/// threshold flaps, and a patient threshold with a slow return reads as lag.

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

  testWidgets('it comes back quicker than it goes away', (tester) async {
    await pump(tester);
    final open = _headerHeight(tester);

    // Going away: after the *reveal's* worth of time it is still on its way,
    // because hiding is the slower of the two.
    await tester.drag(_feed, const Offset(0, -300));
    await tester.pump();
    await tester.pump(SearchHeader.reveal);
    final partWayDown = _headerHeight(tester);
    await tester.pumpAndSettle();
    final folded = _headerHeight(tester);

    expect(
      partWayDown,
      greaterThan(folded),
      reason: 'the fold is still travelling after the reveal duration',
    );

    // Coming back: the same elapsed time and it has already arrived.
    await tester.drag(_feed, const Offset(0, 200));
    await tester.pump();
    await tester.pump(SearchHeader.reveal);

    expect(
      _headerHeight(tester),
      closeTo(open, 1),
      reason: 'the reveal is done inside its own duration',
    );
  });

  testWidgets('and it starts on a shorter upward travel', (tester) async {
    await pump(tester);
    final open = _headerHeight(tester);

    await tester.drag(_feed, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_headerHeight(tester), lessThan(open));

    // Twenty points back up: less than the thirty-two a fold needs, and enough
    // to be heard. This is the delay the change removes -- the shopper reaching
    // for the search bar no longer has to ask twice.
    await tester.drag(_feed, const Offset(0, 20));
    await tester.pumpAndSettle();

    expect(
      _headerHeight(tester),
      open,
      reason: 'a short reach up brings it back',
    );
  });

  testWidgets('but a stray pixel downward still does not fold it', (
    tester,
  ) async {
    // The other half. The upward threshold came down; the downward one did
    // not, so the dead-zone that stops the header flapping is still there.
    await pump(tester);
    final open = _headerHeight(tester);

    // Past the top, so the "at the top" rule is not what is holding it open,
    // then a nudge too small to count as a scroll down.
    await tester.drag(_feed, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.drag(_feed, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(_headerHeight(tester), open);

    await tester.drag(_feed, const Offset(0, -20));
    await tester.pumpAndSettle();

    expect(
      _headerHeight(tester),
      open,
      reason: 'twenty points down is not a committed scroll',
    );
  });
}

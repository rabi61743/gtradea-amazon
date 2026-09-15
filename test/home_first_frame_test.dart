import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/hero_banner.dart' as hb;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.resetForTest();
  });

  tearDown(clearApiStub);

  testWidgets('a zero-sized first frame does not blank the home feed', (
    tester,
  ) async {
    // Android can lay the first frame out before the window has a size. A
    // promo banner decoding at "screen width" asked `Image` for a cache width
    // of 0 there, which is an assertion; thrown in the middle of the feed's
    // layout, it left the list without geometry, and in a debug build the
    // whole feed -- hero, flash sale, promos, products -- painted nothing.
    stubCatalog();
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size.zero;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'nothing thrown at 0 x 0');

    // Then the real window, as the platform delivers it. The width the other
    // home tests use: the test font is wider than a real one, and a narrower
    // window overflows its text for reasons of its own.
    tester.view.physicalSize = const Size(1100, 2400);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final feed = tester.getRect(find.byType(HomeFeed));
    final hero = tester.getRect(find.byType(hb.HeroBanner));
    expect(hero.height, greaterThan(0), reason: 'the hero is laid out');
    expect(
      hero.top,
      lessThan(feed.bottom),
      reason: 'and sits inside the visible feed, not below a broken list',
    );
  });
}

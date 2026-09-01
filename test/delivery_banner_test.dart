import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/delivery_banner.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

late FakeApi api;

void _view(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width * 2, 14000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _inFeed(Finder target) =>
    find.descendant(of: find.byType(HomeFeed), matching: target);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
  });

  testWidgets('promises nothing about delivery being free', (tester) async {
    // The reference read "Free Delivery -- on orders above Rs. 1,999". Nothing
    // in this app does that: `freeDelivery` is never parsed from any response,
    // and /promo-codes/active comes back empty. A shopper who spent Rs. 2,000
    // on the strength of that banner would still be charged.
    _view(tester, 400);
    await tester.pumpWidget(_wrap(DeliveryBanner(onShop: () {})));
    await tester.pump();

    expect(find.textContaining('Free'), findsNothing);
    expect(find.textContaining('1,999'), findsNothing);
  });

  testWidgets('and it quotes no delivery figure at all', (tester) async {
    // It used to print CartStore.deliveryFee, a flat 100 held in this codebase.
    // The server prices freight per basket and destination, so any figure here
    // is one the cart contradicts a screen later.
    _view(tester, 400);
    await tester.pumpWidget(_wrap(DeliveryBanner(onShop: () {})));
    await tester.pump();

    expect(find.textContaining('Rs.'), findsNothing);
    expect(find.textContaining('flat'), findsNothing);
    expect(find.textContaining('quoted before you pay'), findsOneWidget);
  });

  testWidgets('the button works and goes to a product listing', (tester) async {
    _view(tester, 400);
    var taps = 0;
    await tester.pumpWidget(_wrap(DeliveryBanner(onShop: () => taps++)));
    await tester.pump();

    await tester.tap(find.text('Shop now'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('no button when there is nowhere to send anyone', (tester) async {
    _view(tester, 400);
    await tester.pumpWidget(_wrap(const DeliveryBanner()));
    await tester.pump();

    expect(find.text('Shop now'), findsNothing);
  });

  testWidgets('lays out from a small phone to a desktop window', (
    tester,
  ) async {
    for (final width in [320.0, 412.0, 800.0, 1400.0]) {
      _view(tester, width);
      await tester.pumpWidget(_wrap(DeliveryBanner(onShop: () {})));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '${width}dp');

      // Past its cap the panel centres rather than stretching across a desktop.
      // Measured on the panel itself, not on the widget: the widget carries the
      // page margin, so its own rect is the full width at every size.
      final panel = tester.getSize(
        find
            .descendant(
              of: find.byType(DeliveryBanner),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        panel.width,
        lessThanOrEqualTo(DeliveryBanner.maxWidth + 1),
        reason: '${width}dp',
      );
    }
  });

  testWidgets('nothing overflows at any text scale', (tester) async {
    for (final scale in [1.0, 1.5, 2.0]) {
      _view(tester, 360);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(child: DeliveryBanner(onShop: () {})),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'at $scale');
    }
  });

  testWidgets('sits directly above the recommendations', (tester) async {
    _view(tester, 550);
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    final banner = tester.getRect(_inFeed(find.byType(DeliveryBanner))).top;
    final rail = tester.getRect(find.text('Recommended for you')).top;

    expect(banner, lessThan(rail));
  });

  testWidgets('and its button opens a listing from the feed', (tester) async {
    _view(tester, 550);
    await tester.pumpWidget(const GtradeaAmazonApp());
    await tester.pumpAndSettle();

    // Scoped to the banner: the flash sale card carries a "Shop now" of its
    // own, so a bare text finder matches two. Scrolled to as well -- the banner
    // sits near the foot of the feed, and a tap outside the viewport tells you
    // about the harness rather than about the button.
    await tester.scrollUntilVisible(
      find.descendant(
        of: find.byType(DeliveryBanner),
        matching: find.text('Shop now'),
      ),
      400,
      scrollable: find
          .descendant(
            of: find.byType(HomeFeed),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(DeliveryBanner),
        matching: find.text('Shop now'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SearchResultsScreen), findsOneWidget);
  });
}

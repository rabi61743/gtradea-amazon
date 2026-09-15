import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gtradea_amazon/shared/widgets/page_width.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/logistics/data/shipping_mode_store.dart';
import 'package:gtradea_amazon/features/product/data/storefront_config.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/logistics_trust_card.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// The live shape: a bare array of rows whose `setting_value` is a **string**
/// holding JSON. The real site double-encodes it, and a parser that expects an
/// object silently reads nothing.
List<Map<String, dynamic>> settings(Map<String, dynamic> note) => [
  {'setting_key': 'service_fee_percent', 'setting_value': 25},
  {'setting_key': 'shipping_estimate_note', 'setting_value': jsonEncode(note)},
];

/// What `shipping_estimate_note` actually holds on the live site: the note
/// switched off, every freight rate disabled, and **no guarantee object**.
Map<String, dynamic> get liveNote => {
  'enabled': false,
  'heading': 'Shipping & Courier (charged on delivery, as per actual)',
  'showHeading': false,
  'placement': {'checkout': false, 'cart': false, 'product': false},
  'modes': [
    {'key': 'air', 'label': 'By Air', 'perKg': 3500, 'enabled': false},
  ],
};

Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(product: sampleProduct, detail: sampleDetail),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.scrollUntilVisible(
    find.byType(LogisticsTrustCard),
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    StorefrontConfigRepository.instance.resetForTest();
    ShippingModeStore.instance.resetForTest();
    api.on('GET', '/site-settings', body: settings(liveNote));
  });

  group('reading the setting', () {
    test('decodes a value the site encoded as a string', () async {
      final shipping = await StorefrontConfigRepository.instance.shipping();

      expect(shipping.enabled, isFalse, reason: 'the live value');
    });

    test('falls back to the documented window when none is published', () async {
      // Measured: the live setting carries no `guarantee` object at all. These
      // two numbers are the sibling storefront's defaults, and this is the test
      // that says so out loud.
      final shipping = await StorefrontConfigRepository.instance.shipping();

      expect(shipping.guarantee.enabled, isTrue);
      expect(shipping.guarantee.weeksMin, 3);
      expect(shipping.guarantee.weeksMax, 5);
    });

    test('takes the published window when there is one', () async {
      api.on(
        'GET',
        '/site-settings',
        body: settings({
          ...liveNote,
          'guarantee': {'enabled': true, 'weeksMin': 1, 'weeksMax': 2},
        }),
      );
      StorefrontConfigRepository.instance.resetForTest();

      final shipping = await StorefrontConfigRepository.instance.shipping();
      expect(shipping.guarantee.weeksMin, 1);
      expect(shipping.guarantee.weeksMax, 2);
    });

    test('asks the server once, not once per product page', () async {
      await StorefrontConfigRepository.instance.shipping();
      await StorefrontConfigRepository.instance.shipping();

      // 21KB of payment-gateway configuration, re-read on every product page,
      // to draw two dates.
      expect(api.calls.where((c) => c.path == '/site-settings'), hasLength(1));
    });
  });

  group('the window', () {
    test('counts from today, not from a date the server named', () {
      const guarantee = DeliveryGuarantee(weeksMin: 3, weeksMax: 5);
      final (from, to) = guarantee.windowFrom(DateTime(2026, 8, 28));

      expect(from, DateTime(2026, 9, 18));
      expect(to, DateTime(2026, 10, 2));
    });

    testWidgets('is drawn as a range, never as a single date', (tester) async {
      // A single date would be a delivery date the business has not committed
      // to. The whole basis of this figure is a window.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LogisticsTrustCard(
              guarantee: const DeliveryGuarantee(weeksMin: 3, weeksMax: 5),
              now: () => DateTime(2026, 8, 28),
            ),
          ),
        ),
      );

      expect(find.text('Sep 18 – Oct 2'), findsOneWidget);
      expect(find.text('Standard gtradea.com Logistics'), findsOneWidget);
    });

    testWidgets('says nothing when the guarantee is switched off', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: LogisticsTrustCard(
              guarantee: DeliveryGuarantee(enabled: false),
            ),
          ),
        ),
      );

      expect(find.textContaining('Guaranteed delivery'), findsNothing);
    });

    testWidgets('the info control explains what the dates are counted from', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LogisticsTrustCard(
              guarantee: const DeliveryGuarantee(weeksMin: 3, weeksMax: 5),
              now: () => DateTime(2026, 8, 28),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      // The caveat that matters: counted from today, not from dispatch.
      expect(find.textContaining('3 to 5 weeks'), findsOneWidget);
      expect(find.textContaining('from today'), findsOneWidget);
    });
  });

  group('the guarantees strip', () {
    testWidgets('takes the page own measure, like the card above it', (
      tester,
    ) async {
      // A flat 16 left it inset further than the product card, and two blocks
      // starting at different margins read as a mistake.
      for (final width in [360.0, 412.0]) {
        tester.view.physicalSize = Size(width * 3, 2600);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: LogisticsTrustCard(assurances: storeAssurances),
            ),
          ),
        );
        await tester.pump();

        final strip = tester.getRect(
          find
              .descendant(
                of: find.byType(LogisticsTrustCard),
                matching: find.byType(Container),
              )
              .first,
        );

        final margin = width * (1 - PageWidth.factor) / 2;
        expect(strip.left, closeTo(margin, 0.5), reason: '${width}dp');
        expect(width - strip.right, closeTo(margin, 0.5), reason: '${width}dp');
        expect(
          strip.width,
          closeTo(width * PageWidth.factor, 1),
          reason: '97% at ${width}dp',
        );
      }
    });

    testWidgets('and stands tall enough not to feel cramped', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 2600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: LogisticsTrustCard(assurances: storeAssurances)),
        ),
      );
      await tester.pump();

      final strip = tester.getSize(
        find
            .descendant(
              of: find.byType(LogisticsTrustCard),
              matching: find.byType(Container),
            )
            .first,
      );

      // Its own cell padding, top and bottom, around a single line of label.
      expect(strip.height, greaterThanOrEqualTo(56));
    });
  });

  group('on the product page', () {
    testWidgets('replaces the card that named a city nobody chose', (
      tester,
    ) async {
      await _pumpPage(tester);

      expect(find.byType(LogisticsTrustCard), findsOneWidget);
      // The old card was hardcoded to Lalitpur and its Change button was wired
      // to an empty callback.
      expect(find.text('Deliver to Lalitpur'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Change'), findsNothing);
    });

    testWidgets('draws nothing at all when the settings cannot be read', (
      tester,
    ) async {
      // A delivery promise the app could not fetch is one it should not be
      // inventing.
      api.on('GET', '/site-settings', status: 500, body: {'message': 'down'});
      StorefrontConfigRepository.instance.resetForTest();

      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProductDetailScreen(
            product: sampleProduct,
            detail: sampleDetail,
          ),
        ),
      );
      // Pumped rather than settled: the gallery's photographs rotate on a
      // timer, so this page never comes to rest.
      await tester.pump(const Duration(milliseconds: 300));

      // The guarantees still stand -- they are the shop's own terms, not a
      // setting -- but no window is drawn, which is the promise it could not
      // fetch.
      expect(find.textContaining('Guaranteed delivery'), findsNothing);
      // The delivery options in the product card say they could not be read
      // rather than naming a way of shipping nobody published.
      expect(find.textContaining('unavailable just now'), findsOneWidget);
      expect(find.textContaining('days'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the logistics and trust block', () {
    /// The card on its own, so the assertions are about it rather than about
    /// where the page happens to have scrolled to.
    Future<void> pumpCard(
      WidgetTester tester, {
      DeliveryGuarantee? guarantee = const DeliveryGuarantee(
        weeksMin: 3,
        weeksMax: 5,
      ),
    }) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LogisticsTrustCard(
              guarantee: guarantee,
              assurances: storeAssurances,
              now: () => DateTime(2026, 8, 28),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is one card: the window and the guarantees together', (
      tester,
    ) async {
      await pumpCard(tester);

      expect(find.byType(LogisticsTrustCard), findsOneWidget);
      expect(find.text('Standard gtradea.com Logistics'), findsOneWidget);
      expect(find.text('Sep 18 – Oct 2'), findsOneWidget);
      expect(find.text('7-day returns'), findsOneWidget);
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(find.text('Quality checked'), findsOneWidget);
    });

    testWidgets('with the truck beside the window, both in the brand blue', (
      tester,
    ) async {
      await pumpCard(tester);

      final truck = find.byIcon(Icons.local_shipping_outlined);
      expect(truck, findsOneWidget);
      expect(tester.widget<Icon>(truck).color, AppColors.trustBlue);

      final dates = tester.widget<Text>(find.text('Sep 18 – Oct 2'));
      expect(dates.style?.color, AppColors.trustBlue);
      expect(dates.style?.fontSize, 13);
      expect(dates.style?.fontWeight, FontWeight.w600);

      // Beside, not above: the courier's mark stands to the left of the
      // two lines it heads, and level with the pair of them.
      final iconBox = tester.getRect(truck);
      final titleBox = tester.getRect(
        find.text('Standard gtradea.com Logistics'),
      );
      final dateBox = tester.getRect(find.text('Sep 18 – Oct 2'));
      expect(iconBox.right, lessThanOrEqualTo(titleBox.left));
      expect(iconBox.right, lessThanOrEqualTo(dateBox.left));
      expect(
        iconBox.center.dy,
        closeTo((titleBox.top + dateBox.bottom) / 2, 6),
      );

      // And the card itself opens the same note, which is what the
      // chevron at its right promises.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('and the three guarantees in equal thirds', (tester) async {
      await pumpCard(tester);

      final cells = [
        for (final label in [
          '7-day returns',
          'Cash on delivery',
          'Quality checked',
        ])
          tester.getRect(find.text(label)),
      ];
      for (final cell in cells.skip(1)) {
        expect(cell.top, closeTo(cells.first.top, 0.5), reason: 'level');
      }
      final firstGap = cells[1].center.dx - cells[0].center.dx;
      final secondGap = cells[2].center.dx - cells[1].center.dx;
      expect(secondGap, closeTo(firstGap, 1));
    });

    testWidgets('the guarantees stand even with no window to promise', (
      tester,
    ) async {
      // The shop's own terms are not a site setting, so a settings failure
      // takes the window away and leaves the promises.
      await pumpCard(tester, guarantee: null);

      expect(find.textContaining('Guaranteed delivery'), findsNothing);
      expect(find.text('7-day returns'), findsOneWidget);
      expect(find.text('Quality checked'), findsOneWidget);
    });

    testWidgets('and a guarantee still opens its terms', (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text('Cash on delivery'));
      await tester.pumpAndSettle();

      // The row's own label, and the sheet's heading above the terms.
      expect(find.text('Cash on delivery'), findsNWidgets(2));
      expect(find.textContaining('Pay the courier'), findsOneWidget);
    });
  });
}

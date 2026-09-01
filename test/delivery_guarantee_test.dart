import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/storefront_config.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/delivery_guarantee_card.dart';

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
    find.byType(DeliveryGuaranteeCard),
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
            body: DeliveryGuaranteeCard(
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
            body: DeliveryGuaranteeCard(
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
            body: DeliveryGuaranteeCard(
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

  group('on the product page', () {
    testWidgets('replaces the card that named a city nobody chose', (
      tester,
    ) async {
      await _pumpPage(tester);

      expect(find.byType(DeliveryGuaranteeCard), findsOneWidget);
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

      expect(find.byType(DeliveryGuaranteeCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

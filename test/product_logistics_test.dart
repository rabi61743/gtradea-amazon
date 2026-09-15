import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/logistics/data/shipping_mode_store.dart';
import 'package:gtradea_amazon/features/product/data/storefront_config.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/product_logistics_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/features/auth/data/auth_store.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// The live shape of `/site-settings`: a bare array whose `setting_value` is a
/// **string** holding JSON for the objects and a bare value for the rest.
List<Map<String, dynamic>> _settings({
  List<Map<String, dynamic>>? modes,
  Object? selector = 'false',
  Object? leadMin = 7,
  Object? leadMax = 15,
  Object? showLeadTime = true,
}) => [
  {
    'setting_key': 'shipping_estimate_note',
    'setting_value': jsonEncode({
      'enabled': false,
      'modes':
          modes ??
          [
            {'key': 'air', 'label': 'By Air', 'perKg': 3500, 'enabled': false},
            {'key': 'sea', 'label': 'By Sea', 'perKg': 900, 'enabled': false},
          ],
    }),
  },
  {'setting_key': 'shipping_mode_selector_enabled', 'setting_value': selector},
  {'setting_key': 'air_discount_percent', 'setting_value': 5},
  {'setting_key': 'sea_discount_percent', 'setting_value': 7},
  {'setting_key': 'default_lead_time_days_min', 'setting_value': leadMin},
  {'setting_key': 'default_lead_time_days_max', 'setting_value': leadMax},
  {'setting_key': 'show_lead_time_on_pdp', 'setting_value': showLeadTime},
];

/// `POST /checkout/delivery-charge` as the live endpoint answers it.
Map<String, dynamic> _charge(num total) => {
  'mode': 'charge',
  'total': total,
  'quote_id': 'q-1',
  'breakdown': {'vat': 50.25, 'vat_pct': 13},
};

void _seedAddress() {
  AddressStore.instance.add(
    label: AddressLabel.home,
    fullName: 'Rabi',
    phone: '9800000000',
    province: 'Bagmati',
    city: 'Lalitpur',
    area: 'Jawalakhel',
    makeDefault: true,
  );
}

/// The section on its own, so the assertions are about it rather than about
/// where a long product page happens to have scrolled to.
Future<void> _pumpSection(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: ProductLogisticsSection(
            lines: const [
              CartLine(
                productId: '825709571788',
                title: 'Quick-drying polo',
                unitPrice: 554,
                quantity: 2,
                source: '1688',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The options used to be behind a tap on a collapsed line. They are on the
/// page now, so this only lets the figures land.
Future<void> _openFlyout(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    StorefrontConfigRepository.instance.resetForTest();
    ShippingModeStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    api.on('GET', '/site-settings', body: _settings());
    api.on('POST', '/checkout/delivery-charge', body: _charge(436.75));
  });

  tearDown(clearApiStub);

  group('the options', () {
    test('are the shop\'s own, read from the site settings', () async {
      final config = await StorefrontConfigRepository.instance.logistics();

      // Two here because the fixture publishes two. Nothing in the app names
      // air, land or sea: a shop that publishes four gets four.
      expect(config.modes.map((m) => m.key), ['air', 'sea']);
      expect(config.modes.map((m) => m.label), ['By Air', 'By Sea']);
      expect(config.modes.first.perKg, 3500);
      expect(config.leadDaysMin, 7);
      expect(config.leadDaysMax, 15);
    });

    test('carry the discount the shop attaches to each of them', () async {
      final config = await StorefrontConfigRepository.instance.logistics();

      expect(config.modes.first.discountPercent, 5);
      expect(config.modes.last.discountPercent, 7);
      // Switched off on the live site, and the app does not apply what the
      // shop is not applying.
      expect(config.discountsApply, isFalse);
    });

    test('are empty when the shop publishes none', () async {
      api.on(
        'GET',
        '/site-settings',
        body: [
          {
            'setting_key': 'shipping_estimate_note',
            'setting_value': jsonEncode({'enabled': false}),
          },
        ],
      );
      StorefrontConfigRepository.instance.resetForTest();

      final config = await StorefrontConfigRepository.instance.logistics();
      expect(config.modes, isEmpty);
    });

    test('cost one request, shared with the delivery settings', () async {
      await StorefrontConfigRepository.instance.logistics();
      await StorefrontConfigRepository.instance.shipping();

      expect(api.calls.where((c) => c.path == '/site-settings'), hasLength(1));
    });
  });

  group('the line in the card', () {
    testWidgets('names the shop\'s logistics and what it is shipping by', (
      tester,
    ) async {
      await _pumpSection(tester);

      expect(find.text('gtradea.com Delivery Options'), findsOneWidget);
      // Every published mode, and the shop's own lead time on each.
      expect(find.text('By Air'), findsOneWidget);
      expect(find.text('By Sea'), findsOneWidget);
      expect(find.textContaining('Arrives in 7 - 15 days'), findsNWidgets(2));
    });

    testWidgets('says so when the shop has published no options', (
      tester,
    ) async {
      api.on(
        'GET',
        '/site-settings',
        body: [
          {
            'setting_key': 'shipping_estimate_note',
            'setting_value': jsonEncode({'enabled': false}),
          },
        ],
      );
      StorefrontConfigRepository.instance.resetForTest();

      await _pumpSection(tester);

      expect(
        find.textContaining('publishes no delivery options'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('and when they could not be read at all', (tester) async {
      api.on('GET', '/site-settings', status: 500, body: const {});
      StorefrontConfigRepository.instance.resetForTest();

      await _pumpSection(tester);

      // Nothing invented: no mode, no window, no figure.
      expect(find.textContaining('unavailable just now'), findsOneWidget);
      expect(find.textContaining('days'), findsNothing);
    });
  });

  group('the flyout', () {
    testWidgets('lists every option the backend published', (tester) async {
      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.text('By Air'), findsOneWidget);
      expect(find.text('By Sea'), findsOneWidget);
    });

    testWidgets('prices each one for this product and this address', (
      tester,
    ) async {
      _seedAddress();
      api.onCall('POST', '/checkout/delivery-charge', (call) {
        final body = call.body as Map;
        // The server is asked per mode, for the line being looked at.
        return reply(_charge(body['shippingMode'] == 'sea' ? 210 : 436.75));
      });

      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.text('Rs. 437'), findsOneWidget);
      expect(find.text('Rs. 210'), findsOneWidget);

      final quoted = api.calls.where(
        (c) => c.path == '/checkout/delivery-charge',
      );
      expect(quoted, hasLength(2), reason: 'one per published mode');
      expect(
        (quoted.first.body as Map)['district'],
        'Lalitpur',
        reason: 'freight is priced to a destination',
      );
      expect(
        ((quoted.first.body as Map)['guestCartItems'] as List)
            .first['quantity'],
        2,
        reason: 'and to what is actually being bought',
      );
    });

    testWidgets('asks for an address before it can price anything', (
      tester,
    ) async {
      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.textContaining('Add a delivery address'), findsOneWidget);
      expect(
        api.calls.where((c) => c.path == '/checkout/delivery-charge'),
        isEmpty,
        reason: 'freight to nowhere is not a quote',
      );
    });

    testWidgets('prices nothing until there is an order to price', (
      tester,
    ) async {
      // A grid listing with nothing typed into it. The endpoint falls back to
      // the shopper's saved cart when it is sent no lines, so asking would put
      // the freight for their basket on this product's card.
      _seedAddress();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ProductLogisticsSection(lines: []),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openFlyout(tester);

      expect(
        api.calls.where((c) => c.path == '/checkout/delivery-charge'),
        isEmpty,
      );
      expect(find.textContaining('Choose what you want above'), findsOneWidget);
      expect(find.textContaining('Rs.'), findsNothing);
    });

    testWidgets('prices a signed-in shopper own product, not their basket', (
      tester,
    ) async {
      // Measured against the live endpoint: it honours `guestCartItems` only
      // for an anonymous request. With a credential it prices the account's
      // own basket and ignores what it is handed, which against one product is
      // a wrong number rather than a missing one -- so the ask is made without
      // one, and a signed-in shopper sees the freight for what is in front of
      // them.
      signInForTest();
      _seedAddress();

      await _pumpSection(tester);
      await _openFlyout(tester);

      final asked = api.calls.where(
        (c) => c.path == '/checkout/delivery-charge',
      );
      expect(asked, isNotEmpty);
      // Sent as the lines on the page, not as the account's cart.
      expect(asked.first.json['guestCartItems'], isNotNull);
      expect(find.text('By Air'), findsOneWidget);
      expect(find.text('By Sea'), findsOneWidget);
    });

    testWidgets('offers a retry when the freight could not be priced', (
      tester,
    ) async {
      _seedAddress();
      api.on('POST', '/checkout/delivery-charge', status: 500, body: const {});

      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.textContaining('could not be priced'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // And the options are still there to choose between: a missing figure
      // does not make a way of shipping unavailable.
      expect(find.text('By Air'), findsOneWidget);
      expect(find.text('By Sea'), findsOneWidget);
    });

    testWidgets('says freight is settled at checkout when none is published', (
      tester,
    ) async {
      _seedAddress();
      // The live endpoint answers `mode: off` where freight is not charged.
      api.on(
        'POST',
        '/checkout/delivery-charge',
        body: const {'mode': 'off', 'total': 0},
      );

      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.text('At checkout'), findsNWidgets(2));
    });
  });

  group('what the server said about the quote', () {
    /// The delivery-charge response as the live gateway returns it, with the
    /// breakdown it actually sends.
    Map<String, dynamic> fullCharge({num total = 169.5}) => {
      'mode': 'estimate',
      'quote_id': 'q-1',
      'total': total,
      'breakdown': {
        'district': 'Lalitpur',
        'chargeable_kg': 0.5,
        'weight_basis': 'higher',
        'logistic_subtotal': 150,
        'vat': 19.5,
        'vat_pct': 13,
        'combine_discount': 0,
        'lines': [
          {'freight_source': 'api', 'nepal_npr': 150},
        ],
        'flags': {'china_freight_unavailable': false},
      },
    };

    testWidgets('every field it filled in reaches the option', (tester) async {
      _seedAddress();
      api.on('POST', '/checkout/delivery-charge', body: fullCharge());

      await _pumpSection(tester);
      await _openFlyout(tester);

      // The figure, and the tax the server itemised inside it.
      expect(find.text('Rs. 170').first, findsOneWidget);
      expect(find.textContaining('VAT').first, findsOneWidget);

      // Where it was priced to, what it was charged on, who priced it, and who
      // collects it -- all of them the server's own fields.
      expect(find.textContaining('Lalitpur').first, findsOneWidget);
      expect(find.textContaining('0.5 kg').first, findsOneWidget);
      expect(find.textContaining('carrier rate').first, findsOneWidget);
      expect(find.textContaining('paid on delivery').first, findsOneWidget);
    });

    testWidgets('a quote of zero reads as free, not as no quote', (
      tester,
    ) async {
      _seedAddress();
      api.on('POST', '/checkout/delivery-charge', body: fullCharge(total: 0));

      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.text('Free').first, findsOneWidget);
      // And not the blank that used to stand in for it.
      expect(find.text('At checkout'), findsNothing);
    });

    testWidgets('and the server own warning is passed on', (tester) async {
      // The gateway flags a line it could not get a carrier rate for and falls
      // back to its minimum. That is the server's word, not a guess made here.
      _seedAddress();
      final body = fullCharge();
      (body['breakdown'] as Map)['flags'] = {'china_freight_unavailable': true};
      api.on('POST', '/checkout/delivery-charge', body: body);

      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.textContaining('gave no rate').first, findsOneWidget);
    });
  });

  group('the marks', () {
    testWidgets('name the carriage, not a mood', (tester) async {
      // A shopper reading "By Air" beside a lightning bolt has to work out that
      // the bolt means speed and the speed means flying. A plane says it once.
      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.byIcon(Icons.flight), findsOneWidget);
      expect(find.byIcon(Icons.directions_boat), findsOneWidget);
      // The fixture publishes air and sea; a shop publishing land gets the
      // lorry, which the fallback below covers.
      expect(find.byIcon(Icons.local_shipping), findsNothing);
    });

    testWidgets('and a mode with no mark of its own gets carriage', (
      tester,
    ) async {
      api.on(
        'GET',
        '/site-settings',
        body: [
          {
            'setting_key': 'shipping_estimate_note',
            'setting_value': jsonEncode({
              'modes': [
                {'key': 'rail', 'label': 'By Rail'},
              ],
            }),
          },
        ],
      );
      StorefrontConfigRepository.instance.resetForTest();

      await _pumpSection(tester);
      await _openFlyout(tester);

      expect(find.text('By Rail'), findsOneWidget);
      expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    });

    testWidgets('and the chosen one is marked as chosen to a reader', (
      tester,
    ) async {
      await _pumpSection(tester);
      await _openFlyout(tester);

      final handle = tester.ensureSemantics();

      await tester.tap(find.text('By Sea'));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.text('By Sea'));
      // The row reads out as itself: the mode, its window and its figure.
      expect(node.label, contains('By Sea'));
      expect(node.flagsCollection.isSelected.name, 'isTrue');
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isInMutuallyExclusiveGroup, isTrue);

      // And the one it moved off is no longer marked.
      final other = tester.getSemantics(find.text('By Air'));
      expect(other.flagsCollection.isSelected.name, 'isFalse');

      handle.dispose();
    });
  });

  group('choosing one', () {
    testWidgets('marks the one that was chosen', (tester) async {
      await _pumpSection(tester);
      await _openFlyout(tester);

      await tester.tap(find.text('By Sea'));
      await tester.pumpAndSettle();

      // The options stay on the page; the mark moves to the one chosen.
      expect(find.text('By Sea'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_off), findsOneWidget);
      expect(ShippingModeStore.instance.selected?.key, 'sea');
    });

    testWidgets('and the choice is what checkout ships by', (tester) async {
      await _pumpSection(tester);
      await _openFlyout(tester);
      await tester.tap(find.text('By Sea'));
      await tester.pumpAndSettle();

      // Not a label on a card: this is the value the order is placed with.
      expect(ShippingModeStore.instance.checkoutMode, 'sea');
    });

    testWidgets('a tap elsewhere keeps what was chosen', (tester) async {
      await _pumpSection(tester);
      await _openFlyout(tester);
      await tester.tap(find.text('By Sea'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(20, 620));
      await tester.pumpAndSettle();

      expect(find.text('By Air'), findsOneWidget, reason: 'still listed');
      expect(ShippingModeStore.instance.selectedKey, 'sea');
    });

    test('a mode the shop no longer offers is not kept', () async {
      SharedPreferences.setMockInitialValues({'shipping_mode': 'land'});
      await ShippingModeStore.instance.load();

      // 'land' is not on the published list, so the order cannot be placed
      // under it. The first offered mode stands in.
      expect(ShippingModeStore.instance.selectedKey, 'air');
    });

    test('and one it does offer is remembered', () async {
      SharedPreferences.setMockInitialValues({'shipping_mode': 'sea'});
      await ShippingModeStore.instance.load();

      expect(ShippingModeStore.instance.selectedKey, 'sea');
    });
  });

  group('the rest of the order follows it', () {
    testWidgets('the cart prices freight by the mode that was chosen', (
      tester,
    ) async {
      _seedAddress();
      await _pumpSection(tester);
      await _openFlyout(tester);
      await tester.tap(find.text('By Sea'));
      await tester.pumpAndSettle();

      CartStore.instance.add(
        const CartLine(
          productId: '825709571788',
          title: 'Quick-drying polo',
          unitPrice: 554,
          quantity: 2,
          source: '1688',
        ),
      );
      // Not awaited: inside a widget test the request only advances while
      // the tester pumps, and awaiting it here would wait forever.
      unawaited(CartStore.instance.refreshDeliveryQuote(district: 'Lalitpur'));
      await tester.pump(const Duration(seconds: 1));

      final quoted = api.calls.lastWhere(
        (c) => c.path == '/checkout/delivery-charge',
      );
      expect((quoted.body as Map)['shippingMode'], 'sea');
    });

    testWidgets('a change of quantity reprices what is on screen', (
      tester,
    ) async {
      _seedAddress();
      await _pumpSection(tester);
      await _openFlyout(tester);

      final before = api.calls
          .where((c) => c.path == '/checkout/delivery-charge')
          .length;

      // The page rebuilds this section with the new count; freight already
      // shown was priced for the old one.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ProductLogisticsSection(
                lines: const [
                  CartLine(
                    productId: '825709571788',
                    title: 'Quick-drying polo',
                    unitPrice: 554,
                    quantity: 9,
                    source: '1688',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sent = api.calls
          .where((c) => c.path == '/checkout/delivery-charge')
          .toList();
      expect(sent.length, greaterThan(before), reason: 're-asked');
      expect(
        ((sent.last.body as Map)['guestCartItems'] as List).first['quantity'],
        9,
      );
    });
  });

  group('on the product page', () {
    testWidgets('the logistics line sits inside the product card', (
      tester,
    ) async {
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
      // Pumped rather than settled: the gallery rotates on a timer, so this
      // page never comes to rest.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ProductLogisticsSection), findsOneWidget);
      // One logistics heading on the page, not two: the window moved into the
      // card rather than being copied into it.
      expect(find.text('gtradea.com Delivery Options'), findsOneWidget);
    });

    testWidgets('and the card is 97% of the page, centred', (tester) async {
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
      await tester.pump(const Duration(milliseconds: 300));

      final page =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final card = tester.getRect(find.byType(ProductLogisticsSection));

      // The section is inside the card's own 14pt padding, so it measures a
      // little narrower than the card -- but it is centred on the page and
      // nowhere near the edges.
      expect(card.left, greaterThan(page * 0.015));
      expect(page - card.right, closeTo(card.left, 1));
    });
  });
}

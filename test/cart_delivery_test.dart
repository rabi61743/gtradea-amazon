import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/promo/data/coupon_store.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

late FakeApi api;

const _dress = CartLine(
  productId: 'dress',
  title: 'Suspender dress',
  unitPrice: 1808,
);

/// The shape `/checkout/delivery-charge` actually answers with, measured live:
/// a top-level mode and total, and a breakdown the freight is derived from.
Map<String, dynamic> quote({num total = 551.18, String mode = 'charge'}) => {
  'mode': mode,
  'total': total,
  'quote_id': 'q-1',
  'breakdown': {
    'mode': mode,
    'logistic_subtotal': total,
    'chargeable_kg': 2.352,
    'vat': 63,
    'vat_pct': 13,
  },
};

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const CartScreen()),
  );
  await tester.pumpAndSettle();
}

void _withAddress() => AddressStore.instance.add(
  label: AddressLabel.home,
  fullName: 'Rabi Yadav',
  phone: '9800000000',
  province: 'Bagmati',
  city: 'Lalitpur',
  area: 'Jhamsikhel',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    CouponStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
  });

  group('the delivery fee comes from the server', () {
    testWidgets('the cart asks for a quote and shows what came back', (
      tester,
    ) async {
      // The figure is the server's freight calculation for this basket and this
      // district -- not a flat fee held in the app. Rs. 100 used to be added to
      // every order regardless of what was in it.
      _withAddress();
      api.on('POST', '/checkout/delivery-charge', body: quote());
      CartStore.instance.add(_dress);

      await _pump(tester);

      final sent = api.calls.lastWhere(
        (c) => c.path == '/checkout/delivery-charge',
      );
      expect(sent.json['district'], 'Lalitpur');
      expect(find.text('Rs. 551'), findsWidgets);
    });

    testWidgets('the basket it is quoting for is sent, not just a total', (
      tester,
    ) async {
      // Freight is priced on weight and volume, which the server looks up from
      // the upstream catalogue id. A quote asked without the items would be a
      // quote for nothing.
      _withAddress();
      api.on('POST', '/checkout/delivery-charge', body: quote());
      CartStore.instance.add(_dress);

      await _pump(tester);

      final sent = api.calls.lastWhere(
        (c) => c.path == '/checkout/delivery-charge',
      );
      final items = sent.json['guestCartItems'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['quantity'], 1);
    });

    testWidgets('with no address there is nothing to quote against', (
      tester,
    ) async {
      // Freight is priced to a destination. Without one the cart says the
      // charge is worked out at checkout rather than inventing a figure.
      CartStore.instance.add(_dress);

      await _pump(tester);

      expect(
        api.calls.where((c) => c.path == '/checkout/delivery-charge'),
        isEmpty,
      );
      expect(find.text('Calculated at checkout'), findsOneWidget);
    });

    testWidgets('a shop with freight pricing off shows no charge', (
      tester,
    ) async {
      // mode 'off' means this storefront does not price freight here at all.
      // The quote parser returns null for it, and the cart must not print a
      // zero as though delivery were free.
      _withAddress();
      api.on(
        'POST',
        '/checkout/delivery-charge',
        body: quote(mode: 'off', total: 0),
      );
      CartStore.instance.add(_dress);

      await _pump(tester);

      expect(find.text('Free'), findsNothing);
      expect(find.text('Calculated at checkout'), findsOneWidget);
    });

    testWidgets('a failed quote is not turned into a number', (tester) async {
      _withAddress();
      api.on(
        'POST',
        '/checkout/delivery-charge',
        status: 500,
        body: const {'message': 'no'},
      );
      CartStore.instance.add(_dress);

      await _pump(tester);

      expect(find.text('Calculated at checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

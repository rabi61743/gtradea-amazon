import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/audio/app_sound.dart';
import 'package:gtradea_amazon/core/audio/app_sounds.dart';
import 'package:gtradea_amazon/core/audio/sound_settings.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/checkout/presentation/checkout_screen.dart';
import 'package:gtradea_amazon/features/legal/data/legal_page_repository.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

late FakeApi api;

const _line = CartLine(
  productId: 'p1',
  title: 'Ice silk jacket',
  unitPrice: 1130,
  quantity: 2,
);

Widget _wrap() => MaterialApp(
  theme: AppTheme.light,
  home: CheckoutScreen(
    lines: const [_line],
    totals: CartTotals.of(const [_line]),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap());
  await tester.pumpAndSettle();
}

/// Ticks the terms box and presses the order button.
Future<void> _placeOrder(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ElevatedButton).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
    LegalPageRepository.instance.resetForTest();
    SoundSettings.instance.resetForTest();
    AppSound.enabled = true;
    for (final sound in [
      AppSounds.orderConfirmed,
      AppSounds.paymentSuccessful,
      AppSounds.paymentFailed,
      AppSounds.removed,
      AppSounds.addToCart,
    ]) {
      await sound.resetForTest();
    }

    api.on(
      'GET',
      '/pages/terms',
      body: {
        'id': 'p',
        'slug': 'terms',
        'title': 'Terms of Service',
        'content': '<h2>Terms</h2>',
      },
    );
    api.on('GET', '/orders', body: const []);
    // Cash on delivery, so an order completes without a gateway or a WebView.
    api.on(
      'GET',
      '/site-settings/active_payment_methods',
      body: const {
        'setting_value': {
          'cod': {
            'label': 'Cash on Delivery',
            'order': 1,
            'enabled': true,
            'isDefault': true,
          },
        },
      },
    );

    // An order needs a signed-in shopper, somewhere to deliver to, and a
    // number for the courier. The address carries the phone.
    signInForTest();
    ApiClient.overrideDio = api.dio();
    AddressStore.instance.add(
      label: AddressLabel.home,
      fullName: 'Rabi Yadav',
      phone: '9800000000',
      province: 'Bagmati',
      city: 'Lalitpur',
      area: 'Jhamsikhel, house 12',
      makeDefault: true,
    );
  });

  tearDown(() {
    AppSound.enabled = true;
    SoundSettings.instance.resetForTest();
  });

  group('a cash-on-delivery order', () {
    testWidgets('sounds once the server has given it a number', (tester) async {
      api.on(
        'POST',
        '/checkout',
        body: const {'orderId': 'order-1', 'orderNumber': 'GT-1001'},
      );

      await _pump(tester);
      await _placeOrder(tester);

      expect(AppSounds.orderConfirmed.plays, 1);
    });

    testWidgets('and no payment sound, because nothing was paid', (
      tester,
    ) async {
      api.on(
        'POST',
        '/checkout',
        body: const {'orderId': 'order-1', 'orderNumber': 'GT-1001'},
      );

      await _pump(tester);
      await _placeOrder(tester);

      expect(AppSounds.paymentSuccessful.plays, 0);
      expect(AppSounds.paymentFailed.plays, 0);
    });

    testWidgets('the cart being emptied is not a burst of delete sounds', (
      tester,
    ) async {
      // Checkout drops the ordered rows from the cart. That is the app tidying
      // up, not the shopper deleting anything.
      api.on(
        'POST',
        '/checkout',
        body: const {'orderId': 'order-1', 'orderNumber': 'GT-1001'},
      );

      await _pump(tester);
      await _placeOrder(tester);

      expect(AppSounds.removed.plays, 0);
    });
  });

  group('an order that fails', () {
    testWidgets('is silent -- the sound follows the server, not the tap', (
      tester,
    ) async {
      api.on('POST', '/checkout', status: 500, body: const {});

      await _pump(tester);
      await _placeOrder(tester);

      expect(AppSounds.orderConfirmed.plays, 0);
      expect(AppSounds.paymentSuccessful.plays, 0);
    });

    testWidgets('and so is one the server refuses in a 200', (tester) async {
      // Checkout's second failure convention: HTTP 200 carrying success:false.
      api.on(
        'POST',
        '/checkout',
        body: const {'success': false, 'message': 'Out of stock'},
      );

      await _pump(tester);
      await _placeOrder(tester);

      expect(AppSounds.orderConfirmed.plays, 0);
    });
  });

  group('with sound switched off', () {
    testWidgets('a confirmed order is silent, and still placed', (
      tester,
    ) async {
      await SoundSettings.instance.setEnabled(false);
      api.on(
        'POST',
        '/checkout',
        body: const {'orderId': 'order-1', 'orderNumber': 'GT-1001'},
      );

      await _pump(tester);
      await _placeOrder(tester);

      expect(AppSounds.orderConfirmed.plays, 0);
      expect(
        api.calls.where((call) => call.path == '/checkout'),
        isNotEmpty,
        reason: 'the order still went out',
      );
    });
  });
}

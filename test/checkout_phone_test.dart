import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/checkout/data/checkout_models.dart';
import 'package:gtradea_amazon/features/checkout/presentation/checkout_screen.dart';
import 'package:gtradea_amazon/features/legal/data/legal_page_repository.dart';
import 'package:gtradea_amazon/features/profile/data/profile.dart';
import 'package:gtradea_amazon/features/profile/data/profile_store.dart';

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

/// Cash on delivery, so an order completes without a gateway or a WebView.
Map<String, dynamic> get _cod => {
  'setting_value': {
    'cod': {
      'label': 'Cash on Delivery',
      'order': 1,
      'enabled': true,
      'isDefault': true,
    },
  },
};

Address _saveAddress({String phone = ''}) => AddressStore.instance.add(
  label: AddressLabel.home,
  fullName: 'Rabi Yadav',
  phone: phone,
  province: 'Bagmati',
  city: 'Lalitpur',
  area: 'Baghdol',
  makeDefault: true,
);

Widget _wrap() => MaterialApp(
  theme: AppTheme.light,
  home: CheckoutScreen(
    lines: const [_line],
    totals: CartTotals.of(const [_line]),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap());
  await tester.pumpAndSettle();
}

Finder get _field => find.widgetWithText(TextField, 'Phone number');

String _typed(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

/// Everything a cash-on-delivery order needs except the number.
Future<void> _readyToOrder(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox).first);
  await tester.pumpAndSettle();
}

Future<void> _placeOrder(WidgetTester tester) async {
  final button = find.textContaining('Place order');
  await tester.ensureVisible(button.first);
  await tester.pumpAndSettle();
  await tester.tap(button.first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
    ProfileStore.instance.resetForTest();
    LegalPageRepository.instance.resetForTest();
    api
      ..on('GET', '/site-settings/active_payment_methods', body: _cod)
      ..on(
        'GET',
        '/pages/terms',
        body: {'title': 'Terms', 'content': '<p>x</p>'},
      )
      ..on(
        'POST',
        '/checkout',
        body: const {'orderId': 'order-1', 'orderNumber': 'GT-1001'},
      )
      ..on('GET', '/orders', body: const [])
      ..on(
        'PATCH',
        '/profile',
        body: const {'id': 'u1', 'phone': '9800000001'},
      );
  });

  tearDown(clearApiStub);

  group('the number the courier rings', () {
    testWidgets('is asked for in the delivery section', (tester) async {
      _saveAddress();
      await _pump(tester);

      expect(_field, findsOneWidget);

      // In "Deliver to", above the billing section -- not floated to the
      // bottom of the page beside the payment methods.
      final delivery = tester.getTopLeft(find.text('Deliver to')).dy;
      final phone = tester.getTopLeft(_field).dy;
      final billing = tester.getTopLeft(find.text('Bill To')).dy;
      expect(phone, greaterThan(delivery));
      expect(phone, lessThan(billing));
    });

    testWidgets("and is filled from the address's own number", (tester) async {
      _saveAddress(phone: '9801234567');
      await _pump(tester);

      expect(_typed(tester), '9801234567');
    });

    testWidgets("or the account's, for an address saved without one", (
      tester,
    ) async {
      _saveAddress();
      signInForTest();
      ProfileStore.instance.seedForTest(
        const Profile(id: 'u1', firstName: 'Rabi', phone: '9807654321'),
      );

      await _pump(tester);

      expect(_typed(tester), '9807654321');
    });

    testWidgets('but never over a number the shopper typed', (tester) async {
      // The profile arrives after the screen is built, and switching address
      // reseeds: neither may overwrite what is being typed.
      _saveAddress();
      await _pump(tester);

      await tester.enterText(_field, '9812223344');
      await tester.pumpAndSettle();

      signInForTest();
      ProfileStore.instance.seedForTest(
        const Profile(id: 'u1', firstName: 'Rabi', phone: '9807654321'),
      );
      await tester.pumpAndSettle();

      expect(_typed(tester), '9812223344');
    });
  });

  group('what it will accept', () {
    test('a complete Nepali mobile, however it is written', () {
      for (final good in [
        '9801234567',
        '+977 9801234567',
        '977-980-123-4567',
        '01-4412345',
      ]) {
        expect(CheckoutAddress.phoneProblem(good), isNull, reason: good);
      }
    });

    test('and not an incomplete one', () {
      expect(CheckoutAddress.phoneProblem(''), contains('Add a phone number'));
      expect(CheckoutAddress.phoneProblem('98012'), contains('10 digits'));
      expect(
        CheckoutAddress.phoneProblem('98012345678'),
        contains('10 digits'),
      );
      expect(
        CheckoutAddress.phoneProblem('12345'),
        contains('complete phone number'),
      );
    });
  });

  group('placing the order', () {
    testWidgets('stops, and says why, when the number is not usable', (
      tester,
    ) async {
      _saveAddress();
      await _pump(tester);

      await tester.enterText(_field, '98012');
      await _readyToOrder(tester);
      await _placeOrder(tester);

      expect(
        find.text('A mobile number is 10 digits, e.g. 9801234567.'),
        findsWidgets,
      );
      expect(
        api.calls.where((c) => c.path == '/checkout'),
        isEmpty,
        reason: 'nothing was ordered',
      );
    });

    testWidgets('and the error clears as soon as it is fixed', (tester) async {
      _saveAddress();
      await _pump(tester);

      await tester.enterText(_field, '98012');
      await _readyToOrder(tester);
      await _placeOrder(tester);

      await tester.enterText(_field, '9801234567');
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(_field).decoration?.errorText,
        isNull,
        reason: 'a form that keeps scolding a corrected field is broken',
      );
    });

    testWidgets('sends the number that was typed, not the saved one', (
      tester,
    ) async {
      _saveAddress(phone: '9800000000');
      signInForTest();
      await _pump(tester);

      await tester.enterText(_field, '9812223344');
      await _readyToOrder(tester);
      await _placeOrder(tester);

      final order = api.calls.firstWhere((c) => c.path == '/checkout');
      final shipping = order.json['shippingAddress'] as Map<String, dynamic>;
      // E.164, which is the form the courier system takes.
      expect(shipping['phone'], '+9779812223344');
    });

    testWidgets('and keeps it on the address for next time', (tester) async {
      _saveAddress(phone: '9800000000');
      signInForTest();
      await _pump(tester);

      await tester.enterText(_field, '9812223344');
      await _readyToOrder(tester);
      await _placeOrder(tester);

      expect(AddressStore.instance.addresses.single.phone, '9812223344');
    });

    testWidgets('filing it on an account that has none', (tester) async {
      _saveAddress();
      signInForTest();
      ProfileStore.instance.seedForTest(const Profile(id: 'u1'));
      await _pump(tester);

      await tester.enterText(_field, '9812223344');
      await _readyToOrder(tester);
      await _placeOrder(tester);

      final patch = api.calls.where((c) => c.path == '/profile').toList();
      expect(patch, hasLength(1));
      expect(patch.single.json['phone'], '9812223344');
    });

    testWidgets('but leaving an account that already has one alone', (
      tester,
    ) async {
      // A one-off number for one delivery is not a request to change the
      // number on the account.
      _saveAddress();
      signInForTest();
      ProfileStore.instance.seedForTest(
        const Profile(id: 'u1', phone: '9807654321'),
      );
      await _pump(tester);

      await tester.enterText(_field, '9812223344');
      await _readyToOrder(tester);
      await _placeOrder(tester);

      expect(api.calls.where((c) => c.path == '/profile'), isEmpty);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/home/widgets/product_rail.dart'
    show formatRupees;
import 'package:gtradea_amazon/features/checkout/presentation/checkout_screen.dart';
import 'package:gtradea_amazon/features/checkout/presentation/how_to_pay.dart';
import 'package:gtradea_amazon/features/legal/data/legal_page_repository.dart';
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

/// Cash on delivery, so a step can be completed without a gateway.
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

/// No default method, so "choose one" is a step with something to do.
Map<String, dynamic> get _twoMethods => {
  'setting_value': {
    'cod': {'label': 'Cash on Delivery', 'order': 1, 'enabled': true},
    'khalti': {'label': 'Khalti', 'order': 2, 'enabled': true},
  },
};

void _saveAddress({String phone = '9801234567'}) => AddressStore.instance.add(
  label: AddressLabel.home,
  fullName: 'Rabi Yadav',
  phone: phone,
  province: 'Bagmati',
  city: 'Lalitpur',
  area: 'Baghdol',
  makeDefault: true,
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: CheckoutScreen(
        lines: const [_line],
        totals: CartTotals.of(const [_line]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Anything inside the guide, and nothing outside it: "Payment" is also
/// the payment section's own heading.
Finder _inGuide(Finder matching) =>
    find.descendant(of: find.byType(HowToPay), matching: matching);

/// Which step the guide says the shopper is on, from what it prints.
int _step(WidgetTester tester) {
  final label = tester
      .widget<Text>(_inGuide(find.textContaining('Step ')).first)
      .data!;
  return int.parse(RegExp(r'Step (\d)').firstMatch(label)!.group(1)!);
}

/// How many steps the strip shows as done: one tick each.
int _done(WidgetTester tester) =>
    _inGuide(find.byIcon(Icons.check)).evaluate().length;

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
      ..on('GET', '/orders', body: const []);
  });

  tearDown(clearApiStub);

  group('the guide', () {
    testWidgets('names the four steps of the real checkout', (tester) async {
      _saveAddress();
      await _pump(tester);

      expect(find.byType(HowToPay), findsOneWidget);
      for (final label in ['Details', 'Method', 'Review', 'Confirm']) {
        expect(_inGuide(find.text(label)), findsOneWidget, reason: label);
      }
    });

    testWidgets('sits in the payment section, not above the address', (
      tester,
    ) async {
      _saveAddress();
      await _pump(tester);

      final address = tester.getTopLeft(find.text('Deliver to')).dy;
      final guide = tester.getTopLeft(find.byType(HowToPay)).dy;
      expect(guide, greaterThan(address));
    });

    testWidgets('opens to the wording, and starts closed', (tester) async {
      _saveAddress();
      await _pump(tester);

      // Closed: the strip alone, so the methods stay in reach.
      expect(find.textContaining('Delivery address, phone'), findsNothing);

      await tester.tap(find.text('How to pay'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delivery address, phone'), findsOneWidget);
      expect(find.textContaining('Agree the terms'), findsOneWidget);
      expect(find.text('Step 1 — Enter your details'), findsOneWidget);
    });
  });

  group('where it says the shopper is', () {
    testWidgets('on the details, while there is no address', (tester) async {
      await _pump(tester);

      expect(_step(tester), 1);
      expect(_done(tester), 0, reason: 'nothing supplied yet');
    });

    testWidgets('still on the details, when the phone is not usable', (
      tester,
    ) async {
      // An address alone is not enough: the shop refuses an order with no
      // number on it, so the step is not done until the number is real.
      _saveAddress(phone: '98012');
      await _pump(tester);

      expect(_step(tester), 1);
      expect(_done(tester), 0);
    });

    testWidgets('on choosing a method, when the shop offered none', (
      tester,
    ) async {
      // The methods could not be read, so there is nothing selected and
      // nothing to select: the step the shopper is stuck on is the second.
      api.on(
        'GET',
        '/site-settings/active_payment_methods',
        status: 500,
        body: const {'message': 'down'},
      );
      _saveAddress();
      await _pump(tester);

      expect(_step(tester), 2);
      expect(_done(tester), 1, reason: 'the details are in');
    });

    testWidgets('past it as soon as the shop names a method', (tester) async {
      // Two on offer and no default among them: the app selects the first
      // rather than leaving the shopper with nothing chosen.
      api.on('GET', '/site-settings/active_payment_methods', body: _twoMethods);
      _saveAddress();
      await _pump(tester);

      expect(_step(tester), 3);
      expect(_done(tester), 2, reason: 'details and a method');
    });

    testWidgets('on the review, once a method is chosen', (tester) async {
      // The shop's default method is picked for the shopper, so this order is
      // already past step two when the page opens.
      _saveAddress();
      await _pump(tester);

      expect(_step(tester), 3);
      expect(_done(tester), 2, reason: 'details and payment');
    });

    testWidgets('and on confirming, once the terms are accepted', (
      tester,
    ) async {
      _saveAddress();
      await _pump(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(_step(tester), 4);
      expect(_done(tester), 3, reason: 'everything but the payment');
    });

    testWidgets('a business with no company name is held at the review', (
      tester,
    ) async {
      // The same rule the button enforces, said out loud a step earlier.
      _saveAddress();
      await _pump(tester);

      await tester.tap(find.text('Business'));
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(_step(tester), 3);
      expect(_done(tester), 2, reason: 'the invoice has no name on it');
    });
  });

  group('what is required', () {
    testWidgets('is marked on the section that is outstanding', (tester) async {
      await _pump(tester);

      // No address and no phone, so the delivery section is marked. The
      // payment section is not: the shop named a default and the app took
      // it, which is the same rule the button reads.
      expect(find.text('Required'), findsOneWidget);
      final mark = tester.getTopLeft(find.text('Required')).dy;
      final billing = tester.getTopLeft(find.text('Bill To')).dy;
      expect(mark, lessThan(billing), reason: 'on Deliver to');
    });

    testWidgets('and on the payment section when nothing can be chosen', (
      tester,
    ) async {
      api.on(
        'GET',
        '/site-settings/active_payment_methods',
        status: 500,
        body: const {'message': 'down'},
      );
      _saveAddress();
      await _pump(tester);

      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('and the mark clears as each is supplied', (tester) async {
      _saveAddress();
      await _pump(tester);

      // Address, phone and the shop's default method are all in hand, so
      // neither section is outstanding.
      expect(find.text('Required'), findsNothing);
    });

    testWidgets('a marked requirement is one the button really enforces', (
      tester,
    ) async {
      // The proof that the marks are not decoration: with the phone missing,
      // the section is marked and the order is refused.
      _saveAddress(phone: '');
      await _pump(tester);

      expect(find.text('Required'), findsWidgets);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      final pay = find.textContaining('Place order');
      await tester.ensureVisible(pay.first);
      await tester.pumpAndSettle();
      await tester.tap(pay.first);
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path == '/checkout'),
        isEmpty,
        reason: 'the guide and the button agree',
      );
    });
  });

  group('the guide sheet', () {
    testWidgets('names every required field, marked with a star', (
      tester,
    ) async {
      _saveAddress();
      await _pump(tester);
      await tester.tap(find.text('How to pay'));
      await tester.pumpAndSettle();

      // findsWidgets, not one: the phone has a field of its own on the page
      // behind the sheet, which is the point of naming it here.
      for (final field in [
        'Full name',
        'Phone number',
        'Email address',
        'Delivery address',
      ]) {
        expect(find.textContaining(field), findsWidgets, reason: field);
      }
      // The address and the number this page really holds.
      expect(find.textContaining('Rabi Yadav'), findsWidgets);
      expect(find.textContaining('9801234567'), findsWidgets);
    });

    testWidgets('lists the methods the shop offered, and nothing else', (
      tester,
    ) async {
      api.on('GET', '/site-settings/active_payment_methods', body: _twoMethods);
      _saveAddress();
      await _pump(tester);
      await tester.tap(find.text('How to pay'));
      await tester.pumpAndSettle();

      expect(find.text('Cash on Delivery'), findsWidgets);
      expect(find.text('Khalti'), findsWidgets);
      // Nothing invented: a method the shop never named is not in the guide.
      expect(find.textContaining('PayPal'), findsNothing);
      expect(find.textContaining('Visa'), findsNothing);
    });

    testWidgets('shows the amount this order actually comes to', (
      tester,
    ) async {
      _saveAddress();
      await _pump(tester);
      await tester.tap(find.text('How to pay'));
      await tester.pumpAndSettle();

      expect(find.text('Order amount'), findsOneWidget);
      final total = CartTotals.of(const [_line]).total;
      expect(find.text(formatRupees(total)), findsWidgets);
    });

    testWidgets('and closes without touching the order', (tester) async {
      _saveAddress();
      await _pump(tester);
      await tester.tap(find.text('How to pay'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Order amount'), findsNothing);
      expect(
        api.calls.where((c) => c.path == '/checkout'),
        isEmpty,
        reason: 'reading is not ordering',
      );
    });
  });

  group('what it does not do', () {
    testWidgets('it neither pays nor claims anything about paying', (
      tester,
    ) async {
      signInForTest();
      _saveAddress();
      await _pump(tester);

      await tester.tap(find.text('How to pay'));
      await tester.pumpAndSettle();

      // No invented outcome anywhere in it: the shop says whether an order
      // was paid, and it says so on the result screen.
      expect(find.textContaining('successful'), findsNothing);
      expect(find.textContaining('Paid'), findsNothing);
      expect(
        api.calls.where((c) => c.path == '/checkout'),
        isEmpty,
        reason: 'reading the guide is not ordering',
      );
    });
  });
}

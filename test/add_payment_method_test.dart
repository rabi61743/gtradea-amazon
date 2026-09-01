import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/checkout/data/card_details.dart';
import 'package:gtradea_amazon/features/checkout/data/saved_payment_repository.dart';
import 'package:gtradea_amazon/features/checkout/data/saved_payment_store.dart';
import 'package:gtradea_amazon/features/checkout/presentation/add_payment_method_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

/// A Luhn-valid test number, and never a real one.
const _visa = '4242424242424242';

Widget _host(GlobalKey<NavigatorState> key) => MaterialApp(
  theme: AppTheme.light,
  navigatorKey: key,
  home: const Scaffold(body: SizedBox.expand()),
);

/// The row the server answers with.
Map<String, dynamic> _row({
  String id = 'pm-1',
  String last4 = '4242',
  bool isDefault = false,
}) => {
  'id': id,
  'card_last_four': last4,
  'card_type': 'visa',
  'expiry_month': 11,
  'expiry_year': 2031,
  'cardholder_name': 'Rabi Yadav',
  'is_default': isDefault,
};

Future<void> _openSheet(
  WidgetTester tester,
  GlobalKey<NavigatorState> key,
) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(key));
  unawaited(AddPaymentMethodSheet.show(key.currentContext!));
  await tester.pumpAndSettle();
}

Future<void> _fill(
  WidgetTester tester, {
  String number = _visa,
  String month = '11',
  String year = '2031',
  String holder = 'Rabi Yadav',
}) async {
  await tester.enterText(
    find.widgetWithText(TextField, '1234 5678 9012 3456'),
    number,
  );
  await tester.enterText(find.widgetWithText(TextField, 'MM'), month);
  await tester.enterText(find.widgetWithText(TextField, 'YYYY'), year);
  await tester.enterText(find.widgetWithText(TextField, 'John Doe'), holder);
  await tester.pump();
}

void main() {
  late FakeApi api;
  late GlobalKey<NavigatorState> nav;

  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    SavedPaymentStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    nav = GlobalKey<NavigatorState>();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    SavedPaymentStore.instance.resetForTest();
    clearApiStub();
  });

  group('what reaches the server', () {
    test('is the last four digits and never the number', () async {
      // The single most important assertion in this file. The card number is
      // read for its brand and its tail, and neither it nor anything that
      // could be used to charge the card is in the request.
      signIn();
      api.on('POST', '/saved-payment-methods', body: _row());

      await SavedPaymentRepository.instance.add(
        number: _visa,
        holder: 'Rabi Yadav',
        expiryMonth: 11,
        expiryYear: 2031,
      );

      final sent = api.calls.single;
      expect(sent.json['card_last_four'], '4242');
      expect(sent.json['card_type'], 'visa');
      expect(sent.json['expiry_month'], 11);
      expect(sent.json['expiry_year'], 2031);
      expect(sent.json['cardholder_name'], 'Rabi Yadav');

      final body = sent.json.toString();
      expect(body.contains(_visa), isFalse, reason: 'the number never travels');
      expect(body.contains('424242424242'), isFalse);
      expect(
        sent.json.keys,
        isNot(contains('cvv')),
        reason: 'there is no security code anywhere in this flow',
      );
      expect(sent.json.keys, isNot(contains('card_number')));
    });

    test('reads the shop own record back', () async {
      signIn();
      api.on(
        'GET',
        '/saved-payment-methods',
        body: [
          _row(id: 'pm-1', isDefault: true),
          _row(id: 'pm-2', last4: '1881'),
        ],
      );

      final cards = await SavedPaymentRepository.instance.list();

      expect(cards.map((c) => c.last4), ['4242', '1881']);
      expect(cards.first.serverId, 'pm-1');
      expect(cards.first.isDefault, isTrue);
      expect(cards.first.brand, CardBrand.visa);
      expect(cards.first.holder, 'Rabi Yadav');
    });

    test('a row with no usable digits is dropped, not drawn blank', () async {
      signIn();
      api.on(
        'GET',
        '/saved-payment-methods',
        body: [
          {'id': 'pm-1', 'card_last_four': '', 'expiry_month': 11},
        ],
      );

      expect(await SavedPaymentRepository.instance.list(), isEmpty);
    });

    test('a delete goes to the server before the device forgets', () async {
      // Or the card returns on the next sync, which reads as the delete having
      // been ignored.
      signIn();
      api.on('DELETE', '/saved-payment-methods/pm-1', status: 204);
      api.on('GET', '/saved-payment-methods', body: [_row()]);
      await SavedPaymentStore.instance.syncFromServer();
      expect(SavedPaymentStore.instance.cards, hasLength(1));

      await SavedPaymentStore.instance.removeCard(
        SavedPaymentStore.instance.cards.single,
      );

      expect(SavedPaymentStore.instance.cards, isEmpty);
      expect(
        api.calls.where((c) => c.method == 'DELETE'),
        isNotEmpty,
        reason: 'the shop was told',
      );
    });
  });

  group('the Add Payment Method sheet', () {
    testWidgets('shows the fields the reference asks for, and no CVV', (
      tester,
    ) async {
      signIn();
      await _openSheet(tester, nav);

      expect(find.text('Add Payment Method'), findsOneWidget);
      expect(find.text('Card Number'), findsOneWidget);
      expect(find.text('Expiry Month'), findsOneWidget);
      expect(find.text('Expiry Year'), findsOneWidget);
      expect(find.text('Cardholder Name'), findsOneWidget);
      expect(find.text('Set as default payment method'), findsOneWidget);
      expect(find.text('Save Card'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Nothing here can charge the card, so nothing here asks for the code.
      expect(find.textContaining('CVV'), findsNothing);
      expect(find.textContaining('CVC'), findsNothing);
      expect(find.textContaining('Security code'), findsNothing);
    });

    testWidgets('refuses an empty form and sends nothing', (tester) async {
      signIn();
      await _openSheet(tester, nav);

      await tester.tap(find.text('Save Card'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the card number'), findsOneWidget);
      expect(find.text('Enter the name on the card'), findsOneWidget);
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });

    testWidgets('catches a mistyped number before the server does', (
      tester,
    ) async {
      signIn();
      await _openSheet(tester, nav);
      // Right length, wrong checksum -- a transposed pair, which is the
      // commonest mistype and the one a length check cannot see.
      await _fill(tester, number: '4242424242424243');

      await tester.tap(find.text('Save Card'));
      await tester.pumpAndSettle();

      expect(find.text('Check the card number'), findsOneWidget);
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });

    testWidgets('refuses a month that does not exist', (tester) async {
      signIn();
      await _openSheet(tester, nav);
      await _fill(tester, month: '13');

      await tester.tap(find.text('Save Card'));
      await tester.pumpAndSettle();

      expect(find.text('MM, 01-12'), findsOneWidget);
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });

    testWidgets('refuses a card that has already expired', (tester) async {
      signIn();
      await _openSheet(tester, nav);
      await _fill(tester, month: '01', year: '2020');

      await tester.tap(find.text('Save Card'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Check the year'), findsOneWidget);
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });

    testWidgets('a good card is saved and joins the list', (tester) async {
      signIn();
      api.on('POST', '/saved-payment-methods', body: _row());
      await _openSheet(tester, nav);
      await _fill(tester);

      await tester.tap(find.text('Save Card'));
      await tester.pumpAndSettle();

      expect(api.calls.where((c) => c.method == 'POST'), hasLength(1));
      final saved = SavedPaymentStore.instance.cards.single;
      expect(saved.last4, '4242');
      expect(saved.serverId, 'pm-1');
      // The sheet closes on success, so the same card cannot be saved twice by
      // a second tap on a button that is still sitting there.
      expect(find.text('Save Card'), findsNothing);
    });

    testWidgets('the default checkbox reaches the server', (tester) async {
      signIn();
      api.on('POST', '/saved-payment-methods', body: _row(isDefault: true));
      await _openSheet(tester, nav);
      await _fill(tester);

      await tester.tap(find.text('Set as default payment method'));
      await tester.pump();
      await tester.tap(find.text('Save Card'));
      await tester.pumpAndSettle();

      expect(
        api.calls.firstWhere((c) => c.method == 'POST').json['is_default'],
        isTrue,
      );
    });

    testWidgets('a refused save says why and keeps what was typed', (
      tester,
    ) async {
      signIn();
      api.on(
        'POST',
        '/saved-payment-methods',
        status: 500,
        body: const {'error': 'Card store unavailable'},
      );
      await _openSheet(tester, nav);
      await _fill(tester);

      await tester.tap(find.text('Save Card'));
      await tester.pumpAndSettle();

      expect(find.textContaining('unavailable'), findsOneWidget);
      // Still open, still filled in -- a failure must not cost the typing.
      expect(find.text('Save Card'), findsOneWidget);
      expect(find.text('Rabi Yadav'), findsOneWidget);
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/l10n/app_strings.dart';
import 'package:gtradea_amazon/core/l10n/payment_strings.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/features/checkout/data/card_details.dart';
import 'package:gtradea_amazon/features/checkout/data/payment_method.dart';
import 'package:gtradea_amazon/features/checkout/data/payment_settings_repository.dart';
import 'package:gtradea_amazon/features/checkout/data/saved_payment_store.dart';
import 'package:gtradea_amazon/features/checkout/presentation/payment_methods_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

/// Test numbers the card schemes publish for exactly this purpose. None of
/// them belongs to anybody.
const _visa = '4111111111111111';
const _amex = '378282246310005';
const _mastercard = '5555555555554444';

CardDetails card({
  String number = _visa,
  String holder = 'RABI YADAV',
  int month = 12,
  int year = 2030,
  String cvv = '123',
}) =>
    CardDetails(
      number: number,
      holder: holder,
      expiryMonth: month,
      expiryYear: year,
      cvv: cvv,
    );

void main() {
  group('what the shop accepts', () {
    late FakeApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      api = FakeApi();
      ApiClient.overrideDio = api.dio();
    });

    tearDown(() => ApiClient.overrideDio = null);

    test('a method the shop switched off is never offered', () async {
      // The live storefront has cash on delivery and cards disabled. Offering
      // one means a shopper picks it, enters an address, agrees a total,
      // commits -- and is then refused by a gateway that was never going to
      // accept them.
      api.on('GET', '/site-settings/active_payment_methods', body: const {
        'setting_value': {
          'khalti': {'label': 'Khalti', 'order': 1, 'enabled': true},
          'cod': {'label': 'Cash on Delivery', 'order': 4, 'enabled': false},
          'card': {'label': 'Credit Card', 'order': 1, 'enabled': false},
        },
      });

      final methods = await PaymentSettingsRepository.instance.methods();
      expect(methods.map((m) => m.id), ['khalti']);
    });

    test('methods come back in the shop order, not the app', () async {
      api.on('GET', '/site-settings/active_payment_methods', body: const {
        'setting_value': {
          'connectips': {'label': 'connectIPS', 'order': 2, 'enabled': true},
          'khalti': {'label': 'Khalti', 'order': 1, 'enabled': true},
          'esewa': {'label': 'eSewa', 'order': 2, 'enabled': true},
        },
      });

      final methods = await PaymentSettingsRepository.instance.methods();
      // Khalti first by order; the two sharing order 2 break the tie the same
      // way every time, so the list does not reshuffle between builds.
      expect(methods.map((m) => m.id), ['khalti', 'connectips', 'esewa']);
    });

    test('the shop own label, description and badge are used', () async {
      api.on('GET', '/site-settings/active_payment_methods', body: const {
        'setting_value': {
          'khalti': {
            'label': 'Khalti',
            'description': 'Pay with Khalti wallet, bank or mobile banking',
            'badge': 'Recommended',
            'order': 1,
            'enabled': true,
            'isDefault': true,
          },
        },
      });

      final method =
          (await PaymentSettingsRepository.instance.methods()).single;
      expect(method.label, 'Khalti');
      expect(method.badge, 'Recommended');
      expect(method.isDefault, isTrue);
      expect(method.kind, PaymentKind.wallet);
    });

    test('a beta method is hidden from everyone not on the list', () {
      // Fail-closed. A half-finished integration switched on for its testers
      // must not appear for anyone else, and least of all for a guest.
      const beta = PaymentMethod(
        id: 'esewa',
        label: 'eSewa',
        description: '',
        order: 2,
        betaUserIds: ['user-a'],
      );

      expect(beta.isVisibleTo('user-a'), isTrue);
      expect(beta.isVisibleTo('user-b'), isFalse);
      expect(beta.isVisibleTo(null), isFalse);
    });

    test('a method with no beta list is for everyone', () {
      const open = PaymentMethod(
        id: 'khalti',
        label: 'Khalti',
        description: '',
        order: 1,
      );
      expect(open.isVisibleTo(null), isTrue);
    });

    test('an unseeded setting is no methods, not a crash', () async {
      api.on('GET', '/site-settings/active_payment_methods',
          body: const {'setting_value': null});

      expect(await PaymentSettingsRepository.instance.methods(), isEmpty);
    });

    test('the advance percentage parses even as a string', () async {
      // The live value is the string "80".
      api.on('GET', '/site-settings/advance_payment_percent',
          body: const {'setting_value': '80'});

      expect(await PaymentSettingsRepository.instance.advancePercent(), 80);
    });

    test('a missing advance percentage charges the whole amount', () async {
      // The safe default: never ask for less than the order is worth and then
      // bill the difference.
      api.on('GET', '/site-settings/advance_payment_percent',
          status: 500, body: const {'error': 'down'});

      expect(await PaymentSettingsRepository.instance.advancePercent(), 100);
    });
  });

  group('card validation', () {
    test('catches a mistyped number the length check would let through', () {
      // Two digits transposed is the commonest way a card is mistyped, and the
      // only check that sees it is the checksum.
      expect(passesLuhn(_visa), isTrue);
      expect(passesLuhn('4111111111111112'), isFalse);

      final errors = validateCard(
        number: '4111 1111 1111 1112',
        holder: 'RABI',
        expiry: '12/30',
        cvv: '123',
      );
      expect(errors.number, 'Check the card number');
      expect(errors.isValid, isFalse);
    });

    test('knows the brand from the leading digits', () {
      expect(CardBrand.of(_visa), CardBrand.visa);
      expect(CardBrand.of(_mastercard), CardBrand.mastercard);
      expect(CardBrand.of(_amex), CardBrand.amex);
      expect(CardBrand.of('6212345678901232'), CardBrand.unionPay);
      expect(CardBrand.of('9999'), CardBrand.unknown);
    });

    test('expects four digits for Amex and three for the rest', () {
      // Otherwise an Amex holder types three digits into a field that accepts
      // them and is declined by the issuer for no visible reason.
      expect(
        validateCard(
          number: _amex,
          holder: 'R Y',
          expiry: '12/30',
          cvv: '123',
        ).cvv,
        'American Express codes are 4 digits',
      );
      expect(
        validateCard(
          number: _amex,
          holder: 'R Y',
          expiry: '12/30',
          cvv: '1234',
        ).cvv,
        isNull,
      );
    });

    test('a card is good through the last day of its expiry month', () {
      // Not up to the first. A card expiring 08/26 works all through August.
      final august = DateTime(2026, 8, 20);
      expect(
        validateCard(
          number: _visa,
          holder: 'R Y',
          expiry: '08/26',
          cvv: '123',
          now: august,
        ).expiry,
        isNull,
      );
      expect(
        validateCard(
          number: _visa,
          holder: 'R Y',
          expiry: '07/26',
          cvv: '123',
          now: august,
        ).expiry,
        'That card has expired',
      );
    });

    test('a month that does not exist says so', () {
      expect(
        validateCard(
          number: _visa,
          holder: 'R Y',
          expiry: '13/30',
          cvv: '123',
        ).expiry,
        'That month does not exist',
      );
    });

    test('every field says what to change', () {
      final errors = validateCard(number: '', holder: '', expiry: '', cvv: '');
      expect(errors.number, 'Enter the card number');
      expect(errors.holder, 'Enter the name on the card');
      expect(errors.expiry, 'Enter the expiry date');
      expect(errors.cvv, 'Enter the security code');
    });

    test('groups the number the way it is printed on the card', () {
      expect(formatCardNumber('4111111111111111'), '4111 1111 1111 1111');
      // Amex is printed 4-6-5, not 4-4-4-4.
      expect(formatCardNumber('378282246310005'), '3782 822463 10005');
    });
  });

  group('saving a card', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SavedPaymentStore.instance.resetForTest();
    });

    test('keeps the last four digits and nothing more of the number', () {
      final saved = SavedPaymentMethod.fromCard(card());

      expect(saved.last4, '1111');
      expect(saved.maskedNumber, '•••• •••• •••• 1111');
      expect(saved.brand, CardBrand.visa);
    });

    test('never writes the number or the security code to disk', () async {
      // The rule the whole feature turns on. Storing a full card number puts
      // this app inside the card industry's scope for no benefit, and keeping
      // a security code after a transaction is forbidden outright.
      SavedPaymentStore.instance.save(SavedPaymentMethod.fromCard(card()));
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(SavedPaymentStore.storageKeyFor(null)) ?? '';

      expect(raw, isNot(contains(_visa)));
      expect(raw, contains('1111'), reason: 'the last four may be kept');

      // And nothing resembling a card number survives anywhere in the blob.
      final decoded = jsonDecode(raw) as List;
      final fields = (decoded.single as Map).values.join(' ');
      expect(RegExp(r'\d{12,}').hasMatch(fields), isFalse);
    });

    test('the object itself does not print the number', () {
      // Guards against a card reaching a crash report through a stray
      // interpolation.
      expect(card().toString(), isNot(contains(_visa)));
      expect(card().toString(), contains('1111'));
    });

    test('the same card saved twice appears once', () {
      final store = SavedPaymentStore.instance;
      expect(store.save(SavedPaymentMethod.fromCard(card())), isTrue);
      expect(store.save(SavedPaymentMethod.fromCard(card())), isFalse);
      expect(store.count, 1);
    });

    test('an expired card is kept and marked, not hidden', () {
      // Someone looking for a card they saved should find it.
      final expired = SavedPaymentMethod.fromCard(card(month: 1, year: 2020));
      expect(expired.isExpired(), isTrue);
      expect(expired.expiryLabel, '01/20');

      final live = SavedPaymentMethod.fromCard(card(month: 12, year: 2099));
      expect(live.isExpired(), isFalse);
    });

    test('a card is good through the last day of its month here too', () {
      final august = SavedPaymentMethod.fromCard(card(month: 8, year: 2026));
      expect(august.isExpired(DateTime(2026, 8, 31)), isFalse);
      expect(august.isExpired(DateTime(2026, 9, 1)), isTrue);
    });

    test('removing takes it off the list and off the disk', () async {
      final store = SavedPaymentStore.instance;
      final saved = SavedPaymentMethod.fromCard(card());
      store.save(saved);
      await Future<void>.delayed(Duration.zero);

      store.remove(saved.id);
      await Future<void>.delayed(Duration.zero);

      expect(store.isEmpty, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SavedPaymentStore.storageKeyFor(null)), '[]');
    });

    test('one shopper never sees another shopper cards', () async {
      // A card belongs to a person, not a phone. Carrying one across a sign-in
      // would attach it to the wrong account, which for payment details is the
      // worst kind of wrong.
      final store = SavedPaymentStore.instance;
      store.save(SavedPaymentMethod.fromCard(card()));
      await Future<void>.delayed(Duration.zero);

      await store.switchIdentity('someone@else.com');
      expect(store.isEmpty, isTrue);

      await store.switchIdentity(null);
      expect(store.count, 1, reason: 'the guest cards are still theirs');
    });

    test('a corrupt store degrades to none rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        SavedPaymentStore.storageKeyFor(null): 'not json',
      });
      SavedPaymentStore.instance.resetForTest();

      await SavedPaymentStore.instance.load();
      expect(SavedPaymentStore.instance.isEmpty, isTrue);
    });

    test('an entry with a full number where the last four belong is rejected',
        () {
      // Defence in depth: even if something wrote one, it does not come back.
      expect(
        SavedPaymentMethod.fromJson(const {
          'id': 'x',
          'last4': _visa,
          'expiryMonth': 12,
          'expiryYear': 2030,
        }),
        isNull,
      );
    });
  });

  group('translations', () {
    test('the payment flow speaks both languages', () {
      // Missing a string is a compile error, not an English word in a Nepali
      // checkout. This checks the two tables are actually different.
      expect(AppStrings.en.payment.paymentSuccessful, 'Payment successful');
      expect(
        AppStrings.ne.payment.paymentSuccessful,
        isNot(AppStrings.en.payment.paymentSuccessful),
      );
      expect(AppStrings.ne.payment.title, isNotEmpty);
      expect(
        PaymentStrings.ne.paidWith('Khalti'),
        contains('Khalti'),
        reason: 'the method name is not translated',
      );
    });

    test('the order number survives translation', () {
      expect(
        PaymentStrings.ne.orderStillExists('GT-1001'),
        contains('GT-1001'),
      );
    });
  });

  group('the payment methods screen', () {
    late FakeApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SavedPaymentStore.instance.resetForTest();
      api = FakeApi();
      ApiClient.overrideDio = api.dio();
      api.on('GET', '/site-settings/active_payment_methods', body: const {
        'setting_value': {
          'khalti': {
            'label': 'Khalti',
            'description': 'Pay with Khalti wallet',
            'badge': 'Recommended',
            'order': 1,
            'enabled': true,
          },
          'cod': {'label': 'Cash on Delivery', 'order': 4, 'enabled': false},
        },
      });
    });

    tearDown(() => ApiClient.overrideDio = null);

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PaymentMethodsScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('lists a saved card by its last four digits', (tester) async {
      SavedPaymentStore.instance.save(SavedPaymentMethod.fromCard(card()));
      await pump(tester);

      expect(find.text('Visa •••• •••• •••• 1111'), findsOneWidget);
      expect(find.textContaining('RABI YADAV'), findsOneWidget);
      // And never anything more of the number than that.
      expect(find.textContaining(_visa), findsNothing);
    });

    testWidgets('removing a card asks first, and backing out keeps it',
        (tester) async {
      SavedPaymentStore.instance.save(SavedPaymentMethod.fromCard(card()));
      await pump(tester);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this card?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(SavedPaymentStore.instance.count, 1);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(SavedPaymentStore.instance.isEmpty, isTrue);
      expect(find.text('No saved cards'), findsOneWidget);
    });

    testWidgets('an expired card is shown and marked, not hidden',
        (tester) async {
      SavedPaymentStore.instance
          .save(SavedPaymentMethod.fromCard(card(month: 1, year: 2020)));
      await pump(tester);

      expect(find.text('Visa •••• •••• •••• 1111'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('says where a card comes from when there are none',
        (tester) async {
      // There is deliberately no Add button: a card is saved at the moment it
      // is used, so an empty list has to explain itself.
      await pump(tester);

      expect(find.text('No saved cards'), findsOneWidget);
      expect(find.textContaining('ask us to remember it'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add card'), findsNothing);
    });

    testWidgets('shows what the shop accepts, and not what it does not',
        (tester) async {
      await pump(tester);

      expect(find.text('Khalti'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Cash on Delivery'), findsNothing);
    });

    testWidgets('a failure to check offers a retry rather than an empty list',
        (tester) async {
      api.on('GET', '/site-settings/active_payment_methods',
          status: 500, body: const {'error': 'settings are down'});
      await pump(tester);

      expect(find.text('settings are down'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('says plainly what is never stored', (tester) async {
      await pump(tester);
      expect(find.textContaining('never stores your card number'),
          findsOneWidget);
    });
  });
}

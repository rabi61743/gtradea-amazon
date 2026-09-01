import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/checkout/presentation/checkout_screen.dart';
import 'package:gtradea_amazon/features/legal/data/legal_page_repository.dart';
import 'package:gtradea_amazon/features/legal/presentation/terms_sheet.dart';

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

/// The place-order button, whatever it is currently labelled.
ElevatedButton _payButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton).last);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
    LegalPageRepository.instance.resetForTest();
    api.on(
      'GET',
      '/pages/terms',
      body: {
        'id': 'p',
        'slug': 'terms',
        'title': 'Terms of Service',
        'content': '<h2>Terms of Service</h2><p>Agreement to Terms.</p>',
      },
    );
  });

  testWidgets('the order cannot be placed until the terms are accepted', (
    tester,
  ) async {
    // This is the whole point. `CheckoutOrderInput.termsAccepted` was hardcoded
    // to true, so the app asserted to the server that the customer had agreed
    // to terms it had never shown them.
    await _pump(tester);

    expect(find.textContaining('I have read and agree to the'), findsOneWidget);
    expect(
      _payButton(tester).onPressed,
      isNull,
      reason: 'nothing can be ordered before the box is ticked',
    );
  });

  testWidgets('ticking the box enables it', (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(_payButton(tester).onPressed, isNotNull);
  });

  testWidgets('the terms open, and come from the server', (tester) async {
    // Fetched from GET /pages/terms rather than pasted into the app, so what a
    // shopper agrees to is the text the shop is currently publishing.
    await _pump(tester);

    await tester.tapOnText(find.textRange.ofSubstring('Terms and Conditions'));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c.path == '/pages/terms'), isNotEmpty);
    expect(find.text('Terms of Service'), findsWidgets);
    expect(find.textContaining('Agreement to Terms'), findsOneWidget);
  });

  testWidgets('the terms say so when they cannot be loaded', (tester) async {
    // Somebody being asked to agree to something has a right to know the text
    // failed to load, rather than being shown a blank page and a tick box.
    api.on(
      'GET',
      '/pages/terms',
      status: 500,
      body: {'message': 'Terms are unavailable right now.'},
    );
    LegalPageRepository.instance.resetForTest();

    await _pump(tester);
    await tester.tapOnText(find.textRange.ofSubstring('Terms and Conditions'));
    await tester.pumpAndSettle();

    // Scoped: the payment-methods loader offers a Try again of its own when it
    // has not been stubbed either.
    expect(
      find.descendant(
        of: find.byType(TermsSheet),
        matching: find.text('Try again'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a signed-out shopper still has to tick before anything runs', (
    tester,
  ) async {
    signInForTest();
    await _pump(tester);

    expect(_payButton(tester).onPressed, isNull);
  });
}

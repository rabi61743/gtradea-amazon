import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/shared/widgets/artwork_panel.dart';
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

/// The shop's live method list, as measured on the server: eSewa, Khalti,
/// connectIPS, Bank/Mobile Wallet and Fonepay Checkout are on; cash on
/// delivery, card and plain Fonepay are off.
Map<String, dynamic> get _liveMethods => {
  'setting_value': {
    'cod': {'label': 'Cash on Delivery', 'order': 1, 'enabled': false},
    // The beta list is production's, and it matters: eSewa is switched on for
    // everyone *and* carries testers. Reading that as a restriction hid it
    // from every shopper, which is what this fixture now catches.
    'esewa': {
      'label': 'eSewa',
      'description': 'Pay with your eSewa wallet',
      'order': 2,
      'enabled': true,
      'betaUserIds': ['6fb5f98d-d044-40fe-b129-3182b4d3d2c6'],
    },
    'khalti': {
      'label': 'Khalti',
      'description': 'Pay with Khalti wallet, bank or mobile banking',
      'order': 3,
      'enabled': true,
      'isDefault': true,
    },
    'connectips': {
      'label': 'connectIPS',
      'description': 'Pay direct from any Nepali bank account',
      'order': 4,
      'enabled': true,
    },
  },
};

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

Future<void> _acceptTerms(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
    LegalPageRepository.instance.resetForTest();
    api
      ..on('GET', '/site-settings/active_payment_methods', body: _liveMethods)
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
      ..on(
        'POST',
        '/payments/khalti/initiate',
        body: const {
          'orderId': 'order-1',
          'orderNumber': 'GT-1001',
          'paymentUrl': 'https://test.local/pay',
        },
      );
  });

  group('eSewa', () {
    testWidgets('is offered, because the shop has it switched on', (
      tester,
    ) async {
      // Measured live: active_payment_methods has esewa enabled. The app reads
      // that list rather than holding its own, so eSewa needed no adding -- it
      // needed proving. This is the test that says it reaches the screen.
      await _pump(tester);

      expect(find.text('eSewa'), findsOneWidget);
      expect(find.text('Khalti'), findsOneWidget);
      expect(find.text('connectIPS'), findsOneWidget);
    });

    testWidgets('a method the shop switched off is not offered', (
      tester,
    ) async {
      // Offering one the server has disabled means a shopper picks it, commits,
      // and is refused by a gateway that was never going to take them.
      await _pump(tester);

      expect(find.text('Cash on Delivery'), findsNothing);
    });
  });

  testWidgets('the sections run address, billing, summary, payment', (
    tester,
  ) async {
    // Asserted by position on screen rather than by reading the widget list,
    // because the order is the requirement: a shopper says where it goes and
    // who it is billed to, checks what it comes to, and only then chooses how
    // to pay. Picking a gateway before seeing the total is the wrong way round.
    await _pump(tester);

    final address = tester.getTopLeft(find.text('Deliver to')).dy;
    final billing = tester.getTopLeft(find.text('Bill To')).dy;
    final summary = tester.getTopLeft(find.text('Order summary')).dy;
    // 'Payment' is the section's localised title -- the reference calls it
    // "Payment method", the app's own string is shorter.
    final payment = tester.getTopLeft(find.text('Payment')).dy;

    expect(address, lessThan(billing));
    expect(billing, lessThan(summary));
    expect(summary, lessThan(payment));
  });

  testWidgets('the payment section is reachable on a real phone', (
    tester,
  ) async {
    // The bug this catches. Payment moved below the order summary, and with the
    // lines expanded it fell off the bottom of a 412x915 screen entirely -- not
    // merely off-view, but never built, because a ListView does not build what
    // it cannot show. The ordering test above missed it: it runs on a 600x1600
    // window where everything fits at once.
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(
      find.text('Payment'),
      findsOneWidget,
      reason: 'a shopper cannot choose what they cannot reach',
    );
    expect(find.text('Khalti'), findsOneWidget);
  });

  testWidgets('the order summary opens to show the lines', (tester) async {
    await _pump(tester);

    // Closed to begin with, so the payment choice stays on screen; the lines
    // are one tap away for anyone who wants to check them.
    expect(find.text('Ice silk jacket'), findsNothing);

    await tester.tap(find.text('2 items'));
    await tester.pumpAndSettle();

    expect(find.text('Ice silk jacket'), findsOneWidget);
  });

  group('the summary line pictures', () {
    /// Two different products, each with its own photograph.
    Widget twoLines() {
      const lines = [
        CartLine(
          productId: 'p1',
          title: 'Ice silk jacket',
          unitPrice: 1130,
          quantity: 2,
          imageUrl: 'https://cdn.invalid/jacket.jpg',
        ),
        CartLine(
          productId: 'p2',
          title: 'Canvas tote',
          unitPrice: 400,
          quantity: 1,
          imageUrl: 'https://cdn.invalid/tote.jpg',
        ),
      ];
      return MaterialApp(
        theme: AppTheme.light,
        home: CheckoutScreen(lines: lines, totals: CartTotals.of(lines)),
      );
    }

    testWidgets('each line shows its own product, in order', (tester) async {
      // The requirement that a mistake here would be invisible on one line and
      // obvious on two: the second row must carry the second product's picture,
      // not the first one's.
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(twoLines());
      await tester.pumpAndSettle();

      await tester.tap(find.text('3 items'));
      await tester.pumpAndSettle();

      final panels = tester
          .widgetList<ArtworkPanel>(find.byType(ArtworkPanel))
          .toList();
      expect(panels, hasLength(2));
      expect(panels[0].imageUrl, 'https://cdn.invalid/jacket.jpg');
      expect(panels[1].imageUrl, 'https://cdn.invalid/tote.jpg');
    });

    testWidgets('and they arrive only when the summary is opened', (
      tester,
    ) async {
      // The section is closed by default so the payment choice stays on screen.
      // Pictures must not change that.
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(twoLines());
      await tester.pumpAndSettle();

      expect(find.byType(ArtworkPanel), findsNothing);
    });

    testWidgets('a line with no picture still renders', (tester) async {
      // Roughly half this catalogue publishes no image for a listing. The panel
      // draws its tinted icon rather than a gap or a broken-image glyph, which
      // is the fallback the cart and the order lines already use.
      await _pump(tester);

      await tester.tap(find.text('2 items'));
      await tester.pumpAndSettle();

      final panel = tester.widget<ArtworkPanel>(find.byType(ArtworkPanel));
      expect(panel.imageUrl, isNull);
      expect(find.text('Ice silk jacket'), findsOneWidget);
    });
  });

  group('Bill To', () {
    testWidgets('offers an individual and a business invoice', (tester) async {
      await _pump(tester);

      expect(find.text('Bill To'), findsOneWidget);
      expect(find.text('Individual'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);
    });

    testWidgets('an individual is asked for no company details', (
      tester,
    ) async {
      // A company name box under a personal order is a field that can only be
      // filled in by mistake.
      await _pump(tester);

      expect(find.text('Company name'), findsNothing);
      expect(find.textContaining('PAN / VAT'), findsNothing);
    });

    testWidgets('choosing Business asks who the invoice is for', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.text('Business'));
      await tester.pumpAndSettle();

      expect(find.text('Company name'), findsOneWidget);
      expect(find.textContaining('PAN / VAT'), findsOneWidget);
    });

    testWidgets('a business order without a company name is refused', (
      tester,
    ) async {
      signInForTest();
      await _pump(tester);
      await _acceptTerms(tester);

      await tester.tap(find.text('Business'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();

      expect(
        find.text('A business invoice needs a company name.'),
        findsOneWidget,
      );
      expect(
        api.calls.where((c) => c.path == '/checkout'),
        isEmpty,
        reason: 'nothing was sent',
      );
    });

    testWidgets('the billing choice reaches the server', (tester) async {
      // billingType, companyName and taxId have been in CheckoutOrderInput
      // since it was written and nothing ever set them, so every order went as
      // an individual -- including the wholesale ones.
      signInForTest();
      AddressStore.instance.add(
        label: AddressLabel.home,
        fullName: 'Rabi Yadav',
        phone: '9800000000',
        province: 'Bagmati',
        city: 'Lalitpur',
        area: 'Jhamsikhel',
      );
      // Cash on delivery for this one. A gateway order opens a WebView, which
      // has no platform implementation under `flutter_test`; the body is built
      // by the same `CheckoutOrderInput.toJson` either way, so the COD path
      // proves the shape without standing up a browser.
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

      await _pump(tester);
      await _acceptTerms(tester);
      await tester.tap(find.text('Business'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Company name'),
        'Himalaya Traders',
      );
      await tester.pumpAndSettle();

      await tester.tap(_payButtonFinder());
      await tester.pumpAndSettle();

      final sent = api.calls.lastWhere((c) => c.path == '/checkout');
      final billing = (sent.json['billingAddress'] as Map)
          .cast<String, Object?>();
      expect(billing['billingType'], 'business');
      expect(billing['companyName'], 'Himalaya Traders');
      expect(sent.json['termsAccepted'], isTrue);
    });
  });
}

Finder _payButtonFinder() => find.byType(ElevatedButton).last;

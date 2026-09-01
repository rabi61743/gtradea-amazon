import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/help/presentation/contact_screen.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/presentation/track_order_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';
import 'support/orders.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  late FakeApi api;

  /// Signs in, then puts our own stub back -- `signInForTest` installs one of
  /// its own, which would otherwise swallow the calls being asserted on.
  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    OrderStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on(
      'GET',
      '/site-settings/support_email',
      body: const {'setting_value': 'business@gtradea.com'},
    );
    api.on(
      'GET',
      '/site-settings/support_phone',
      body: const {'setting_value': '+977-9712000020 customer_Support'},
    );
    api.on('GET', '/orders', body: const []);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    OrderStore.instance.resetForTest();
    clearApiStub();
  });

  group('the Contact page', () {
    testWidgets('shows the shop own address, hours and number', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const ContactScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Contact Information'), findsOneWidget);
      expect(find.text('business@gtradea.com'), findsOneWidget);
      expect(find.text('2-4 hours (business hours)'), findsOneWidget);
      expect(
        find.textContaining('+977-9712000020'),
        findsOneWidget,
        reason: 'the shop setting, not a number written into the app',
      );
    });

    testWidgets('has Quick Links, and no FAQs among them', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const ContactScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Quick Links'), findsOneWidget);
      expect(find.text('Help Center'), findsOneWidget);
      expect(find.text('Track Order'), findsOneWidget);
      expect(find.text('FAQs'), findsNothing);
      expect(find.textContaining('FAQ'), findsNothing);
    });

    testWidgets('Track Order opens the tracker', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const ContactScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Track Order'));
      await tester.pumpAndSettle();

      expect(find.byType(TrackOrderScreen), findsOneWidget);
    });

    testWidgets('a setting the shop has not published is left out', (
      tester,
    ) async {
      api.on(
        'GET',
        '/site-settings/support_phone',
        body: const {'setting_value': null},
      );
      _tall(tester);
      await tester.pumpWidget(_wrap(const ContactScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Phone'), findsNothing);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('a failure offers a retry', (tester) async {
      api.on(
        'GET',
        '/site-settings/support_email',
        status: 500,
        body: const {},
      );
      _tall(tester);
      await tester.pumpWidget(_wrap(const ContactScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Track order', () {
    testWidgets('finds the order and reports where it has got to', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/orders', body: [orderJson(orderNumber: 'GT-1001')]);
      api.on('GET', '/orders/order-1/tracking', body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap(const TrackOrderScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GT-1001');
      await tester.tap(find.widgetWithText(FilledButton, 'Track order'));
      await tester.pumpAndSettle();

      // Twice: in the box it was typed into, and on the result card.
      expect(find.text('GT-1001'), findsNWidgets(2));
      expect(find.text('View order details'), findsOneWidget);
      // The server's own list was asked, rather than whatever this device held.
      expect(api.calls.where((c) => c.path.endsWith('/orders')), isNotEmpty);
    });

    testWidgets('the number is matched however it was typed', (tester) async {
      // Somebody reading it off a confirmation types it as they see it.
      signIn();
      api.on('GET', '/orders', body: [orderJson(orderNumber: 'GT-1001')]);
      api.on('GET', '/orders/order-1/tracking', body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap(const TrackOrderScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  gt1001 ');
      await tester.tap(find.widgetWithText(FilledButton, 'Track order'));
      await tester.pumpAndSettle();

      expect(find.text('View order details'), findsOneWidget);
    });

    testWidgets('a cancelled order says so rather than a delivery stage', (
      tester,
    ) async {
      signIn();
      api.on(
        'GET',
        '/orders',
        body: [orderJson(orderNumber: 'GT-1001', status: 'cancelled')],
      );
      api.on('GET', '/orders/order-1/tracking', body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap(const TrackOrderScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GT-1001');
      await tester.tap(find.widgetWithText(FilledButton, 'Track order'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cancelled'), findsWidgets);
    });

    testWidgets('a number nobody ordered under is refused clearly', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/orders', body: [orderJson(orderNumber: 'GT-1001')]);
      _tall(tester);
      await tester.pumpWidget(_wrap(const TrackOrderScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GT-9999');
      await tester.tap(find.widgetWithText(FilledButton, 'Track order'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No order numbered'), findsOneWidget);
      expect(find.text('View order details'), findsNothing);
    });

    testWidgets('an empty box is asked for a number, not searched', (
      tester,
    ) async {
      signIn();
      _tall(tester);
      await tester.pumpWidget(_wrap(const TrackOrderScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Track order'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Enter the order number'), findsOneWidget);
      expect(
        api.calls.where((c) => c.path.endsWith('/orders')),
        isEmpty,
        reason: 'nothing to look up',
      );
    });

    testWidgets('an order with no carrier update yet says that', (
      tester,
    ) async {
      // A normal state for a fresh order, and not a failure to report.
      signIn();
      api.on('GET', '/orders', body: [orderJson(orderNumber: 'GT-1001')]);
      api.on('GET', '/orders/order-1/tracking', status: 404, body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap(const TrackOrderScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GT-1001');
      await tester.tap(find.widgetWithText(FilledButton, 'Track order'));
      await tester.pumpAndSettle();

      expect(find.text('No carrier updates yet.'), findsOneWidget);
      expect(find.text('View order details'), findsOneWidget);
    });

    testWidgets('a lookup that fails says so rather than "not found"', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/orders', status: 500, body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap(const TrackOrderScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GT-1001');
      await tester.tap(find.widgetWithText(FilledButton, 'Track order'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No order numbered'), findsNothing);
    });
  });
}

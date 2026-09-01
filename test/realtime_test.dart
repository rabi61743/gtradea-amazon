import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/realtime/realtime_service.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';
import 'support/orders.dart';

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OrderStore.instance.resetForTest();
    api = stubCatalog();
    api.on('GET', '/orders', body: [orderJson()]);
    api.on(
      'GET',
      '/orders/order-1/tracking',
      body: trackingJson(reached: OrderStage.shipped),
    );
  });

  group('classifying an event', () {
    test('routes on a prefix rather than a closed list of names', () {
      // Production emits order_status, cancellation_approved, new_order and
      // more. A closed set would silently drop the ones nobody listed.
      expect(const RealtimeEvent(name: 'order.shipped').isOrder, isTrue);
      expect(const RealtimeEvent(name: 'order_status').isOrder, isTrue);
      expect(
        const RealtimeEvent(name: 'notification.created').isNotification,
        isTrue,
      );
      expect(const RealtimeEvent(name: 'wallet.credited').isOrder, isFalse);
      expect(
        const RealtimeEvent(name: 'wallet.credited').isNotification,
        isFalse,
      );
    });
  });

  group('routing', () {
    testWidgets('an order event refetches the orders', (tester) async {
      signInForTest();
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      final before = api.calls.where((c) => c.path == '/orders').length;

      RealtimeService.instance.emitForTest(
        const RealtimeEvent(name: 'order.shipped'),
      );
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path == '/orders').length,
        greaterThan(before),
      );
    });

    testWidgets('an event naming an order also refetches its tracking', (
      tester,
    ) async {
      // The sibling app refreshes only the list, so a shopper watching a
      // tracking screen sees it sit still while the list behind it updates.
      signInForTest();
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      seedOrder(id: 'order-1');

      RealtimeService.instance.emitForTest(
        const RealtimeEvent(name: 'order.shipped', orderId: 'order-1'),
      );
      await tester.pumpAndSettle();

      expect(
        api.calls.any((c) => c.path == '/orders/order-1/tracking'),
        isTrue,
      );
    });

    testWidgets('an unfamiliar event refreshes everything', (tester) async {
      // A name matching neither prefix is likelier to be a new kind of change
      // than nothing at all, so it is treated as both.
      signInForTest();
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      final before = api.calls.where((c) => c.path == '/orders').length;

      RealtimeService.instance.emitForTest(
        const RealtimeEvent(name: 'something.new'),
      );
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path == '/orders').length,
        greaterThan(before),
      );
    });

    testWidgets('a notification event leaves the orders alone', (tester) async {
      signInForTest();
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      final before = api.calls.where((c) => c.path == '/orders').length;

      RealtimeService.instance.emitForTest(
        const RealtimeEvent(name: 'notification.created'),
      );
      await tester.pumpAndSettle();

      expect(api.calls.where((c) => c.path == '/orders').length, before);
    });
  });
}

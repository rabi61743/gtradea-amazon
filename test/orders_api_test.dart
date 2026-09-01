import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart'
    show OrderStage;
import 'package:gtradea_amazon/features/orders/data/orders_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';
import 'support/orders.dart';

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() => ApiClient.overrideDio = null);

  group('the orders list', () {
    test('reads a bare array', () async {
      api.on(
        'GET',
        '/orders',
        body: [
          orderJson(),
          orderJson(id: 'order-2'),
        ],
      );

      final orders = await OrdersRepository.instance.list();
      expect(orders.map((o) => o.id), ['order-1', 'order-2']);
    });

    test('reads a wrapped array too', () async {
      // The endpoint answers bare today. If it is ever wrapped, an empty list
      // would be indistinguishable from having no orders at all -- which is
      // the most alarming thing this screen can say wrongly.
      api.on(
        'GET',
        '/orders',
        body: {
          'orders': [orderJson()],
        },
      );

      final orders = await OrdersRepository.instance.list();
      expect(orders, hasLength(1));
    });

    test('drops a row with no id rather than failing the list', () async {
      // One malformed row must not cost the shopper their whole order history.
      api.on(
        'GET',
        '/orders',
        body: [
          orderJson(),
          {'order_number': 'GT-9', 'status': 'pending'},
        ],
      );

      final orders = await OrdersRepository.instance.list();
      expect(orders, hasLength(1));
    });

    test('money that arrives as a string is still money', () async {
      // Postgres numeric reaches JSON as a string. A cast here would throw and
      // take the list with it.
      api.on(
        'GET',
        '/orders',
        body: [
          {
            ...orderJson(),
            'total_amount': '2260.50',
            'advance_amount': 1000,
            'remaining_amount': '1260.50',
          },
        ],
      );

      final order = (await OrdersRepository.instance.list()).single;
      expect(order.totalAmount, 2260.50);
      expect(order.advanceAmount, 1000);
      expect(order.remainingAmount, 1260.50);
    });

    test('status is free text, matched rather than mapped', () async {
      // The server is free to add a state. A closed enum would fail to decode
      // an order rather than show an unfamiliar label.
      Future<ServerOrder> withStatus(String status) async {
        api.on('GET', '/orders', body: [orderJson(status: status)]);
        return (await OrdersRepository.instance.list()).single;
      }

      expect((await withStatus('DELIVERED')).isDelivered, isTrue);
      expect((await withStatus('completed')).isDelivered, isTrue);
      expect((await withStatus('partially_cancelled')).isCancelled, isTrue);
      expect((await withStatus('refunded')).isCancelled, isTrue);
      expect((await withStatus('brand_new_state')).isDelivered, isFalse);
      expect((await withStatus('brand_new_state')).isCancelled, isFalse);
    });
  });

  group('tracking', () {
    test('is decoded as camelCase, which is what it is sent as', () async {
      // The one camelCase payload in this API. Normalising it would be a
      // second place for the two conventions to drift apart.
      api.on(
        'GET',
        '/orders/order-1/tracking',
        body: trackingJson(
          reached: OrderStage.shipped,
          statusLabel: 'On its way',
        ),
      );

      final tracking = await OrdersRepository.instance.tracking('order-1');
      expect(tracking.statusLabel, 'On its way');
      expect(tracking.shipments.single.shipmentNo, 'SHIP-77');
      expect(tracking.shipments.single.modeLabel, 'Road freight');
      expect(tracking.timeline, hasLength(6));
    });

    test(
      'a step status nobody anticipated is treated as not yet reached',
      () async {
        api.on(
          'GET',
          '/orders/order-1/tracking',
          body: {
            'shipments': [
              {
                'timeline': [
                  {
                    'stage': 'TRANSIT',
                    'label': 'x',
                    'status': 'held_at_customs',
                  },
                ],
              },
            ],
          },
        );

        final tracking = await OrdersRepository.instance.tracking('order-1');
        expect(tracking.timeline.single.state, TrackingStepState.upcoming);
      },
    );

    test('an empty tracking payload decodes rather than throwing', () async {
      api.on(
        'GET',
        '/orders/order-1/tracking',
        body: const <String, dynamic>{},
      );

      final tracking = await OrdersRepository.instance.tracking('order-1');
      expect(tracking.hasShipments, isFalse);
      expect(tracking.statusLabel, '');
    });

    test('an id with characters that need escaping is escaped', () async {
      api.on(
        'GET',
        '/orders/a%2Fb/tracking',
        body: trackingJson(reached: OrderStage.placed),
      );

      await OrdersRepository.instance.tracking('a/b');
      expect(api.calls.single.path, '/orders/a%2Fb/tracking');
    });
  });

  group('cancellations and returns', () {
    test('an empty detail is omitted, not sent as an empty string', () async {
      // Absent and empty mean different things to the server, and "" is not
      // "no reason given".
      api.on('POST', '/order-cancellations', status: 201, body: const {});

      await OrdersRepository.instance.requestCancellation(
        orderId: 'order-1',
        reason: 'changed_mind',
        details: '',
      );

      expect(api.calls.single.json.containsKey('reason_details'), isFalse);
      expect(api.calls.single.json['order_id'], 'order-1');
    });

    test('a return names the order items, not the products', () async {
      // Returns key on the order_items row, which is the only thing that
      // identifies one line of one order.
      api.on('POST', '/returns', status: 201, body: const {});

      await OrdersRepository.instance.requestReturn(
        orderId: 'order-1',
        reason: 'damaged',
        items: [(orderItemId: 'item-0', quantity: 2)],
      );

      final body = api.calls.single.json;
      expect(body['refund_method'], 'original_payment');
      expect(body['items'], [
        {'order_item_id': 'item-0', 'quantity': 2},
      ]);
    });

    test('both request lists are merged, under either key', () async {
      api.on(
        'GET',
        '/order-cancellations',
        body: {
          'requests': [
            {'id': 'c1', 'request_number': 'CAN-1', 'status': 'PENDING'},
          ],
        },
      );
      api.on(
        'GET',
        '/returns',
        body: {
          'returns': [
            {'id': 'r1', 'return_number': 'RET-1', 'status': 'approved'},
          ],
        },
      );

      final requests = await OrdersRepository.instance.requests();
      expect(requests.map((r) => r.number), ['CAN-1', 'RET-1']);
      expect(requests.first.isReturn, isFalse);
      expect(requests.last.isReturn, isTrue);
      expect(requests.first.status, 'pending', reason: 'lowercased');
    });

    test('one list failing does not hide the other', () async {
      api.on('GET', '/order-cancellations', status: 500, body: {'error': 'x'});
      api.on(
        'GET',
        '/returns',
        body: {
          'returns': [
            {'id': 'r1', 'return_number': 'RET-1'},
          ],
        },
      );

      final requests = await OrdersRepository.instance.requests();
      expect(requests.map((r) => r.number), ['RET-1']);
    });
  });
}

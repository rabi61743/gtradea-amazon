import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/data/orders_repository.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:gtradea_amazon/features/orders/widgets/order_shipment_summary.dart';

import 'support/orders.dart';

const _five = CartLine(
  productId: 'cup',
  title: 'Extra large water cup',
  unitPrice: 268,
  quantity: 5,
);

Future<Order> _open(
  WidgetTester tester, {
  required OrderStage reached,
  String status = 'processing',
  OrderTracking? tracking,
}) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  var order = seedOrder(reached: reached, status: status, lines: const [_five]);
  if (tracking != null) {
    order = order.withTracking(tracking);
    OrderStore.instance.seedForTest([order]);
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OrderDetailScreen(orderId: order.id),
    ),
  );
  await tester.pump();
  return order;
}

/// The number on one tile of the grid.
int _tile(WidgetTester tester, String label) {
  final tile = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final number = find
      .descendant(of: tile.first, matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .firstWhere((t) => int.tryParse(t) != null);
  return int.parse(number);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OrderStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('the counts', () {
    testWidgets('say how many pieces were ordered', (tester) async {
      await _open(tester, reached: OrderStage.placed);

      expect(find.text('Order Summary'), findsOneWidget);
      expect(_tile(tester, 'Items Ordered'), 5);
    });

    testWidgets('and put them all in processing before anything ships', (
      tester,
    ) async {
      await _open(tester, reached: OrderStage.confirmed);

      expect(_tile(tester, 'Items Processing'), 5);
      expect(_tile(tester, 'Items in Transit'), 0);
      expect(_tile(tester, 'Items Delivered'), 0);
    });

    testWidgets('in transit once the carrier has them', (tester) async {
      await _open(tester, reached: OrderStage.shipped, status: 'shipped');

      expect(_tile(tester, 'Items in Transit'), 5);
      expect(_tile(tester, 'Items Processing'), 0);
    });

    testWidgets('and delivered once they have arrived', (tester) async {
      await _open(tester, reached: OrderStage.delivered, status: 'delivered');

      expect(_tile(tester, 'Items Delivered'), 5);
      expect(_tile(tester, 'Items in Transit'), 0);
    });

    testWidgets('split per parcel where the shop assigned the items', (
      tester,
    ) async {
      // Two legs, two counts, two different stages: the split is the server's
      // own, and each parcel answers for what is in it.
      final tracking = OrderTracking.fromJson({
        'shipments': [
          {
            'shipmentNo': 'SHIP-A',
            'mode': 'air',
            'modeLabel': 'Air Freight',
            'itemCount': 2,
            'timeline': [
              {'stage': 'DELIVERED', 'label': 'Delivered', 'status': 'done'},
            ],
          },
          {
            'shipmentNo': 'SHIP-B',
            'mode': 'land',
            'modeLabel': 'Surface Freight',
            'itemCount': 3,
            'timeline': [
              {'stage': 'TRANSIT', 'label': 'In transit', 'status': 'current'},
            ],
          },
        ],
      });

      await _open(
        tester,
        reached: OrderStage.shipped,
        status: 'shipped',
        tracking: tracking,
      );

      expect(_tile(tester, 'Items Delivered'), 2);
      expect(_tile(tester, 'Items in Transit'), 3);
      expect(_tile(tester, 'Items Ordered'), 5);
    });

    testWidgets('and the parcels are listed with what is in each', (
      tester,
    ) async {
      final tracking = OrderTracking.fromJson({
        'shipments': [
          {
            'shipmentNo': 'Shipment A',
            'mode': 'air',
            'modeLabel': 'Air Freight',
            'itemCount': 2,
            'stageMessage': 'In Transit',
            'timeline': [
              {'stage': 'TRANSIT', 'label': 'Flown out', 'status': 'done'},
            ],
          },
          {
            'shipmentNo': 'Shipment B',
            'mode': 'land',
            'modeLabel': 'Surface Freight',
            'itemCount': 3,
            'stageMessage': 'Overseas Processing',
            'timeline': [
              {'stage': 'PACKED', 'label': 'Packed', 'status': 'done'},
            ],
          },
        ],
      });

      await _open(
        tester,
        reached: OrderStage.shipped,
        status: 'shipped',
        tracking: tracking,
      );

      await tester.scrollUntilVisible(
        find.text('Shipments'),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();

      // Named twice over, and rightly: once in this summary, once as the
      // heading of its own steps in the journey below.
      expect(find.text('Shipment A'), findsWidgets);
      expect(find.textContaining('Air Freight'), findsWidgets);
      expect(find.text('2 Items'), findsOneWidget);
      expect(find.text('3 Items'), findsOneWidget);
      // The shop's own words for where the parcel is: on the summary, and on
      // the journey heading below.
      expect(find.text('In Transit'), findsWidgets);
    });
  });

  group('what it will not claim', () {
    test('an unsplit order puts every piece in one bucket, not a guess', () {
      // No item assignment from the server, so the order's own stage speaks
      // for all of it rather than this inventing a division.
      final order = seedOrder(
        reached: OrderStage.shipped,
        status: 'shipped',
        lines: const [_five],
      );
      final tally = OrderItemTally.of(order, DateTime.now());

      expect(tally.perParcel, isFalse);
      expect(tally.inTransit, 5);
      expect(tally.delivered + tally.processing, 0);
    });
  });
}

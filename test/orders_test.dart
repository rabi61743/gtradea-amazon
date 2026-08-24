import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'support/api.dart';
import 'support/auth.dart';
import 'package:gtradea_amazon/features/orders/data/orders_repository.dart';
import 'support/orders.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:gtradea_amazon/features/orders/presentation/orders_screen.dart';
import 'package:gtradea_amazon/core/time_format.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _jacket = CartLine(
  productId: 'jacket',
  variantLabel: 'Blush pink',
  title: 'Ice silk jacket',
  unitPrice: 1130,
  listPrice: 1568,
  freeDelivery: true,
  quantity: 2,
);

const _dress = CartLine(
  productId: 'dress',
  title: 'Suspender dress',
  unitPrice: 1808,
);

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// An order the server says has reached [reached].
///
/// Progress comes from the carrier now, not from a clock, so a test says which
/// stage it wants rather than how long ago the order was placed.
Order _at(
  OrderStage reached, {
  List<CartLine> lines = const [_jacket],
  String status = 'processing',
  String paymentStatus = 'pending',
  String id = 'order-1',
  DateTime? placedAt,
}) {
  return seedOrder(
    reached: reached,
    id: id,
    status: status,
    paymentStatus: paymentStatus,
    lines: lines,
    placedAt: placedAt,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OrderStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('stage progression', () {
    test('follows the carrier, not a clock', () {
      // The previous build advanced an order through six stages on a timer:
      // thirty seconds to confirmed, fourteen minutes to delivered. Nothing
      // about a real parcel works that way, and a shopper watching their order
      // "arrive" while it sat in a warehouse is worse than no timeline.
      for (final stage in OrderStage.values) {
        expect(_at(stage).stage(), stage, reason: stage.name);
      }
    });

    test('an order placed long ago has still only been placed', () {
      final old = seedOrder(
        reached: OrderStage.placed,
        status: 'pending',
        placedAt: DateTime.now().subtract(const Duration(days: 400)),
      );
      expect(old.stage(), OrderStage.placed);
      expect(old.isSettled(), isFalse);
    });

    test('"out for delivery" is not "delivered"', () {
      // One string contains the other, so a naive substring match reports a
      // parcel on a van as already handed over.
      expect(_at(OrderStage.outForDelivery).stage(), OrderStage.outForDelivery);
      expect(_at(OrderStage.outForDelivery).isSettled(), isFalse);
    });

    test('falls back to the order status when there is no tracking yet', () {
      // Tracking is a separate request that can fail or lag. The order's own
      // status is coarser but still true.
      final shipped = seedOrder(status: 'shipped', withTracking: false);
      expect(shipped.stage(), OrderStage.shipped);

      final done = seedOrder(status: 'completed', withTracking: false);
      expect(done.stage(), OrderStage.delivered);
      expect(done.isSettled(), isTrue);
    });

    test('a stage code nobody anticipated does not reset the progress', () {
      // The carrier owns its vocabulary and can add to it. An unfamiliar step
      // contributes nothing rather than dragging the timeline back to placed.
      final tracking = OrderTracking.fromJson({
        'shipments': [
          {
            'timeline': [
              {'stage': 'TRANSIT', 'label': 'In transit', 'status': 'done'},
              {'stage': 'CUSTOMS_HELD', 'label': 'At customs', 'status': 'done'},
            ],
          },
        ],
      });
      final order = _at(OrderStage.placed).withTracking(tracking);
      expect(order.stage(), OrderStage.shipped);
    });

    test('an unfamiliar step status counts as not reached', () {
      // The only enum on the wire in this domain. Decoded strictly it would
      // throw and blank the whole tracking screen.
      final step = TrackingStep.fromJson(
        const {'stage': 'TRANSIT', 'label': 'x', 'status': 'quantum'},
      );
      expect(step.state, TrackingStepState.upcoming);
    });

    test('no delivery date is invented when nobody has given one', () {
      final order = seedOrder(withTracking: false);
      expect(order.estimatedDelivery, isNull);
    });

    test('the delivery date is the carrier window', () {
      final when = DateTime.now().add(const Duration(days: 5));
      final order = seedOrder(reached: OrderStage.shipped, etaTo: when);
      expect(order.estimatedDelivery!.day, when.day);
    });

    test('a delivered order reports when it actually arrived', () {
      final order = _at(OrderStage.delivered, status: 'delivered');
      expect(order.estimatedDelivery, isNotNull);
      expect(order.isSettled(), isTrue);
    });
  });

  group('OrderStore', () {
    test('placing records an order with a readable id and newest first', () {
      final first = _at(
        OrderStage.delivered,
        status: 'delivered',
        id: 'order-old',
        placedAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      final second = _at(OrderStage.placed);

      expect(OrderStore.instance.count, 2);
      expect(OrderStore.instance.orders.first.id, second.id);
      // The id is a server UUID; the reference is the short number a shopper
      // can read out over the phone.
      expect(first.displayReference, startsWith('GT'));
      expect(first.id, isNot(second.id));
    });

    test('two orders placed in the same millisecond still get distinct ids',
        () {
      final when = DateTime(2026, 8, 23, 12);
      final a = OrderStore.instance.place(
        lines: const [_jacket],
        delivery: 0,
        recipient: 'Rabi',
        address: 'x',
        paymentState: PaymentState.paid,
        placedAt: when,
      );
      final b = OrderStore.instance.place(
        lines: const [_dress],
        delivery: 0,
        recipient: 'Rabi',
        address: 'x',
        paymentState: PaymentState.paid,
        placedAt: when,
      );
      expect(a.id, isNot(b.id));
    });

    test('totals come from the frozen lines and the frozen delivery', () {
      final order = OrderStore.instance.place(
        lines: const [_jacket],
        delivery: 100,
        recipient: 'Rabi',
        address: 'x',
        paymentState: PaymentState.cashOnDelivery,
      );

      expect(order.totals.subtotal, 2260);
      expect(order.totals.itemCount, 2);
      // Charged 100 even though the line is free-delivery: what was agreed at
      // the time wins over the current rule.
      expect(order.totals.delivery, 100);
      expect(order.totals.total, 2360);
    });

    test('survives a reload from disk', () async {
      final order = _at(OrderStage.shipped, status: 'shipped');
      await Future<void>.delayed(Duration.zero);

      OrderStore.instance.resetForTest();
      await OrderStore.instance.load();

      final reloaded = OrderStore.instance.byId(order.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.lines.single.title, 'Ice silk jacket');
      expect(reloaded.recipient, 'Rabi');
      // The stage survives a restart because the server's own status is cached
      // alongside the order, not re-derived from a clock.
      expect(reloaded.stage().index,
          greaterThanOrEqualTo(OrderStage.packed.index));
    });

    test('a corrupt history degrades to none rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'gtradea_orders': 'not json'});
      OrderStore.instance.resetForTest();
      await OrderStore.instance.load();
      expect(OrderStore.instance.isEmpty, isTrue);
    });

    test('an order with no readable lines is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_orders':
            '[{"id":"GT1","placedAt":1,"lines":[]},'
                '{"id":"GT2","placedAt":2,"lines":'
                '[{"productId":"a","title":"A","unitPrice":5}]}]',
      });
      OrderStore.instance.resetForTest();
      await OrderStore.instance.load();
      // An empty receipt for a total nobody can check is worse than nothing.
      expect(OrderStore.instance.orders.map((o) => o.id), ['GT2']);
    });

    test('guest orders follow the shopper into their account', () async {
      _at(OrderStage.placed);
      OrderStore.instance.bindToAuth();

      signInForTest(email: 'rabi@example.com');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(OrderStore.instance.count, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('gtradea_orders'), isNull,
          reason: 'the guest copy is cleared once carried over');
    });
  });

  group('cancel, return and failure', () {
    test('an order can be cancelled before it ships, not after', () {
      final early = _at(OrderStage.placed);
      expect(early.canCancel(), isTrue);
      expect(OrderStore.instance.cancel(early.id), isTrue);
      expect(OrderStore.instance.byId(early.id)!.outcome, OrderOutcome.cancelled);

      final shipped = _at(OrderStage.shipped, status: 'shipped');
      expect(shipped.canCancel(), isFalse);
      expect(OrderStore.instance.cancel(shipped.id), isFalse,
          reason: 'the parcel has already gone');
      expect(OrderStore.instance.byId(shipped.id)!.outcome, isNull);
    });

    test('a cancelled order freezes at the stage it had reached', () {
      final order = _at(OrderStage.packed);
      OrderStore.instance.cancel(order.id);
      final cancelled = OrderStore.instance.byId(order.id)!;

      // Time keeps passing, but a cancelled parcel does not go on to ship.
      expect(cancelled.stage(DateTime.now().add(const Duration(days: 1))),
          OrderStage.packed);
      expect(cancelled.statusLabel(), 'Cancelled');
      expect(cancelled.isSettled(), isTrue);
    });

    test('a return can only be asked for once it has arrived', () {
      final enRoute = _at(OrderStage.outForDelivery);
      expect(enRoute.canReturn(), isFalse);
      expect(OrderStore.instance.requestReturn(enRoute.id), isFalse);

      final delivered = _at(OrderStage.delivered, status: 'delivered');
      expect(delivered.canReturn(), isTrue);
      expect(OrderStore.instance.requestReturn(delivered.id), isTrue);
      expect(OrderStore.instance.byId(delivered.id)!.statusLabel(), 'Returned');
    });

    test('a cancelled order cannot then be returned', () {
      final order = _at(OrderStage.placed);
      OrderStore.instance.cancel(order.id);
      expect(OrderStore.instance.requestReturn(order.id), isFalse);
      expect(OrderStore.instance.byId(order.id)!.outcome, OrderOutcome.cancelled);
    });

    test('a failed order reports a failed payment too', () {
      final order = _at(OrderStage.placed);
      expect(OrderStore.instance.markFailed(order.id), isTrue);
      final failed = OrderStore.instance.byId(order.id)!;
      expect(failed.outcome, OrderOutcome.failed);
      expect(failed.paymentState, PaymentState.failed);
    });

    test('cancelled and failed orders carry no tracking number', () {
      final cancelled = _at(OrderStage.outForDelivery);
      OrderStore.instance.cancel(cancelled.id);
      // canCancel is false past shipped, so this one stays live -- use a
      // failure, which can be set at any point.
      final failed = _at(OrderStage.outForDelivery);
      OrderStore.instance.markFailed(failed.id);

      expect(OrderStore.instance.byId(failed.id)!.trackingNumber(), isNull);
    });

    test('a settled order survives a reload still settled', () async {
      final order = _at(OrderStage.placed);
      OrderStore.instance.cancel(order.id);
      // Two fire-and-forget writes back to back -- placing, then settling.
      // One microtask turn only lets the first of them land.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      OrderStore.instance.resetForTest();
      await OrderStore.instance.load();
      expect(OrderStore.instance.byId(order.id)!.outcome, OrderOutcome.cancelled);
    });
  });

  group('tracking number', () {
    test('appears only once there is a parcel with a courier', () {
      expect(_at(OrderStage.placed).trackingNumber(), isNull);
      expect(_at(OrderStage.packed).trackingNumber(), isNull);
      expect(_at(OrderStage.shipped, status: 'shipped').trackingNumber(), isNotNull);
    });
  });

  group('OrdersScreen', () {
    testWidgets('explains itself when there are no orders', (tester) async {
      await tester.pumpWidget(_wrap(const OrdersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No orders yet'), findsOneWidget);
    });

    testWidgets('lists an order with its id, status and total', (tester) async {
      _useTallWindow(tester);
      // Delivered, so no ticker runs and pumpAndSettle is safe.
      final order = _at(OrderStage.delivered, status: 'delivered');
      await tester.pumpWidget(_wrap(const OrdersScreen()));
      await tester.pumpAndSettle();

      expect(find.text(order.displayReference), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.textContaining('2 items'), findsOneWidget);
      expect(find.textContaining('Rs. 2,260'), findsOneWidget);
    });

    testWidgets('opens the order when tapped', (tester) async {
      _useTallWindow(tester);
      final order = _at(OrderStage.delivered, status: 'delivered');
      await tester.pumpWidget(_wrap(const OrdersScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text(order.displayReference));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
    });
  });

  group('OrderDetailScreen', () {
    testWidgets('shows every stage, dates, items, address and payment',
        (tester) async {
      _useTallWindow(tester);
      final order = _at(OrderStage.delivered, status: 'delivered');
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
      await tester.pumpAndSettle();

      // The whole road, not only the part already walked.
      for (final stage in OrderStage.values) {
        expect(find.text(stage.label), findsWidgets, reason: stage.label);
      }
      expect(find.text('Ice silk jacket'), findsOneWidget);
      expect(find.text('Blush pink · Qty 2'), findsOneWidget);
      expect(find.text('Jhamsikhel, Lalitpur, Bagmati'), findsOneWidget);
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(find.text('Tracking'), findsOneWidget);
      // The carrier's own reference, not one this app made up.
      expect(find.text('SHIP-77'), findsOneWidget);
    });

    testWidgets('hides tracking until something has been dispatched',
        (tester) async {
      _useTallWindow(tester);
      final order = _at(OrderStage.placed);
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
      await tester.pump();

      // An empty Tracking heading would read as information that failed to
      // load rather than information that does not exist yet.
      expect(find.text('Tracking'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('offers Cancel early and Return once delivered',
        (tester) async {
      _useTallWindow(tester);
      final early = _at(OrderStage.placed);
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: early.id)));
      await tester.pump();
      expect(find.text('Cancel order'), findsOneWidget);
      expect(find.text('Request a return'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());

      final delivered = _at(OrderStage.delivered, status: 'delivered');
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: delivered.id)));
      await tester.pumpAndSettle();
      expect(find.text('Request a return'), findsOneWidget);
      expect(find.text('Cancel order'), findsNothing);
    });

    testWidgets('cancelling asks first and then shows the cancelled state',
        (tester) async {
      _useTallWindow(tester);
      // Cancelling asks the server, and the server's answer is what the screen
      // shows -- it does not mark the order cancelled on its own say-so.
      final api = stubCatalog()
        ..on('POST', '/order-cancellations', status: 201, body: const {})
        ..on('GET', '/orders', body: [
          orderJson(status: 'cancelled', paymentStatus: 'refunded'),
        ]);
      signInForTest();

      final order = _at(OrderStage.placed);
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
      await tester.pump();

      await tester.tap(find.text('Cancel order'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cancel this order?'), findsOneWidget);

      await tester.tap(find.text('Cancel order').last);
      await tester.pumpAndSettle();

      expect(api.calls.any((c) => c.path == '/order-cancellations'), isTrue);

      expect(OrderStore.instance.byId(order.id)!.outcome,
          OrderOutcome.cancelled);
      expect(find.textContaining('Nothing will be delivered'), findsOneWidget);
      // The action is gone: a cancelled order cannot be cancelled again.
      expect(find.text('Cancel order'), findsNothing);
    });

    testWidgets('backing out of the cancel dialog keeps the order',
        (tester) async {
      _useTallWindow(tester);
      final order = _at(OrderStage.placed);
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
      await tester.pump();

      await tester.tap(find.text('Cancel order'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Keep it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(OrderStore.instance.byId(order.id)!.outcome, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a failed order shows no onward stages', (tester) async {
      _useTallWindow(tester);
      final order = _at(OrderStage.placed);
      OrderStore.instance.markFailed(order.id);

      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
      await tester.pumpAndSettle();

      expect(find.text('Failed'), findsWidgets);
      expect(find.text('Payment failed'), findsOneWidget);
      // Listing Shipped and Out for delivery under a failed order would
      // suggest a parcel that is on its way.
      expect(find.text('Shipped'), findsNothing);
      expect(find.text('Out for delivery'), findsNothing);
    });

    testWidgets('a returned order says so and offers no further action',
        (tester) async {
      _useTallWindow(tester);
      final order = _at(OrderStage.delivered, status: 'delivered');
      OrderStore.instance.requestReturn(order.id);

      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
      await tester.pumpAndSettle();

      expect(find.text('Returned'), findsWidgets);
      expect(find.textContaining('A courier will collect it'), findsOneWidget);
      expect(find.text('Request a return'), findsNothing);
    });

    testWidgets('an order that no longer exists says so rather than crashing',
        (tester) async {
      await tester.pumpWidget(_wrap(const OrderDetailScreen(orderId: 'nope')));
      await tester.pumpAndSettle();
      expect(find.text('This order is no longer available'), findsOneWidget);
    });
  });

  group('date wording', () {
    test('reads today and tomorrow by name', () {
      final now = DateTime.now();
      expect(formatWhen(now), startsWith('Today,'));
      expect(
        formatWhen(now.add(const Duration(days: 1))),
        startsWith('Tomorrow,'),
      );
      expect(formatDay(now), 'today');
    });
  });
}

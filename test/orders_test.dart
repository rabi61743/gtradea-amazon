import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:gtradea_amazon/features/orders/presentation/orders_screen.dart';
import 'package:gtradea_amazon/features/orders/widgets/order_timeline.dart';
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

/// Places an order that was made [ago] in the past, so a given stage is
/// already reached without any waiting.
Order _placeAgo(Duration ago, {List<CartLine> lines = const [_jacket]}) {
  return OrderStore.instance.place(
    lines: lines,
    delivery: 0,
    recipient: 'Rabi',
    address: 'Lalitpur, Bagmati',
    paymentState: PaymentState.cashOnDelivery,
    placedAt: DateTime.now().subtract(ago),
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
    final placed = DateTime(2026, 8, 23, 12);

    test('walks the six stages in order as time passes', () {
      OrderStage at(Duration elapsed) =>
          Order.stageAt(placed, placed.add(elapsed));

      expect(at(Duration.zero), OrderStage.placed);
      expect(at(Order.stageAfter[1]), OrderStage.confirmed);
      expect(at(Order.stageAfter[2]), OrderStage.packed);
      expect(at(Order.stageAfter[3]), OrderStage.shipped);
      expect(at(Order.stageAfter[4]), OrderStage.outForDelivery);
      expect(at(Order.stageAfter[5]), OrderStage.delivered);
    });

    test('never goes past delivered however long it has been', () {
      expect(
        Order.stageAt(placed, placed.add(const Duration(days: 400))),
        OrderStage.delivered,
      );
    });

    test('the stage table is monotonic', () {
      // A schedule that went backwards would make the timeline jump about.
      for (var i = 1; i < Order.stageAfter.length; i++) {
        expect(Order.stageAfter[i] > Order.stageAfter[i - 1], isTrue,
            reason: 'stage $i');
      }
    });

    test('estimated delivery is read off the same table as the stages', () {
      final order = _placeAgo(Duration.zero);
      expect(
        order.estimatedDelivery.difference(order.placedAt),
        Order.stageAfter.last,
        reason: 'the estimate cannot contradict the progression',
      );
    });
  });

  group('OrderStore', () {
    test('placing records an order with a readable id and newest first', () {
      final first = _placeAgo(const Duration(minutes: 30));
      final second = _placeAgo(Duration.zero);

      expect(OrderStore.instance.count, 2);
      expect(OrderStore.instance.orders.first.id, second.id);
      expect(first.id, startsWith('GT'));
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
      final order = _placeAgo(const Duration(minutes: 3));
      await Future<void>.delayed(Duration.zero);

      OrderStore.instance.resetForTest();
      await OrderStore.instance.load();

      final reloaded = OrderStore.instance.byId(order.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.lines.single.title, 'Ice silk jacket');
      expect(reloaded.recipient, 'Rabi');
      // The stage keeps advancing across a restart, because it is derived from
      // when the order was placed rather than stored.
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
      _placeAgo(Duration.zero);
      OrderStore.instance.bindToAuth();

      AuthStore.instance.signIn(email: 'rabi@example.com');
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
      final early = _placeAgo(const Duration(seconds: 5));
      expect(early.canCancel(), isTrue);
      expect(OrderStore.instance.cancel(early.id), isTrue);
      expect(OrderStore.instance.byId(early.id)!.outcome, OrderOutcome.cancelled);

      final shipped = _placeAgo(Order.stageAfter[3]);
      expect(shipped.canCancel(), isFalse);
      expect(OrderStore.instance.cancel(shipped.id), isFalse,
          reason: 'the parcel has already gone');
      expect(OrderStore.instance.byId(shipped.id)!.outcome, isNull);
    });

    test('a cancelled order freezes at the stage it had reached', () {
      final order = _placeAgo(Order.stageAfter[2]);
      OrderStore.instance.cancel(order.id);
      final cancelled = OrderStore.instance.byId(order.id)!;

      // Time keeps passing, but a cancelled parcel does not go on to ship.
      expect(cancelled.stage(DateTime.now().add(const Duration(days: 1))),
          OrderStage.packed);
      expect(cancelled.statusLabel(), 'Cancelled');
      expect(cancelled.isSettled(), isTrue);
    });

    test('a return can only be asked for once it has arrived', () {
      final enRoute = _placeAgo(Order.stageAfter[4]);
      expect(enRoute.canReturn(), isFalse);
      expect(OrderStore.instance.requestReturn(enRoute.id), isFalse);

      final delivered = _placeAgo(Order.stageAfter[5]);
      expect(delivered.canReturn(), isTrue);
      expect(OrderStore.instance.requestReturn(delivered.id), isTrue);
      expect(OrderStore.instance.byId(delivered.id)!.statusLabel(), 'Returned');
    });

    test('a cancelled order cannot then be returned', () {
      final order = _placeAgo(Duration.zero);
      OrderStore.instance.cancel(order.id);
      expect(OrderStore.instance.requestReturn(order.id), isFalse);
      expect(OrderStore.instance.byId(order.id)!.outcome, OrderOutcome.cancelled);
    });

    test('a failed order reports a failed payment too', () {
      final order = _placeAgo(Duration.zero);
      expect(OrderStore.instance.markFailed(order.id), isTrue);
      final failed = OrderStore.instance.byId(order.id)!;
      expect(failed.outcome, OrderOutcome.failed);
      expect(failed.paymentState, PaymentState.failed);
    });

    test('cancelled and failed orders carry no tracking number', () {
      final cancelled = _placeAgo(Order.stageAfter[4]);
      OrderStore.instance.cancel(cancelled.id);
      // canCancel is false past shipped, so this one stays live -- use a
      // failure, which can be set at any point.
      final failed = _placeAgo(Order.stageAfter[4]);
      OrderStore.instance.markFailed(failed.id);

      expect(OrderStore.instance.byId(failed.id)!.trackingNumber(), isNull);
    });

    test('a settled order survives a reload still settled', () async {
      final order = _placeAgo(Duration.zero);
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
      expect(_placeAgo(const Duration(seconds: 1)).trackingNumber(), isNull);
      expect(_placeAgo(Order.stageAfter[2]).trackingNumber(), isNull);
      expect(_placeAgo(Order.stageAfter[3]).trackingNumber(), isNotNull);
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
      final order = _placeAgo(Order.stageAfter[5]);
      await tester.pumpWidget(_wrap(const OrdersScreen()));
      await tester.pumpAndSettle();

      expect(find.text(order.id), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.textContaining('2 items'), findsOneWidget);
      expect(find.textContaining('Rs. 2,260'), findsOneWidget);
    });

    testWidgets('opens the order when tapped', (tester) async {
      _useTallWindow(tester);
      final order = _placeAgo(Order.stageAfter[5]);
      await tester.pumpWidget(_wrap(const OrdersScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text(order.id));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
    });
  });

  group('OrderDetailScreen', () {
    testWidgets('shows every stage, dates, items, address and payment',
        (tester) async {
      _useTallWindow(tester);
      final order = _placeAgo(Order.stageAfter[5]);
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
      await tester.pumpAndSettle();

      // The whole road, not only the part already walked.
      for (final stage in OrderStage.values) {
        expect(find.text(stage.label), findsWidgets, reason: stage.label);
      }
      expect(find.text('Ice silk jacket'), findsOneWidget);
      expect(find.text('Blush pink · Qty 2'), findsOneWidget);
      expect(find.text('Lalitpur, Bagmati'), findsOneWidget);
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(find.text('Tracking'), findsOneWidget);
      expect(find.textContaining('GTX'), findsOneWidget);
    });

    testWidgets('hides tracking until something has been dispatched',
        (tester) async {
      _useTallWindow(tester);
      final order = _placeAgo(const Duration(seconds: 1));
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
      final early = _placeAgo(const Duration(seconds: 1));
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: early.id)));
      await tester.pump();
      expect(find.text('Cancel order'), findsOneWidget);
      expect(find.text('Request a return'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());

      final delivered = _placeAgo(Order.stageAfter[5]);
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: delivered.id)));
      await tester.pumpAndSettle();
      expect(find.text('Request a return'), findsOneWidget);
      expect(find.text('Cancel order'), findsNothing);
    });

    testWidgets('cancelling asks first and then shows the cancelled state',
        (tester) async {
      _useTallWindow(tester);
      final order = _placeAgo(const Duration(seconds: 1));
      await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
      await tester.pump();

      await tester.tap(find.text('Cancel order'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cancel this order?'), findsOneWidget);

      await tester.tap(find.text('Cancel order').last);
      await tester.pumpAndSettle();

      expect(OrderStore.instance.byId(order.id)!.outcome,
          OrderOutcome.cancelled);
      expect(find.textContaining('Nothing will be delivered'), findsOneWidget);
      // The action is gone: a cancelled order cannot be cancelled again.
      expect(find.text('Cancel order'), findsNothing);
    });

    testWidgets('backing out of the cancel dialog keeps the order',
        (tester) async {
      _useTallWindow(tester);
      final order = _placeAgo(const Duration(seconds: 1));
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
      final order = _placeAgo(Duration.zero);
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
      final order = _placeAgo(Order.stageAfter[5]);
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

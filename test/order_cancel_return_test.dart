import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/data/orders_repository.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';
import 'support/orders.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

const _jacket = CartLine(
  productId: '900001',
  title: 'Fleece-Lined Jacket',
  unitPrice: 1200,
  quantity: 1,
);

const _boots = CartLine(
  productId: '900002',
  title: 'Waterproof Boots',
  unitPrice: 1060,
  quantity: 2,
);

/// A request row in the shape `/order-cancellations` and `/returns` answer
/// with.
Map<String, dynamic> _request({
  String id = 'req-1',
  String orderId = 'order-1',
  String status = 'pending',
  String reason = 'changed_mind',
  String? details,
  num? refundAmount,
  bool isReturn = false,
  String? refundedAt,
}) => {
  'id': id,
  'order_id': orderId,
  if (isReturn) 'return_number': 'RET-9001' else 'request_number': 'CAN-9001',
  'status': status,
  'reason': reason,
  'reason_details': details,
  'refund_amount': refundAmount,
  'created_at': DateTime(2026, 9, 1, 10).toUtc().toIso8601String(),
  'refunded_at': refundedAt,
};

/// Scrolls the order page until [finder] is built.
///
/// The page is a lazy list: a card below the fold is not merely off-screen,
/// it does not exist yet.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    OrderStore.instance.resetForTest();
  });

  tearDown(() {
    OrderStore.instance.resetForTest();
    clearApiStub();
  });

  /// The order on screen, with whatever the two request endpoints answer.
  Future<FakeApi> open(
    WidgetTester tester, {
    required OrderStage reached,
    String status = 'processing',
    List<CartLine> lines = const [_jacket],
    List<Map<String, dynamic>> cancellations = const [],
    List<Map<String, dynamic>> returns = const [],
    int cancelStatus = 201,
    Object? cancelBody,
  }) async {
    _tall(tester);
    final api = stubCatalog()
      ..on(
        'GET',
        '/orders',
        body: [orderJson(status: status, lines: lines)],
      )
      ..on('GET', '/order-cancellations', body: {'requests': cancellations})
      ..on('GET', '/returns', body: {'returns': returns})
      ..on(
        'POST',
        '/order-cancellations',
        status: cancelStatus,
        body: cancelBody ?? const {},
      )
      ..on('POST', '/returns', status: 201, body: const {})
      ..on(
        'POST',
        '/order-cancellations/req-1/withdraw',
        status: 200,
        body: const {},
      );
    signInForTest();

    final order = seedOrder(
      reached: reached,
      id: 'order-1',
      status: status,
      lines: lines,
    );
    // The requests are read with the orders, so the screen knows what the
    // shop already has in hand before it draws a button. Run for real: the
    // fake clock only advances while the tester pumps, and this awaits a
    // round trip rather than a frame.
    await tester.runAsync(() => OrderStore.instance.refreshFromServer());
    await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
    await tester.pumpAndSettle();
    return api;
  }

  group('cancelling an order', () {
    testWidgets('asks for a reason, and sends the one that was picked', (
      tester,
    ) async {
      final api = await open(tester, reached: OrderStage.placed);

      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ordered by mistake'));
      await tester.enterText(find.byType(TextField), 'Wrong size');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request cancellation'));
      await tester.pumpAndSettle();

      final sent = api.calls.firstWhere(
        (c) => c.method == 'POST' && c.path == '/order-cancellations',
      );
      expect(sent.json['order_id'], 'order-1');
      expect(sent.json['reason'], 'ordered_by_mistake');
      expect(sent.json['reason_details'], 'Wrong size');
    });

    testWidgets('and sends nothing until a reason is chosen', (tester) async {
      final api = await open(tester, reached: OrderStage.placed);

      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Request cancellation'),
            )
            .onPressed,
        isNull,
      );
      expect(
        api.calls.where((c) => c.method == 'POST'),
        isEmpty,
        reason: 'nothing sent yet',
      );
    });

    testWidgets('"Other" needs saying what happened', (tester) async {
      await open(tester, reached: OrderStage.placed);

      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other reason'));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(FilledButton, 'Request cancellation');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Duplicate order');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('a refusal is shown in the server\'s own words', (
      tester,
    ) async {
      await open(
        tester,
        reached: OrderStage.placed,
        cancelStatus: 409,
        cancelBody: {'message': 'This order has already been dispatched.'},
      );

      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I changed my mind'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request cancellation'));
      await tester.pumpAndSettle();

      expect(
        find.text('This order has already been dispatched.'),
        findsOneWidget,
      );
    });

    testWidgets('an order already under review offers no second request', (
      tester,
    ) async {
      await open(
        tester,
        reached: OrderStage.placed,
        cancellations: [_request()],
      );

      await reveal(tester, find.text('Cancellation request'));
      expect(find.text('Cancellation request'), findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
      expect(find.textContaining('CAN-9001'), findsOneWidget);
      // The button is gone: the shop has one in hand already.
      expect(find.text('Cancel order'), findsNothing);
    });

    testWidgets('and the store refuses to raise one anyway', (tester) async {
      // Belt and braces: the screen hides the button, and the store will not
      // send a second request even if something else calls it.
      await open(
        tester,
        reached: OrderStage.placed,
        cancellations: [_request()],
      );

      // Off-screen, so nothing is waiting on a frame while the store answers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final sent = await OrderStore.instance.requestCancellation('order-1');
      expect(sent, isFalse);
    });

    testWidgets('a pending one can be withdrawn', (tester) async {
      final api = await open(
        tester,
        reached: OrderStage.placed,
        cancellations: [_request()],
      );

      await reveal(tester, find.text('Withdraw request'));
      await tester.tap(find.text('Withdraw request'));
      await tester.pumpAndSettle();

      expect(
        api.calls.any((c) => c.path == '/order-cancellations/req-1/withdraw'),
        isTrue,
      );
    });

    testWidgets('a rejected one does not block another attempt', (
      tester,
    ) async {
      await open(
        tester,
        reached: OrderStage.placed,
        cancellations: [_request(status: 'rejected')],
      );

      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Cancel order'), findsOneWidget);
    });

    testWidgets('a delivered order is not offered cancellation at all', (
      tester,
    ) async {
      await open(tester, reached: OrderStage.delivered, status: 'delivered');

      expect(find.text('Cancel order'), findsNothing);
    });
  });

  group('returning what arrived', () {
    testWidgets('is offered once delivered, and asks what is going back', (
      tester,
    ) async {
      final api = await open(
        tester,
        reached: OrderStage.delivered,
        status: 'delivered',
        lines: const [_jacket, _boots],
      );

      await tester.tap(find.text('Request a return'));
      await tester.pumpAndSettle();

      // Scoped to the sheet: the order's own item list behind it names the
      // same product.
      final boots = find.descendant(
        of: find.byType(CheckboxListTile),
        matching: find.text('Waterproof Boots'),
      );
      expect(boots, findsOneWidget);
      // Two lines, so neither is assumed.
      final submit = find.widgetWithText(FilledButton, 'Request return');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.tap(boots);
      await tester.tap(find.text('Arrived damaged'));
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final sent = api.calls.firstWhere(
        (c) => c.method == 'POST' && c.path == '/returns',
      );
      expect(sent.json['order_id'], 'order-1');
      expect(sent.json['reason'], 'damaged');
      // Only the line that was ticked, with its own quantity.
      expect(sent.json['items'], [
        {'order_item_id': 'item-1', 'quantity': 2},
      ]);
    });

    testWidgets('a one-line order needs no picking', (tester) async {
      await open(tester, reached: OrderStage.delivered, status: 'delivered');

      await tester.tap(find.text('Request a return'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrong item sent'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Request return'),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('an open return stops a second one', (tester) async {
      await open(
        tester,
        reached: OrderStage.delivered,
        status: 'delivered',
        returns: [_request(id: 'ret-1', status: 'approved', isReturn: true)],
      );

      await reveal(tester, find.text('Return request'));
      expect(find.text('Return request'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Request a return'), findsNothing);
    });
  });

  group('what it says about the refund', () {
    testWidgets('nothing is called refunded until the shop says so', (
      tester,
    ) async {
      await open(
        tester,
        reached: OrderStage.delivered,
        status: 'delivered',
        returns: [_request(id: 'ret-1', status: 'received', isReturn: true)],
      );

      await reveal(tester, find.textContaining('Refund is being processed'));
      expect(find.text('Refunded'), findsNothing);
      expect(find.textContaining('Refund is being processed'), findsOneWidget);
    });

    testWidgets('and the amount is the one the shop sent', (tester) async {
      await open(
        tester,
        reached: OrderStage.delivered,
        status: 'delivered',
        returns: [
          _request(
            id: 'ret-1',
            status: 'refunded',
            isReturn: true,
            refundAmount: 2260,
            refundedAt: DateTime(2026, 9, 3).toUtc().toIso8601String(),
          ),
        ],
      );

      await reveal(tester, find.text('Refunded'));
      expect(find.text('Refunded'), findsOneWidget);
      await reveal(tester, find.textContaining('Rs. 2260'));
      expect(find.textContaining('Rs. 2260'), findsOneWidget);
    });

    test('an approved request is not a refunded one', () {
      const approved = OrderRequest(
        id: 'r',
        orderId: 'o',
        number: 'RET-1',
        status: 'approved',
        reason: 'damaged',
        isReturn: true,
      );
      expect(approved.isRefunded, isFalse);
      expect(approved.isOpen, isTrue);

      const refunded = OrderRequest(
        id: 'r',
        orderId: 'o',
        number: 'RET-1',
        status: 'refunded',
        reason: 'damaged',
        isReturn: true,
      );
      expect(refunded.isRefunded, isTrue);
      expect(refunded.isOpen, isFalse);
    });
  });
}

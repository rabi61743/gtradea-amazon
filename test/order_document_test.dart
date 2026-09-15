import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/data/orders_repository.dart';
import 'package:gtradea_amazon/features/orders/documents/order_document.dart';
import 'package:gtradea_amazon/features/orders/documents/order_document_pdf.dart';
import 'package:gtradea_amazon/features/orders/documents/order_document_saver.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/orders.dart';

const _jacket = CartLine(
  productId: '900001',
  title: 'Fleece-Lined Jacket',
  variantLabel: 'Colour: Navy / Size: L',
  unitPrice: 1200,
  quantity: 1,
);

const _boots = CartLine(
  productId: '900002',
  title: 'Waterproof Boots',
  unitPrice: 1060,
  quantity: 2,
);

ServerOrder _order({
  String status = 'delivered',
  Map<String, dynamic> extra = const {},
  List<CartLine> lines = const [_jacket, _boots],
}) => ServerOrder.fromJson({
  ...orderJson(status: status, lines: lines),
  ...extra,
});

bool _isPdf(Uint8List bytes) {
  final head = ascii.decode(bytes.sublist(0, 5));
  final tail = latin1.decode(bytes.sublist(bytes.length - 32));
  return head == '%PDF-' && tail.contains('%%EOF');
}

void main() {
  group('which document an order gets', () {
    test('completed or delivered is an invoice', () {
      for (final status in [
        'delivered',
        'completed',
        'complete',
        'fulfilled',
        'DELIVERED',
      ]) {
        expect(
          OrderDocumentKind.forStatus(status),
          OrderDocumentKind.invoice,
          reason: status,
        );
      }
    });

    test('anything short of that is a receipt', () {
      // Out for delivery contains "deliver" and is not delivered: an invoice
      // for a parcel still on the road is the mistake this guards against.
      for (final status in [
        'pending',
        'processing',
        'confirmed',
        'shipped',
        'out_for_delivery',
        'out-for-delivery',
        'delivery_failed',
        'cancelled',
        '',
      ]) {
        expect(
          OrderDocumentKind.forStatus(status),
          OrderDocumentKind.receipt,
          reason: status,
        );
      }
    });
  });

  group('what the document is made of', () {
    test('the order the server returned, line for line', () {
      final doc = OrderDocument.fromOrder(_order());

      expect(doc.kind, OrderDocumentKind.invoice);
      expect(doc.number, 'GT-1001');
      expect(doc.orderNumber, 'GT-1001');
      expect(doc.fileName, 'Invoice-GT-1001.pdf');
      expect(doc.status, 'Delivered');

      expect(doc.lines, hasLength(2));
      expect(doc.lines[0].name, 'Fleece-Lined Jacket');
      expect(doc.lines[0].variant, 'Colour: Navy / Size: L');
      expect(doc.lines[0].quantity, 1);
      expect(doc.lines[0].unitPrice, 1200);
      expect(doc.lines[1].quantity, 2);
      expect(doc.lines[1].amount, 2120);

      expect(doc.subtotal, 3320);
      // The server's total, not one worked out here.
      expect(doc.total, 2260);

      expect(doc.customerName, 'Rabi');
      expect(doc.customerPhone, '+9779812345678');
      expect(doc.addressLines, contains('Jhamsikhel'));
      expect(doc.addressLines, contains('Nepal'));
      expect(doc.paymentMethod, 'Cash on delivery');
      expect(doc.paymentStatus, 'Pending');
    });

    test('a receipt is named for itself', () {
      final doc = OrderDocument.fromOrder(_order(status: 'out_for_delivery'));

      expect(doc.kind, OrderDocumentKind.receipt);
      expect(doc.fileName, 'Receipt-GT-1001.pdf');
      expect(doc.status, 'Out for delivery');
    });

    test('the server number and file name win when it sends them', () {
      final numbered = OrderDocument.fromOrder(
        _order(extra: {'invoice_number': 'INV-0077'}),
      );
      expect(numbered.number, 'INV-0077');
      expect(numbered.fileName, 'Invoice-INV-0077.pdf');

      final named = OrderDocument.fromOrder(
        _order(extra: {'invoice_file_name': 'GT invoice 77'}),
      );
      expect(named.fileName, 'GT-invoice-77.pdf');

      final receipt = OrderDocument.fromOrder(
        _order(
          status: 'processing',
          extra: {'receipt_number': 'RCT-12', 'invoice_number': 'INV-9'},
        ),
      );
      expect(receipt.fileName, 'Receipt-RCT-12.pdf');
    });

    test('charges and billing appear only when the server has them', () {
      final itemised = OrderDocument.fromOrder(
        _order(
          extra: {
            'shipping_amount': '150',
            'discount_amount': 100,
            'coupon_code': 'DASHAIN',
            'tax_amount': 50,
            'billing_address': {
              'companyName': 'Himal Traders',
              'taxId': '601234567',
            },
          },
        ),
      );
      expect(itemised.delivery, 150);
      expect(itemised.discount, 100);
      expect(itemised.couponCode, 'DASHAIN');
      expect(itemised.tax, 50);
      expect(itemised.taxFromServer, isTrue);
      expect(itemised.adjustment, isNull, reason: 'it is broken down');
      expect(itemised.companyName, 'Himal Traders');
      expect(itemised.taxId, '601234567');

      // The fixture sends none of them: nothing is invented to fill the gap,
      // and the difference to the server's total is shown for what it is.
      final bare = OrderDocument.fromOrder(_order());
      expect(bare.delivery, isNull);
      expect(bare.discount, isNull);
      expect(bare.companyName, isNull);
      expect(bare.taxFromServer, isFalse);
      expect(bare.adjustment, 2260 - 3320);
    });

    test('the signed-in address fills in only where the order has none', () {
      final doc = OrderDocument.fromOrder(
        _order(),
        accountEmail: 'rabi@example.com',
      );
      expect(doc.customerEmail, 'rabi@example.com');

      final own = OrderDocument.fromOrder(
        _order(extra: {'customer_email': 'orders@himal.com'}),
        accountEmail: 'rabi@example.com',
      );
      expect(own.customerEmail, 'orders@himal.com');
    });
  });

  group('the PDF', () {
    testWidgets('is a real PDF, for both kinds', (tester) async {
      for (final status in ['delivered', 'processing']) {
        final bytes = await tester.runAsync(
          () => renderOrderDocument(
            OrderDocument.fromOrder(
              _order(
                status: status,
                // A title the embedded font cannot draw all of, as supplier
                // titles often are. It must not break the page.
                lines: const [
                  _jacket,
                  CartLine(
                    productId: '900003',
                    title: '超级软 Slippers',
                    unitPrice: 317,
                    quantity: 3,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(bytes, isNotNull);
        expect(_isPdf(bytes!), isTrue, reason: status);
        expect(bytes.length, greaterThan(2000));
      }
    });
  });

  group('downloading', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      CartStore.instance.resetForTest();
      OrderStore.instance.resetForTest();
    });

    tearDown(() {
      OrderDocumentSaver.saveOverride = null;
      OrderStore.instance.resetForTest();
      clearApiStub();
    });

    testWidgets('reads the order afresh and saves it under its own name', (
      tester,
    ) async {
      signInForTest(email: 'rabi@example.com');
      final api = stubCatalog()
        ..on(
          'GET',
          '/orders/order-1',
          body: orderJson(status: 'completed', lines: const [_jacket]),
        );

      String? savedName;
      Uint8List? savedBytes;
      OrderDocumentSaver.saveOverride = (name, bytes) async {
        savedName = name;
        savedBytes = bytes;
        return '/Download/$name';
      };

      final result = await tester.runAsync(
        () => OrderDocuments.download('order-1', accountEmail: 'rabi@example.com'),
      );

      expect(
        api.calls.where((c) => c.method == 'GET' && c.path == '/orders/order-1'),
        isNotEmpty,
        reason: 'the server is asked at the moment of the download',
      );
      expect(result!.kind, OrderDocumentKind.invoice);
      expect(result.fileName, 'Invoice-GT-1001.pdf');
      expect(savedName, 'Invoice-GT-1001.pdf');
      expect(_isPdf(savedBytes!), isTrue);
    });

    testWidgets('a closed save dialog is not an error', (tester) async {
      signInForTest();
      stubCatalog().on(
        'GET',
        '/orders/order-1',
        body: orderJson(status: 'shipped', lines: const [_jacket]),
      );
      OrderDocumentSaver.saveOverride = (name, bytes) async => null;

      final result = await tester.runAsync(
        () => OrderDocuments.download('order-1'),
      );
      expect(result, isNull);
    });

    testWidgets('an order the server will not give out is refused', (
      tester,
    ) async {
      // Somebody else's order, or one that is gone: the server's answer is
      // the whole of the access check.
      signInForTest();
      stubCatalog().on(
        'GET',
        '/orders/order-9',
        status: 404,
        body: {'error': 'Order not found'},
      );
      var saved = false;
      OrderDocumentSaver.saveOverride = (name, bytes) async {
        saved = true;
        return name;
      };

      Object? thrown;
      await tester.runAsync(() async {
        try {
          await OrderDocuments.download('order-9');
        } catch (e) {
          thrown = e;
        }
      });
      expect(thrown, isA<ApiError>());
      expect(saved, isFalse, reason: 'nothing is written');
    });

    testWidgets('an order with no items is not printed', (tester) async {
      signInForTest();
      stubCatalog().on(
        'GET',
        '/orders/order-1',
        body: orderJson(status: 'delivered'),
      );

      Object? thrown;
      await tester.runAsync(() async {
        try {
          await OrderDocuments.download('order-1');
        } catch (e) {
          thrown = e;
        }
      });
      expect(thrown, isA<OrderDocumentUnavailable>());
    });
  });

  group('on the order page', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      CartStore.instance.resetForTest();
      OrderStore.instance.resetForTest();
    });

    tearDown(() {
      OrderDocumentSaver.saveOverride = null;
      OrderStore.instance.resetForTest();
      clearApiStub();
    });

    Future<void> open(
      WidgetTester tester, {
      required String status,
      required OrderStage reached,
    }) async {
      tester.view.physicalSize = const Size(1200, 3400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      stubCatalog()
        ..on(
          'GET',
          '/orders',
          body: [orderJson(status: status, lines: const [_jacket])],
        )
        ..on(
          'GET',
          '/orders/order-1',
          body: orderJson(status: status, lines: const [_jacket]),
        )
        ..on('GET', '/order-cancellations', body: {'requests': []})
        ..on('GET', '/returns', body: {'returns': []});
      signInForTest();
      seedOrder(
        reached: reached,
        id: 'order-1',
        status: status,
        lines: const [_jacket],
      );
      await tester.runAsync(() => OrderStore.instance.refreshFromServer());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const OrderDetailScreen(orderId: 'order-1'),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> reveal(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a delivered order offers its invoice', (tester) async {
      await open(tester, status: 'delivered', reached: OrderStage.delivered);
      await reveal(tester, find.text('Download invoice'));

      expect(find.text('Download invoice'), findsOneWidget);
      expect(find.text('Download receipt'), findsNothing);
    });

    testWidgets('an order on its way offers a receipt instead', (tester) async {
      await open(
        tester,
        status: 'out_for_delivery',
        reached: OrderStage.outForDelivery,
      );
      await reveal(tester, find.text('Download receipt'));

      expect(find.text('Download receipt'), findsOneWidget);
      expect(find.text('Download invoice'), findsNothing);
    });

    testWidgets('tapping it saves the PDF and says where', (tester) async {
      await open(tester, status: 'delivered', reached: OrderStage.delivered);
      await reveal(tester, find.text('Download invoice'));

      String? savedName;
      OrderDocumentSaver.saveOverride = (name, bytes) async {
        savedName = name;
        return '/Download/$name';
      };

      await tester.tap(find.text('Download invoice'));
      await tester.pump();
      // The loading state, while the order is fetched and the PDF drawn.
      expect(find.text('Preparing invoice…'), findsOneWidget);

      // The fetch and the rendering are real work, not frames.
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && savedName == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();

      expect(savedName, 'Invoice-GT-1001.pdf');
      expect(find.text('Invoice saved as Invoice-GT-1001.pdf'), findsOneWidget);
      expect(find.text('Download invoice'), findsOneWidget, reason: 'ready again');
    });
  });
}

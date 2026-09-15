import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/restock/data/restock_requests.dart';
import 'package:gtradea_amazon/features/restock/presentation/restock_request_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

const _id = '825709571788';
const _title = 'Quick-drying polo, every colour sold out';

late FakeApi api;

/// This account's requests as the server holds them.
late List<Map<String, dynamic>> _server;

Map<String, dynamic> _row({
  String id = 'r-1',
  String status = 'pending',
  String? sourceId = _id,
}) => {
  'id': id,
  'product_title': _title,
  'product_source_id': ?sourceId,
  'status': status,
  'created_at': '2026-09-12T08:00:00Z',
};

List<RecordedCall> get _posts => api.calls
    .where((c) => c.method == 'POST' && c.path == '/product-requests')
    .toList();

Future<QuoteRequestLike?> _send() async {
  final request = await RestockRequests.instance.request(
    productId: _id,
    title: _title,
    price: 'Rs. 554',
  );
  return request == null ? null : QuoteRequestLike(request.id);
}

/// Only the id matters to these tests; the type is the repository's own.
class QuoteRequestLike {
  const QuoteRequestLike(this.id);
  final String id;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    api = stubCatalog();
    signInForTest();
    RestockRequests.instance.resetForTest();
    _server = [];
    api.onCall('GET', '/product-requests', (_) => reply({'requests': _server}));
    api.onCall('POST', '/product-requests', (call) {
      _server = [..._server, _row(id: 'r-${_server.length + 1}')];
      return reply({'id': 'r-${_server.length}'});
    });
  });

  tearDown(clearApiStub);

  group('the request', () {
    test('goes to the existing product-requests queue, marked for stock', () async {
      final sent = await _send();

      expect(sent?.id, 'r-1');
      final body = _posts.single.json;
      expect(body['product_source_id'], _id);
      expect(body['product_title'], _title);
      expect(body['message'], startsWith('$restockMarker:'));
      expect(
        RestockRequests.instance.existingFor(productId: _id, title: _title),
        isNotNull,
      );
    });

    test('asking again while one is open sends nothing new', () async {
      await _send();
      final again = await _send();

      expect(again?.id, 'r-1');
      expect(_posts, hasLength(1), reason: 'one request per product');
    });

    test('a double tap is one request', () async {
      final first = RestockRequests.instance.request(
        productId: _id,
        title: _title,
      );
      final second = await RestockRequests.instance.request(
        productId: _id,
        title: _title,
      );
      await first;

      expect(second, isNull, reason: 'the second tap did nothing');
      expect(_posts, hasLength(1));
    });

    test('one made earlier, or on the website, shows as already sent', () async {
      _server = [_row(status: 'reviewing')];
      await RestockRequests.instance.refresh();

      final existing = RestockRequests.instance.existingFor(
        productId: _id,
        title: _title,
      );
      expect(existing?.statusLabel, 'Under review');
      await _send();
      expect(_posts, isEmpty);
    });

    test('a declined request can be asked again', () async {
      _server = [_row(status: 'rejected')];
      await _send();
      expect(_posts, hasLength(1));
    });

    test('a failure is never shown as sent, and can be retried', () async {
      api.on('POST', '/product-requests', status: 500, body: const {
        'error': 'down',
      });
      await expectLater(_send(), throwsA(isA<ApiError>()));
      expect(
        RestockRequests.instance.existingFor(productId: _id, title: _title),
        isNull,
      );

      api.onCall('POST', '/product-requests', (call) {
        _server = [_row()];
        return reply({'id': 'r-1'});
      });
      expect((await _send())?.id, 'r-1');
    });

    test('another account on the device does not see these', () async {
      await _send();
      AuthStore.instance.adoptForTest(
        const Account(id: 'user-2', email: 'someone@example.com'),
      );
      expect(
        RestockRequests.instance.existingFor(productId: _id, title: _title),
        isNull,
      );
    });
  });

  group('the bar', () {
    Future<void> pumpBar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: RestockRequestBar(
              product: ProductDetail.fromProduct(
                productStub(numIid: _id, title: _title, displayPrice: 554),
              ),
              reason: 'Every option is sold out.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says it is unavailable, and sends on a tap', (tester) async {
      await pumpBar(tester);

      expect(find.textContaining('Currently unavailable'), findsOneWidget);
      expect(find.textContaining('Every option is sold out.'), findsOneWidget);

      await tester.tap(find.text('Notify sellers I want this'));
      await tester.pumpAndSettle();

      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Notify sellers I want this'), findsNothing);
      expect(_posts, hasLength(1));
    });

    testWidgets('an error says so and offers to try again', (tester) async {
      api.on('POST', '/product-requests', status: 500, body: const {
        'error': 'Server is down',
      });
      await pumpBar(tester);

      await tester.tap(find.text('Notify sellers I want this'));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Request sent'), findsNothing);
    });

    testWidgets('a guest is asked to sign in first', (tester) async {
      AuthStore.instance.resetForTest();
      RestockRequests.instance.resetForTest();
      await pumpBar(tester);

      expect(find.text('Sign in to notify sellers'), findsOneWidget);
      expect(_posts, isEmpty);
    });

    testWidgets('fits a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(640, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: RestockRequestBar(
              product: ProductDetail.fromProduct(
                productStub(numIid: _id, title: _title),
              ),
              reason: 'This product is no longer available.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/quotes/data/quote_repository.dart';
import 'package:gtradea_amazon/features/quotes/presentation/quote_request_detail_screen.dart';
import 'package:gtradea_amazon/features/quotes/presentation/quote_requests_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Map<String, dynamic> _request({
  String id = 'req-1',
  String title = 'Cross-Border Chic Top',
  String status = 'pending',
  num? quotedPrice,
  int? quantity,
  String? lastMessage,
  String created = '2026-08-19T10:00:00Z',
}) => {
  'id': id,
  'product_title': title,
  'product_image_url': 'https://example.invalid/a.jpg',
  'product_price': 'Rs. 1,200',
  'status': status,
  'quoted_price': quotedPrice,
  'quantity': quantity,
  'last_message': lastMessage,
  'created_at': created,
};

void main() {
  late FakeApi api;

  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  group('reading the requests', () {
    test('are read from the existing product-requests route', () async {
      signIn();
      api.on('GET', '/product-requests', body: [_request()]);

      final requests = await QuoteRepository.instance.listMine();

      expect(api.calls.single.path, contains('/product-requests'));
      final one = requests.single;
      expect(one.id, 'req-1');
      expect(one.title, 'Cross-Border Chic Top');
      expect(one.status, QuoteStatus.pending);
      expect(one.askedPrice, 'Rs. 1,200');
      expect(one.imageUrl, isNotNull);
    });

    test('the shop own status wording is used', () async {
      // The server's five values, labelled the way the storefront labels them,
      // so a shopper who asked on the website is told the same thing here.
      expect(QuoteStatus.of('pending').label, 'Received');
      expect(QuoteStatus.of('reviewing').label, 'Under review');
      expect(QuoteStatus.of('quoted').label, 'Quote ready');
      expect(QuoteStatus.of('approved').label, 'Approved');
      expect(QuoteStatus.of('rejected').label, 'Declined');
    });

    test('a status this app has not heard of is shown, not hidden', () async {
      signIn();
      api.on('GET', '/product-requests', body: [_request(status: 'expired')]);

      final one = (await QuoteRepository.instance.listMine()).single;

      expect(one.status, QuoteStatus.other);
      expect(one.statusLabel, 'Expired', reason: 'the server own word');
    });

    test('newest first, whatever order the server sent', () async {
      signIn();
      api.on(
        'GET',
        '/product-requests',
        body: [
          _request(id: 'old', created: '2026-01-01T00:00:00Z'),
          _request(id: 'new', created: '2026-08-19T00:00:00Z'),
        ],
      );

      final requests = await QuoteRepository.instance.listMine();
      expect(requests.map((r) => r.id), ['new', 'old']);
    });

    test('a row with no id is dropped rather than made unopenable', () async {
      signIn();
      api.on(
        'GET',
        '/product-requests',
        body: [
          {'product_title': 'No id'},
        ],
      );

      expect(await QuoteRepository.instance.listMine(), isEmpty);
    });
  });

  group('My Quote Requests', () {
    testWidgets('lists what this account asked for', (tester) async {
      signIn();
      api.on(
        'GET',
        '/product-requests',
        body: [
          _request(title: 'Cross-Border Chic Top'),
          _request(id: 'req-2', title: 'Gps Car Antenna', status: 'reviewing'),
        ],
      );
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('My Quote Requests'), findsOneWidget);
      expect(find.text('Cross-Border Chic Top'), findsOneWidget);
      expect(find.text('Gps Car Antenna'), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
    });

    testWidgets('an answered request shows the price it was quoted', (
      tester,
    ) async {
      signIn();
      api.on(
        'GET',
        '/product-requests',
        body: [_request(status: 'quoted', quotedPrice: 1450, quantity: 20)],
      );
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Quote ready'), findsOneWidget);
      expect(find.text('Rs. 1,450'), findsOneWidget);
      expect(find.text('Qty 20'), findsOneWidget);
    });

    testWidgets('opens the request that was tapped, by its own id', (
      tester,
    ) async {
      signIn();
      api.on(
        'GET',
        '/product-requests',
        body: [
          _request(id: 'req-1', title: 'First thing'),
          _request(id: 'req-2', title: 'Second thing'),
        ],
      );
      api.on(
        'GET',
        '/product-requests/req-2',
        body: _request(id: 'req-2', title: 'Second thing', quantity: 5),
      );
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Second thing'));
      await tester.pumpAndSettle();

      expect(find.byType(QuoteRequestDetailScreen), findsOneWidget);
      expect(find.text('req-2'), findsOneWidget, reason: 'its own reference');
      expect(
        api.calls.where((c) => c.path.contains('/product-requests/req-2')),
        isNotEmpty,
      );
    });

    testWidgets('says so when nothing has been asked for', (tester) async {
      signIn();
      api.on('GET', '/product-requests', body: const []);
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.text("You haven't requested any quotes yet."),
        findsOneWidget,
      );
    });

    testWidgets('a guest is asked to sign in, not shown an empty list', (
      tester,
    ) async {
      // The list is the account's. "No quotes" would be a lie to somebody who
      // has them under an account they are not signed in to.
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.text('Log in to see your quote requests and replies.'),
        findsOneWidget,
      );
      expect(
        api.calls.where((c) => c.path.contains('/product-requests')),
        isEmpty,
        reason: 'nothing to ask for without an account',
      );
    });

    testWidgets('a failure offers a retry rather than an empty list', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/product-requests', status: 500, body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text("You haven't requested any quotes yet."),
        findsNothing,
        reason: 'a failure is not an empty list',
      );
    });
  });
}

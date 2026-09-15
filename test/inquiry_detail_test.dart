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
  String title = '3 Phase Induction Motor 5.5kW 380V',
  String status = 'reviewing',
  num? quotedPrice,
  int? quantity = 10,
  String created = '2026-09-02T04:39:00Z',
}) => {
  'id': id,
  'product_title': title,
  'product_image_url': 'https://example.invalid/a.jpg',
  'product_price': 'Rs. 24,500',
  'status': status,
  'quoted_price': quotedPrice,
  'quantity': quantity,
  'created_at': created,
};

Map<String, dynamic> _message({
  String id = 'm-1',
  String text = 'Need quotation for 10 units with delivery to Lalitpur.',
  String sender = 'user',
  List<String> attachments = const [],
  String created = '2026-09-02T04:40:00Z',
}) => {
  'id': id,
  'message': text,
  'sender_type': sender,
  'attachments': attachments,
  'created_at': created,
};

void main() {
  late FakeApi api;

  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  /// The screen as the list opens it: the row it was tapped from, then the
  /// full record fetched by that id.
  QuoteRequest rowFor(Map<String, dynamic> json) => QuoteRequest.fromJson(json);

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

  testWidgets('opens on the inquiry that was tapped, by its own id', (
    tester,
  ) async {
    signIn();
    api.on('GET', '/product-requests/req-1', body: _request());
    api.on('GET', '/product-requests/req-1/messages', body: [_message()]);

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(_request()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inquiry Details'), findsOneWidget);
    expect(find.text('3 Phase Induction Motor 5.5kW 380V'), findsWidgets);
    expect(find.text('#req-1'), findsOneWidget);
    expect(find.text('Under review'), findsOneWidget);
    expect(find.textContaining('Inquired on 2 Sep 2026'), findsWidgets);

    // Read by its own id, and nobody else's.
    expect(
      api.calls.where((c) => c.path.contains('/product-requests/req-1')),
      isNotEmpty,
    );
  });

  testWidgets('a record for a different id is not shown over this one', (
    tester,
  ) async {
    // Whatever the server answers with, the page stays about what was tapped.
    signIn();
    api.on(
      'GET',
      '/product-requests/req-1',
      body: _request(id: 'req-9', title: 'Somebody else inquiry'),
    );
    api.on('GET', '/product-requests/req-1/messages', body: const []);

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(_request()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Somebody else inquiry'), findsNothing);
    expect(find.text('3 Phase Induction Motor 5.5kW 380V'), findsWidgets);
  });

  testWidgets('the timeline stands where the status says, and no further', (
    tester,
  ) async {
    signIn();
    api.on('GET', '/product-requests/req-1', body: _request());
    api.on('GET', '/product-requests/req-1/messages', body: const []);

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(_request()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inquiry Status'), findsOneWidget);
    expect(find.text('Inquiry Submitted'), findsOneWidget);
    expect(find.text('Sourcing & Supplier Matching'), findsOneWidget);
    expect(find.text('Quotation'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);

    // Nothing has been quoted, so nothing claims a price is on its way.
    expect(
      find.text('You will be notified once we receive a quote.'),
      findsOneWidget,
    );
  });

  testWidgets('and says what was quoted once there is a quote', (tester) async {
    signIn();
    final quoted = _request(status: 'quoted', quotedPrice: 24500);
    api.on('GET', '/product-requests/req-1', body: quoted);
    api.on('GET', '/product-requests/req-1/messages', body: const []);

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(quoted))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quoted Rs. 24,500.'), findsOneWidget);
    expect(find.text('Quotes (1)'), findsOneWidget);
  });

  testWidgets('the details card shows only what the shop actually keeps', (
    tester,
  ) async {
    signIn();
    api.on('GET', '/product-requests/req-1', body: _request());
    api.on('GET', '/product-requests/req-1/messages', body: [_message()]);

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(_request()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your Inquiry Details'), findsOneWidget);
    expect(find.text('10 units'), findsOneWidget);
    expect(find.text('Rs. 24,500'), findsOneWidget);
    // What the shopper said, from the thread rather than from anywhere else.
    expect(
      find.text('Need quotation for 10 units with delivery to Lalitpur.'),
      findsOneWidget,
    );
    // No field is invented for what the record does not hold.
    expect(find.text('Category'), findsNothing);
    expect(find.text('Target Price'), findsNothing);
    expect(find.text('Delivery Location'), findsNothing);
  });

  testWidgets('the thread is the shop own, and a reply is posted to it', (
    tester,
  ) async {
    signIn();
    api.on('GET', '/product-requests/req-1', body: _request());
    api.on(
      'GET',
      '/product-requests/req-1/messages',
      body: [
        _message(),
        _message(
          id: 'm-2',
          sender: 'admin',
          text: 'Checking with two suppliers.',
          created: '2026-09-02T06:00:00Z',
        ),
      ],
    );
    api.on('POST', '/product-requests/req-1/messages', body: const {});

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(_request()))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();

    expect(find.text('Checking with two suppliers.'), findsOneWidget);
    expect(find.text('GtradeA'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Any update?');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    final sent = api.calls.lastWhere(
      (c) => c.method == 'POST' && c.path.endsWith('/messages'),
    );
    expect((sent.body as Map)['message'], 'Any update?');
  });

  testWidgets('the tabs count the files the thread actually carries', (
    tester,
  ) async {
    signIn();
    api.on('GET', '/product-requests/req-1', body: _request());
    api.on(
      'GET',
      '/product-requests/req-1/messages',
      body: [
        _message(attachments: const ['req-1/spec.pdf', 'req-1/photo.jpg']),
      ],
    );

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(_request()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attachments (2)'), findsWidgets);
    expect(find.text('spec.pdf'), findsWidgets);
  });

  testWidgets('a thread that cannot be read costs the tab, not the page', (
    tester,
  ) async {
    signIn();
    api.on('GET', '/product-requests/req-1', body: _request());
    api.on(
      'GET',
      '/product-requests/req-1/messages',
      status: 500,
      body: const {},
    );

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(_request()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your Inquiry Details'), findsOneWidget);
    expect(find.text('Attachments (0)'), findsOneWidget);
  });

  testWidgets('the list opens this page for the row that was tapped', (
    tester,
  ) async {
    signIn();
    api.on(
      'GET',
      '/product-requests',
      body: [
        _request(id: 'req-1', title: 'First inquiry'),
        _request(id: 'req-2', title: 'Second inquiry'),
      ],
    );
    api.on(
      'GET',
      '/product-requests/req-2',
      body: _request(id: 'req-2', title: 'Second inquiry'),
    );
    api.on('GET', '/product-requests/req-2/messages', body: const []);

    _tall(tester);
    await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Second inquiry'));
    await tester.pumpAndSettle();

    expect(find.byType(QuoteRequestDetailScreen), findsOneWidget);
    expect(find.text('#req-2'), findsOneWidget);
    expect(find.text('First inquiry'), findsNothing);
  });

  testWidgets('every block on the page is 97% of it, centred', (tester) async {
    signIn();
    api.on('GET', '/product-requests/req-1', body: _request());
    api.on('GET', '/product-requests/req-1/messages', body: const []);

    _tall(tester);
    await tester.pumpWidget(
      _wrap(QuoteRequestDetailScreen(request: rowFor(_request()))),
    );
    await tester.pumpAndSettle();

    final page = tester.getSize(find.byType(QuoteRequestDetailScreen)).width;

    for (final label in ['#req-1', 'Inquiry Status', 'Your Inquiry Details']) {
      // The box is the page; the card inside it is the 97%.
      final card = tester.getRect(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(FractionallySizedBox),
                  )
                  .last,
              matching: find.byType(Container),
            )
            .first,
      );
      expect(card.width, closeTo(page * 0.97, 0.5), reason: label);
      expect(card.left, closeTo(page - card.right, 0.5), reason: label);
    }
  });
}

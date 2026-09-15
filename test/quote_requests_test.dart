import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/catalog/presentation/browse_screen.dart';
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

/// The sourcing banner, which is one supplied image.
final _banner = find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName == 'assets/images/inquiry_banner.jpg',
);

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

      expect(find.text('Product Inquiry'), findsOneWidget);
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
      expect(find.text('Quoted Rs. 1,450'), findsOneWidget);
      expect(find.textContaining('Qty 20'), findsOneWidget);
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
      expect(find.text('#req-2'), findsOneWidget, reason: 'its own reference');
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
        find.text("You haven't raised any product inquiries yet."),
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
        find.text('Log in to see your product inquiries and replies.'),
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

  group('the inquiry list as the reference draws it', () {
    /// One of each status, so every tab has something to hold.
    void seedOneOfEach() {
      api.on(
        'GET',
        '/product-requests',
        body: [
          _request(
            id: 'req-1',
            title: '3 Phase Induction Motor 5.5kW 380V',
            status: 'reviewing',
            lastMessage: 'Need quotation for 10 units with delivery to Nepal',
            created: '2026-09-02T10:00:00Z',
          ),
          _request(
            id: 'req-2',
            title: 'Solar LED Street Light 100W with Pole',
            status: 'quoted',
            quotedPrice: 18500,
            created: '2026-09-01T10:00:00Z',
          ),
          _request(
            id: 'req-3',
            title: "Men's Running Shoes",
            status: 'rejected',
            created: '2026-08-27T10:00:00Z',
          ),
        ],
      );
    }

    testWidgets('a card carries the date, the reference and the way in', (
      tester,
    ) async {
      signIn();
      seedOneOfEach();
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      // The day it was raised, not how long ago -- it reads the same tomorrow.
      expect(find.text('Inquired on 2 Sep 2026'), findsOneWidget);
      // The server's own reference, which is what support can be quoted.
      expect(find.text('#req-1'), findsOneWidget);
      expect(find.text('View Details'), findsNWidgets(3));
      expect(
        find.text('Need quotation for 10 units with delivery to Nepal'),
        findsOneWidget,
      );
    });

    testWidgets('the tabs count what the account actually has', (tester) async {
      signIn();
      seedOneOfEach();
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Under Review (1)'), findsOneWidget);
      expect(find.text('Quoted (1)'), findsOneWidget);
      expect(find.text('Closed (1)'), findsOneWidget);
    });

    testWidgets('and picking one narrows the list without a second request', (
      tester,
    ) async {
      signIn();
      seedOneOfEach();
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quoted (1)'));
      await tester.pumpAndSettle();

      expect(
        find.text('Solar LED Street Light 100W with Pole'),
        findsOneWidget,
      );
      expect(find.text('3 Phase Induction Motor 5.5kW 380V'), findsNothing);
      expect(
        api.calls.where((c) => c.path.contains('/product-requests')),
        hasLength(1),
        reason: 'the list is filtered in hand, not re-fetched',
      );
    });

    testWidgets('an empty tab says so and can be left again', (tester) async {
      signIn();
      api.on(
        'GET',
        '/product-requests',
        body: [
          _request(id: 'req-1', title: 'Only a quoted one', status: 'quoted'),
        ],
      );
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Under Review (0)'));
      await tester.pumpAndSettle();

      expect(find.text('No inquiries here.'), findsOneWidget);
      expect(find.text('Only a quoted one'), findsNothing);

      await tester.tap(find.text('All (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Only a quoted one'), findsOneWidget);
    });

    testWidgets('search narrows the same list, and the counts with it', (
      tester,
    ) async {
      signIn();
      seedOneOfEach();
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'solar');
      await tester.pumpAndSettle();

      expect(
        find.text('Solar LED Street Light 100W with Pole'),
        findsOneWidget,
      );
      expect(find.text('3 Phase Induction Motor 5.5kW 380V'), findsNothing);
      expect(find.text('All (1)'), findsOneWidget);
      expect(
        api.calls.where((c) => c.path.contains('/product-requests')),
        hasLength(1),
        reason: 'the endpoint takes no query',
      );
    });

    testWidgets('New Inquiry leads to the catalogue, not a form the server '
        'would refuse', (tester) async {
      signIn();
      seedOneOfEach();
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      expect(_banner, findsOneWidget);

      // The whole banner is the button: "New Inquiry" is painted into it.
      await tester.tap(_banner);
      await tester.pumpAndSettle();

      // An inquiry is raised against a listing, so this is where one starts.
      expect(find.byType(BrowseScreen), findsOneWidget);
    });

    testWidgets('a card takes 97% of the page, centred, with no rule in it', (
      tester,
    ) async {
      signIn();
      seedOneOfEach();
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      final page = tester.getSize(find.byType(QuoteRequestsScreen)).width;
      // The card itself, not the full-width box that centres it.
      final card = tester.getRect(
        find
            .ancestor(of: find.text('#req-1'), matching: find.byType(Material))
            .first,
      );

      expect(card.width, closeTo(page * 0.97, 0.5));
      // The same air either side of it.
      expect(card.left, closeTo(page - card.right, 0.5));

      // Nothing rules off the row that carries View Details.
      expect(
        find.descendant(
          of: find.byType(FractionallySizedBox),
          matching: find.byType(Divider),
        ),
        findsNothing,
      );
      expect(find.text('View Details'), findsNWidgets(3));
    });

    testWidgets('the banner leads the page and spans it', (tester) async {
      signIn();
      seedOneOfEach();
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      final banner = _banner;
      final tabs = find.text('All (3)');
      final firstCard = find.text('3 Phase Induction Motor 5.5kW 380V');

      // Above the tabs, and above the list under them.
      expect(tester.getRect(banner).top, lessThan(tester.getRect(tabs).top));
      expect(
        tester.getRect(banner).top,
        lessThan(tester.getRect(firstCard).top),
      );

      // The full width of the page it is on, at the artwork's own shape.
      final page = tester.getSize(find.byType(QuoteRequestsScreen)).width;
      expect(tester.getSize(banner).width, page);
    });

    testWidgets('the banner is there before the first inquiry too', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/product-requests', body: const []);
      _tall(tester);
      await tester.pumpWidget(_wrap(const QuoteRequestsScreen()));
      await tester.pumpAndSettle();

      expect(_banner, findsOneWidget);
      // No tabs to pick between when there is nothing to filter.
      expect(find.text('All (0)'), findsNothing);
    });
  });
}

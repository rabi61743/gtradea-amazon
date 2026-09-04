import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/corporate_gifts/data/corporate_gifts_repository.dart';
import 'package:gtradea_amazon/features/corporate_gifts/presentation/corporate_gifts_screen.dart';
import 'package:gtradea_amazon/features/corporate_gifts/presentation/corporate_gifts_skeleton.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// One row in the shape `/free-delivery?collection=…` answers with.
Map<String, dynamic> _row(String numIid, String title, {num price = 1200}) => {
  'source': '1688',
  'num_iid': numIid,
  'product_id': null,
  'slug': null,
  'title': title,
  'image_url': 'https://cdn.invalid/$numIid.jpg',
  'price': price,
  'currency_symbol': 'Rs.',
  'free_delivery': false,
  'badge_text': 'HOT',
};

Map<String, dynamic> _page(List<Map<String, dynamic>> rows, {int? total}) => {
  'items': rows,
  'total': total ?? rows.length,
};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WishlistStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  group('asking the server for the collection', () {
    test('it asks for corporate gifts, not the whole catalogue', () async {
      api.on('GET', '/free-delivery', body: _page([_row('1', 'Pen set')]));

      await CorporateGiftsRepository.instance.page();

      final call = api.calls.single;
      expect(call.path, '/free-delivery');
      expect(call.query['collection'], 'corporate-gifts');
      expect(call.query['limit'], CorporateGiftsRepository.pageSize);
    });

    test('a search goes out as q, trimmed', () async {
      api.on('GET', '/free-delivery', body: _page([_row('1', 'Pen set')]));

      await CorporateGiftsRepository.instance.page(query: '  Pen Set  ');

      expect(api.calls.single.query['q'], 'Pen Set');
    });

    test('and an empty one is not sent at all', () async {
      api.on('GET', '/free-delivery', body: _page([_row('1', 'Pen set')]));

      await CorporateGiftsRepository.instance.page(query: '   ');

      expect(api.calls.single.query.containsKey('q'), isFalse);
    });

    test('a later page carries its offset', () async {
      api.on('GET', '/free-delivery', body: _page([]));

      await CorporateGiftsRepository.instance.page(offset: 48);

      expect(api.calls.single.query['offset'], 48);
    });

    test('the first page does not, so nothing is skipped', () async {
      api.on('GET', '/free-delivery', body: _page([]));

      await CorporateGiftsRepository.instance.page();

      expect(api.calls.single.query.containsKey('offset'), isFalse);
    });
  });

  group('what comes back', () {
    test('rows become products the cards can draw', () async {
      api.on(
        'GET',
        '/free-delivery',
        body: _page([_row('1059589640366', 'Executive gift set', price: 2260)]),
      );

      final page = await CorporateGiftsRepository.instance.page();

      final product = page.products.single;
      expect(product.numIid, '1059589640366');
      expect(product.title, 'Executive gift set');
      expect(product.imageUrl, 'https://cdn.invalid/1059589640366.jpg');
      // The shopper's own currency, straight off the row.
      expect(product.displayPrice, 2260);
    });

    test('the total is the whole match, not the page', () async {
      api.on(
        'GET',
        '/free-delivery',
        body: _page([_row('1', 'One'), _row('2', 'Two')], total: 131),
      );

      final page = await CorporateGiftsRepository.instance.page();

      expect(page.products, hasLength(2));
      expect(page.total, 131);
    });

    test('a row with no id or no title is dropped, not drawn empty', () async {
      api.on(
        'GET',
        '/free-delivery',
        body: _page([
          _row('1', 'Real one'),
          {'num_iid': '', 'title': 'No id'},
          {'num_iid': '2', 'title': ''},
        ], total: 3),
      );

      final page = await CorporateGiftsRepository.instance.page();

      expect(page.products.map((p) => p.numIid), ['1']);
    });

    test('a failure arrives as an ApiError, not a DioException', () async {
      api.on('GET', '/free-delivery', status: 500, body: {'message': 'boom'});

      expect(
        () => CorporateGiftsRepository.instance.page(),
        throwsA(isA<ApiError>()),
      );
    });

    test('a cancelled request throws rather than resolving stale', () async {
      api.on('GET', '/free-delivery', body: _page([_row('1', 'One')]));

      final token = CancelToken()..cancel('superseded');

      expect(
        () => CorporateGiftsRepository.instance.page(cancelToken: token),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('the page', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const CorporateGiftsScreen()),
      );
    }

    testWidgets('is shaped like itself while it loads', (tester) async {
      api.on('GET', '/free-delivery', body: _page([_row('1', 'Pen set')]));

      await pump(tester);
      await tester.pump();

      expect(find.byType(CorporateGiftsSkeleton), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CorporateGiftsSkeleton), findsNothing);
    });

    testWidgets('lists the collection on the usual cards', (tester) async {
      api.on(
        'GET',
        '/free-delivery',
        body: _page([_row('1', 'Executive pen set'), _row('2', 'Gift mug')]),
      );

      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ProductResultCard), findsNWidgets(2));
      expect(find.text('Executive pen set'), findsOneWidget);
    });

    testWidgets('typing searches the collection on the server', (tester) async {
      api.onCall('GET', '/free-delivery', (call) {
        final q = call.query['q'];
        return reply(
          _page(
            q == null
                ? [_row('1', 'Executive pen set'), _row('2', 'Gift mug')]
                : [_row('1', 'Executive pen set')],
          ),
        );
      });

      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ProductResultCard), findsNWidgets(2));

      await tester.enterText(find.byType(TextField), 'pen');
      // The debounce -- nothing has gone out yet.
      expect(api.calls, hasLength(1));

      await tester.pumpAndSettle();

      expect(api.calls.last.query['q'], 'pen');
      expect(api.calls.last.query['collection'], 'corporate-gifts');
      expect(find.byType(ProductResultCard), findsOneWidget);
    });

    testWidgets('a word typed at speed is one request, not six', (
      tester,
    ) async {
      api.on('GET', '/free-delivery', body: _page([_row('1', 'Pen set')]));

      await pump(tester);
      await tester.pumpAndSettle();
      final before = api.calls.length;

      for (final typed in ['p', 'pe', 'pen', 'pen ', 'pen s', 'pen se']) {
        await tester.enterText(find.byType(TextField), typed);
        await tester.pump(const Duration(milliseconds: 40));
      }
      // Past the debounce, so the one request it settled on goes out.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(api.calls.length - before, 1);
      expect(api.calls.last.query['q'], 'pen se');
    });

    testWidgets('nothing matching says so, and says what was searched', (
      tester,
    ) async {
      api.onCall('GET', '/free-delivery', (call) {
        final q = call.query['q'];
        return reply(_page(q == null ? [_row('1', 'Pen set')] : []));
      });

      await pump(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'helicopter');
      await tester.pumpAndSettle();

      expect(find.textContaining('helicopter'), findsWidgets);
      expect(find.byType(ProductResultCard), findsNothing);
      // The box stays, so the search can be corrected rather than restarted.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('an empty collection is not reported as a failed search', (
      tester,
    ) async {
      api.on('GET', '/free-delivery', body: _page([]));

      await pump(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('There are no corporate gifts just now.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed search says so rather than showing the last one', (
      tester,
    ) async {
      api.onCall('GET', '/free-delivery', (call) {
        if (call.query.containsKey('q')) {
          return reply({'message': 'boom'}, status: 500);
        }
        return reply(_page([_row('1', 'Executive pen set')]));
      });

      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ProductResultCard), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pen');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // The old products answered the old query. Showing them under a search
      // that failed would read as its results.
      expect(find.byType(ProductResultCard), findsNothing);
      expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);
    });

    testWidgets('a failure offers a retry, and the retry works', (
      tester,
    ) async {
      var attempt = 0;
      api.onCall('GET', '/free-delivery', (_) {
        attempt++;
        if (attempt == 1) {
          return reply({'message': 'boom'}, status: 500);
        }
        return reply(_page([_row('1', 'Pen set')]));
      });

      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ProductResultCard), findsNothing);
      final retry = find.widgetWithText(TextButton, 'Try again');
      expect(retry, findsOneWidget);

      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.byType(ProductResultCard), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/data/hidden_history_store.dart';
import 'package:gtradea_amazon/features/account/presentation/product_history_screen.dart';
import 'package:gtradea_amazon/features/account/presentation/recent_views_section.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

Widget _wrap() =>
    MaterialApp(theme: AppTheme.light, home: const ProductHistoryScreen());

/// Scrolls to the foot of the history, where the older-history control is.
Future<void> _toFooter(WidgetTester tester, Finder target) async {
  // Dragged on the viewed tab's own list: the page view beside it is a
  // scrollable too, and scrollUntilVisible cannot tell which was meant.
  for (var i = 0; i < 40 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Back to the newest rows.
Future<void> _toTop(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// [count] rows, one an hour older than the last, in the shape this app
/// writes them.
List<Map<String, dynamic>> _views(int count, {DateTime? from}) {
  final start = from ?? DateTime(2026, 9, 4, 12);
  return [
    for (var i = 0; i < count; i++)
      {
        'source': '1688',
        'source_product_id': 'p$i',
        'viewed_at': start
            .subtract(Duration(hours: i))
            .toUtc()
            .toIso8601String(),
        'product_data': {
          'name': 'Product $i',
          'image_url': 'https://example.invalid/$i.jpg',
          'price_label': 'Rs. 1,000',
          'category': 'Test',
        },
      },
  ];
}

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    OrderStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    HiddenHistoryStore.instance.resetForTest();

    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/orders', body: const []);
    signInForTest();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    OrderStore.instance.resetForTest();
    HiddenHistoryStore.instance.resetForTest();
    clearApiStub();
  });

  /// Answers with as many rows as were asked for, capped at [total].
  void wireHistory({required int total}) {
    api.onCall('GET', '/product-views', (call) {
      final limit = int.tryParse('${call.query['limit']}') ?? 40;
      return reply(_views(total).take(limit).toList());
    });
  }

  group('older history', () {
    testWidgets('the first load asks for one page, not the lot', (
      tester,
    ) async {
      wireHistory(total: 100);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(api.calls.first.query['limit'], 40);
      await _toFooter(tester, find.text('Load More'));
      expect(find.text('Load More'), findsOneWidget);
    });

    testWidgets('pressing it asks the server for more', (tester) async {
      wireHistory(total: 100);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      final asked = api.calls
          .where((c) => c.path == '/product-views')
          .map((c) => c.query['limit'])
          .toList();
      expect(asked, [40, 80]);
    });

    testWidgets('and shows the older rows without repeating the newer ones', (
      tester,
    ) async {
      wireHistory(total: 45);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Row 42 is past the first page.
      expect(find.text('Product 42'), findsNothing);

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Product 42'));
      expect(find.text('Product 42'), findsOneWidget);

      // Every row still appears exactly once.
      await _toTop(tester);
      expect(find.text('Product 0'), findsWidgets);
      await _toFooter(tester, find.text('Product 39'));
      expect(find.text('Product 39'), findsOneWidget);
    });

    testWidgets('bones stand in for the older rows while they are fetched', (
      tester,
    ) async {
      var call = 0;
      api.onCall('GET', '/product-views', (_) {
        call++;
        return reply(
          _views(call == 1 ? 40 : 60),
          // The second page is held open, so the wait can be looked at.
          delay: call == 1 ? null : const Duration(seconds: 2),
        );
      });
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pump();

      // Rows in outline, not a spinner, and the button stands down while the
      // page it would ask for is already on its way.
      expect(find.byType(RecentViewsSkeleton), findsOneWidget);
      expect(find.text('Load More'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(RecentViewsSkeleton), findsNothing);
    });

    testWidgets('when there is nothing older it says so, once', (tester) async {
      wireHistory(total: 45);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('That is the whole history.'));
      expect(find.text('That is the whole history.'), findsOneWidget);
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('a short first page means there is nothing older at all', (
      tester,
    ) async {
      wireHistory(total: 3);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('That is the whole history.'));
      expect(find.text('Load More'), findsNothing);
      expect(find.text('That is the whole history.'), findsOneWidget);
    });

    testWidgets('a failure offers a retry and keeps what is on screen', (
      tester,
    ) async {
      var attempt = 0;
      api.onCall('GET', '/product-views', (call) {
        attempt++;
        if (attempt == 2) return reply({'message': 'boom'}, status: 500);
        final limit = int.tryParse('${call.query['limit']}') ?? 40;
        return reply(_views(100).take(limit).toList());
      });
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Try again'));
      expect(find.text('Try again'), findsOneWidget);
      // The page it already had is untouched.
      await _toTop(tester);
      expect(find.text('Product 0'), findsWidgets);

      await _toFooter(tester, find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Product 42'));
      expect(find.text('Product 42'), findsOneWidget);
    });
  });

  // The rows that were picked and swiped away are gone with the cards they
  // lived on -- the viewed tab is drawn by RecentViewsSection now. What is
  // hidden stays hidden, which the group below still holds the shop to.

  group('one shopper\'s hidden rows are their own', () {
    test('the list is kept per account', () async {
      SharedPreferences.setMockInitialValues({});
      AuthStore.instance.resetForTest();
      HiddenHistoryStore.instance.resetForTest();

      signInForTest(email: 'first@example.com', id: 'user-1');
      await HiddenHistoryStore.instance.load();
      await HiddenHistoryStore.instance.hide(const ['p1|x']);
      expect(HiddenHistoryStore.instance.isHidden('p1|x'), isTrue);

      // A different account on the same device sees its own list.
      AuthStore.instance.resetForTest();
      signInForTest(email: 'second@example.com', id: 'user-2');
      await HiddenHistoryStore.instance.load();

      expect(HiddenHistoryStore.instance.isHidden('p1|x'), isFalse);
    });
  });
}

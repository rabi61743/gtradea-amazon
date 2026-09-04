import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/data/hidden_history_store.dart';
import 'package:gtradea_amazon/features/account/presentation/product_history_screen.dart';
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
      await _toFooter(tester, find.text('See older history'));
      expect(find.text('See older history'), findsOneWidget);
    });

    testWidgets('pressing it asks the server for more', (tester) async {
      wireHistory(total: 100);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('See older history'));
      await tester.tap(find.text('See older history'));
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

      await _toFooter(tester, find.text('See older history'));
      await tester.tap(find.text('See older history'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Product 42'));
      expect(find.text('Product 42'), findsOneWidget);

      // Every row still appears exactly once.
      await _toTop(tester);
      expect(find.text('Product 0'), findsOneWidget);
      await _toFooter(tester, find.text('Product 39'));
      expect(find.text('Product 39'), findsOneWidget);
    });

    testWidgets('when there is nothing older it says so, once', (tester) async {
      wireHistory(total: 45);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('See older history'));
      await tester.tap(find.text('See older history'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('That is the whole history.'));
      expect(find.text('That is the whole history.'), findsOneWidget);
      expect(find.text('See older history'), findsNothing);
    });

    testWidgets('a short first page means there is nothing older at all', (
      tester,
    ) async {
      wireHistory(total: 3);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('That is the whole history.'));
      expect(find.text('See older history'), findsNothing);
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

      await _toFooter(tester, find.text('See older history'));
      await tester.tap(find.text('See older history'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Try again'));
      expect(find.text('Try again'), findsOneWidget);
      // The page it already had is untouched.
      await _toTop(tester);
      expect(find.text('Product 0'), findsOneWidget);

      await _toFooter(tester, find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Product 42'));
      expect(find.text('Product 42'), findsOneWidget);
    });
  });

  group('picking rows to remove', () {
    Future<void> open(WidgetTester tester) async {
      wireHistory(total: 5);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
    }

    testWidgets('a long press starts it and counts what is picked', (
      tester,
    ) async {
      await open(tester);

      await tester.longPress(find.text('Product 0'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('Product 1'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('a normal tap still opens the product', (tester) async {
      await open(tester);

      await tester.tap(find.text('Product 0'));
      await tester.pumpAndSettle();

      // Not in selection mode, so the tap went where it always did.
      expect(find.text('1 selected'), findsNothing);
    });

    testWidgets('removing asks first, and Keep changes nothing', (
      tester,
    ) async {
      await open(tester);

      await tester.longPress(find.text('Product 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from history'));
      await tester.pumpAndSettle();

      expect(find.text('Remove 1 item?'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(find.text('Product 0'), findsOneWidget);
    });

    testWidgets('confirming hides them, and never asks the server to', (
      tester,
    ) async {
      await open(tester);

      await tester.longPress(find.text('Product 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Product 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from history'));
      await tester.pumpAndSettle();

      expect(find.text('Remove 2 items?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Product 0'), findsNothing);
      expect(find.text('Product 1'), findsNothing);
      expect(find.text('Product 2'), findsOneWidget);

      // The whole point: the records stay on the server.
      expect(
        api.calls.where((c) => c.method == 'DELETE'),
        isEmpty,
        reason: 'user-side only',
      );
    });

    testWidgets('and they stay hidden when the page is loaded again', (
      tester,
    ) async {
      await open(tester);

      await tester.longPress(find.text('Product 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // A fresh screen, reading the same server rows.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Product 0'), findsNothing);
      expect(find.text('Product 1'), findsOneWidget);
    });

    testWidgets('undo puts them back', (tester) async {
      await open(tester);

      await tester.longPress(find.text('Product 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Product 0'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Product 0'), findsOneWidget);
    });

    testWidgets('cancelling leaves everything as it was', (tester) async {
      await open(tester);

      await tester.longPress(find.text('Product 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Product 0'), findsOneWidget);
    });
  });

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

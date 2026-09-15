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
      final limit = int.tryParse('${call.query['limit']}') ?? 10;
      return reply(_views(total).take(limit).toList());
    });
  }

  /// The calls that went to the history route, in order.
  List<RecordedCall> historyCalls() =>
      api.calls.where((c) => c.path == '/product-views').toList();

  group('older history', () {
    testWidgets('the first load asks for one small batch, not the lot', (
      tester,
    ) async {
      wireHistory(total: 100);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(historyCalls().single.query['limit'], 10);
      expect(find.text('Product 9'), findsOneWidget);
      expect(find.text('Product 10'), findsNothing);
      await _toFooter(tester, find.text('Load More'));
      expect(find.text('Load More'), findsOneWidget);
    });

    testWidgets('pressing it asks the server for the next batch', (
      tester,
    ) async {
      wireHistory(total: 100);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      expect(historyCalls().map((c) => c.query['limit']), [10, 20]);
    });

    testWidgets('appends the older rows without repeating the newer ones', (
      tester,
    ) async {
      wireHistory(total: 15);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Product 12'), findsNothing);

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Product 12'));
      expect(find.text('Product 12'), findsOneWidget);

      // Every row exactly once.
      await _toTop(tester);
      for (final name in ['Product 0', 'Product 9', 'Product 14']) {
        await _toFooter(tester, find.text(name));
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });

    testWidgets(
      'the cards stay while the next batch loads, and one tap is one request',
      (tester) async {
        var call = 0;
        api.onCall('GET', '/product-views', (c) {
          call++;
          final limit = int.tryParse('${c.query['limit']}') ?? 10;
          return reply(
            _views(40).take(limit).toList(),
            // The second batch is held open, so the wait can be looked at.
            delay: call == 1 ? null : const Duration(seconds: 2),
          );
        });
        _tall(tester);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        await _toFooter(tester, find.text('Load More'));
        await tester.tap(find.text('Load More'));
        await tester.pump();

        // A spinner on the button, which takes no second tap, and the cards
        // already loaded untouched -- no bones standing in for them.
        final button = tester.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('history-load-more')),
        );
        expect(button.onPressed, isNull);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(find.byType(RecentViewsSkeleton), findsNothing);
        expect(find.text('Product 9'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('history-load-more')),
          warnIfMissed: false,
        );
        await tester.pump();

        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(historyCalls(), hasLength(2));
        await _toFooter(tester, find.text('Product 19'));
        expect(find.text('Product 19'), findsOneWidget);
      },
    );

    testWidgets('Load More reads clearly against the page, idle and loading', (
      tester,
    ) async {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      var call = 0;
      api.onCall('GET', '/product-views', (c) {
        call++;
        final limit = int.tryParse('${c.query['limit']}') ?? 10;
        return reply(
          _views(40).take(limit).toList(),
          delay: call == 1 ? null : const Duration(seconds: 2),
        );
      });
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _toFooter(tester, find.text('Load More'));

      final page = AppTheme.light.scaffoldBackgroundColor;
      for (final loading in [false, true]) {
        if (loading) {
          await tester.tap(find.text('Load More'));
          await tester.pump();
        }
        final button = tester.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('history-load-more')),
        );
        final states = loading ? {WidgetState.disabled} : <WidgetState>{};
        final fill = button.style!.backgroundColor!.resolve(states)!;
        final ink = Color.alphaBlend(
          button.style!.foregroundColor!.resolve(states)!,
          fill,
        );
        final edge = button.style!.side!.resolve(states)!.color;

        expect(fill.a, 1.0, reason: 'an opaque button, not see-through');
        expect(
          contrast(ink, fill),
          greaterThanOrEqualTo(4.5),
          reason: 'label, loading=$loading',
        );
        expect(
          contrast(edge, page),
          greaterThanOrEqualTo(3),
          reason: 'edge against the page, loading=$loading',
        );
        expect(find.text('Load More'), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('when nothing older comes back, Load More goes away', (
      tester,
    ) async {
      wireHistory(total: 15);
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      // Asked for 20, got 15: the server has nothing beyond them.
      await _toFooter(tester, find.text('That is the whole history.'));
      expect(find.text('That is the whole history.'), findsOneWidget);
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets("the server's own has_more is believed over the count", (
      tester,
    ) async {
      api.onCall('GET', '/product-views', (c) {
        final limit = int.tryParse('${c.query['limit']}') ?? 10;
        return reply({
          'views': _views(10).take(limit).toList(),
          'has_more': false,
        });
      });
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('That is the whole history.'));
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('a short first batch means there is nothing older at all', (
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
        final limit = int.tryParse('${call.query['limit']}') ?? 10;
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
      // The batch it already had is untouched.
      await _toTop(tester);
      expect(find.text('Product 0'), findsWidgets);

      await _toFooter(tester, find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      await _toFooter(tester, find.text('Product 12'));
      expect(find.text('Product 12'), findsOneWidget);
    });

    testWidgets('each product record is asked for once, and only when loaded', (
      tester,
    ) async {
      wireHistory(total: 40);
      api.onCall('GET', '/api/1688/product', (c) {
        final id = '${c.query['num_iid']}';
        return reply({
          'item': {'num_iid': id, 'title': 'x'},
        });
      });
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      List<String> detailIds() => [
        for (final c in api.calls)
          if (c.path == '/api/1688/product') '${c.query['num_iid']}',
      ];
      expect(detailIds().toSet(), {for (var i = 0; i < 10; i++) 'p$i'});

      await _toFooter(tester, find.text('Load More'));
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      final ids = detailIds();
      expect(ids.toSet(), {for (var i = 0; i < 20; i++) 'p$i'});
      expect(ids, hasLength(ids.toSet().length), reason: 'no id twice');
    });

    testWidgets('the purchased tab does not hold up the viewed one', (
      tester,
    ) async {
      wireHistory(total: 5);
      api.onCall(
        'GET',
        '/orders',
        (_) => reply(const [], delay: const Duration(seconds: 5)),
      );
      _tall(tester);

      await tester.pumpWidget(_wrap());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Well inside the five seconds the orders are held for.
      expect(find.text('Product 0'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('the first-load bones fill the space from the top', (
      tester,
    ) async {
      api.onCall(
        'GET',
        '/product-views',
        (_) => reply(_views(3), delay: const Duration(seconds: 2)),
      );
      _tall(tester);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      final skeleton = tester.widget<RecentViewsSkeleton>(
        find.byType(RecentViewsSkeleton),
      );
      final context = tester.element(find.byType(RecentViewsSkeleton));
      final listTop = tester.getTopLeft(find.byType(RecentViewsSkeleton)).dy;
      final available = 2000 - listTop;
      final perCard = RecentViewsSkeleton.cardExtent(context) + 8;
      expect(skeleton.rows * perCard, greaterThanOrEqualTo(available * 0.9));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(RecentViewsSkeleton), findsNothing);
      expect(find.text('Product 0'), findsOneWidget);
    });
  });

  group('on a phone, a tablet and a desktop', () {
    for (final size in const [
      Size(360, 740),
      Size(800, 1280),
      Size(1400, 900),
    ]) {
      testWidgets('${size.width.toInt()} dp: bones, then cards, no overflow', (
        tester,
      ) async {
        api.onCall('GET', '/product-views', (c) {
          final limit = int.tryParse('${c.query['limit']}') ?? 10;
          return reply(
            _views(30).take(limit).toList(),
            delay: const Duration(milliseconds: 500),
          );
        });
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_wrap());
        await tester.pump();
        expect(find.byType(RecentViewsSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.byType(RecentViewsSkeleton), findsNothing);
        expect(find.text('Product 0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
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

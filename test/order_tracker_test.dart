import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/auth/presentation/auth_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notifications_screen.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_tracker_button.dart';
import 'package:gtradea_amazon/features/orders/presentation/orders_screen.dart';
import 'package:gtradea_amazon/shared/widgets/brand_wordmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/orders.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

/// Seeds the store with one order per stage given.
void _seed(List<OrderStage> stages, {List<String> cancelled = const []}) {
  final orders = [
    for (var i = 0; i < stages.length; i++)
      seedOrder(reached: stages[i], id: 'order-$i'),
    for (final id in cancelled)
      seedOrder(reached: OrderStage.packed, id: id, status: 'cancelled'),
  ];
  OrderStore.instance.seedForTest(orders);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ensureApiStub();
    OrderStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('the in-flight count', () {
    test('counts an order that is still on its way', () {
      _seed([OrderStage.shipped, OrderStage.outForDelivery]);
      expect(OrderStore.instance.inFlightCount(), 2);
    });

    test('stops counting one once it has arrived', () {
      _seed([OrderStage.shipped, OrderStage.delivered]);
      expect(OrderStore.instance.inFlightCount(), 1);
    });

    test('does not count a cancelled order', () {
      // Called off is not on its way. Badging it would have someone waiting
      // at the door for a parcel nobody is sending.
      _seed([OrderStage.shipped], cancelled: ['order-c']);
      expect(OrderStore.instance.inFlightCount(), 1);
    });

    test('is zero once everything has landed', () {
      _seed([OrderStage.delivered, OrderStage.delivered]);
      expect(OrderStore.instance.inFlightCount(), 0);
    });

    test('is zero with no orders at all', () {
      expect(OrderStore.instance.inFlightCount(), 0);
    });
  });

  group('the tracker button', () {
    testWidgets('badges what is on the way and opens the orders list', (
      tester,
    ) async {
      signInForTest();
      _seed([OrderStage.shipped, OrderStage.packed]);

      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: OrderTrackerButton()))),
      );
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(find.byTooltip('2 orders on the way'), findsOneWidget);

      await tester.tap(find.byType(OrderTrackerButton));
      await tester.pumpAndSettle();

      expect(find.byType(OrdersScreen), findsOneWidget);
    });

    testWidgets('carries no badge when nothing is outstanding', (tester) async {
      signInForTest();
      _seed([OrderStage.delivered]);

      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: OrderTrackerButton()))),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Your orders'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      // The state reads without the badge too, which is what someone who
      // cannot make out a small red disc is left with.
      expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    });

    testWidgets('fills the icon while something is moving', (tester) async {
      signInForTest();
      _seed([OrderStage.shipped]);

      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: OrderTrackerButton()))),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.local_shipping), findsOneWidget);
      expect(find.byTooltip('1 order on the way'), findsOneWidget);
    });

    testWidgets('sends a guest to sign in, not to an empty orders page', (
      tester,
    ) async {
      // A guest has no orders, so opening the list would be a promise of
      // something that could never have anything in it for them.
      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: OrderTrackerButton()))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OrderTrackerButton));
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.byType(OrdersScreen), findsNothing);
    });
  });

  group('in the home header', () {
    testWidgets('sits to the left of the bell', (tester) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final tracker = tester.getRect(find.byType(OrderTrackerButton));
      final bell = tester.getRect(find.byType(NotificationBell));

      expect(tracker.right, lessThanOrEqualTo(bell.left));
    });

    testWidgets('does not push the bell off its margin', (tester) async {
      // The header aligns the bell's icon, not its box, to a 16pt inset. A new
      // sibling in the row is exactly the kind of change that would break it.
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final bell = tester.getRect(
        find.descendant(
          of: find.byType(NotificationBell),
          matching: find.byIcon(Icons.notifications_none),
        ),
      );

      // Still exactly on the margin after the icons shrank. This assertion is
      // what caught the drift: the header's right inset used to be a hardcoded
      // 12, which was half of (48 - 24) and silently assumed a 24pt glyph, so
      // a 21pt one pushed the bell 1.5pt past its margin.
      expect(bell.right, width - 16);
    });

    testWidgets('keeps a full tap target', (tester) async {
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final button = tester.getSize(
        find.descendant(
          of: find.byType(OrderTrackerButton),
          matching: find.byType(IconButton),
        ),
      );

      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
    });

    testWidgets('leaves the wordmark room at a large text scale', (
      tester,
    ) async {
      // The wordmark is inside an Expanded and just lost 48pt to the tracker.
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      for (final scale in [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SearchHeader(onTap: () {}),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'at ${scale}x');
        expect(find.byType(BrandWordmark), findsOneWidget);
      }
    });
  });
}

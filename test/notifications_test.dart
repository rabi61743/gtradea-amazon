import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/time_format.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/notifications/data/notification_store.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notification_settings_screen.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notifications_screen.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/orders.dart';

const _jacket = CartLine(
  productId: 'jacket',
  variantLabel: 'Blush pink',
  title: 'Ice silk jacket',
  unitPrice: 1130,
  freeDelivery: true,
);

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// An order the carrier says has reached [reached].
///
/// Notifications are derived from the stages an order has actually passed
/// through, which the server now decides rather than a clock.
Order _at(OrderStage reached) => seedOrder(
  reached: reached,
  status: reached == OrderStage.delivered ? 'delivered' : 'processing',
  lines: const [_jacket],
);

int _sync() =>
    NotificationStore.instance.syncFromOrders(OrderStore.instance.orders);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationStore.instance.resetForTest();
    NotificationSettings.instance.resetForTest();
    OrderStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('deriving notifications from orders', () {
    test('a brand new order announces placement and payment only', () {
      _at(OrderStage.placed);
      _sync();

      final categories = NotificationStore.instance.items
          .map((n) => n.category)
          .toSet();
      expect(categories, {
        NotificationCategory.orderPlaced,
        NotificationCategory.payment,
      });
    });

    test('an order that has run its course announces every stage', () {
      _at(OrderStage.delivered);
      _sync();

      final categories = NotificationStore.instance.items
          .map((n) => n.category)
          .toSet();
      for (final expected in [
        NotificationCategory.orderPlaced,
        NotificationCategory.orderConfirmed,
        NotificationCategory.orderPacked,
        NotificationCategory.orderShipped,
        NotificationCategory.orderOutForDelivery,
        NotificationCategory.orderDelivered,
      ]) {
        expect(categories, contains(expected), reason: expected.label);
      }
    });

    test('syncing twice does not announce anything twice', () {
      _at(OrderStage.delivered);
      final first = _sync();
      expect(first, greaterThan(0));

      expect(_sync(), 0, reason: 'nothing new has happened');
      expect(NotificationStore.instance.count, first);
    });

    test('a later stage is announced on the next sync, not before', () {
      // Placed just before the confirm boundary.
      _at(OrderStage.placed);
      _sync();
      expect(
        NotificationStore.instance.items.any(
          (n) => n.category == NotificationCategory.orderConfirmed,
        ),
        isFalse,
      );

      // The carrier moves it on, and the feed follows.
      _at(OrderStage.packed);
      NotificationStore.instance.syncFromOrders(OrderStore.instance.orders);
      expect(
        NotificationStore.instance.items.any(
          (n) => n.category == NotificationCategory.orderConfirmed,
        ),
        isTrue,
      );
    });

    test('a cancelled order is announced and stops there', () {
      final order = _at(OrderStage.placed);
      OrderStore.instance.cancel(order.id);
      _sync();

      final categories = NotificationStore.instance.items
          .map((n) => n.category)
          .toList();
      expect(categories, contains(NotificationCategory.orderCancelled));
      expect(categories, isNot(contains(NotificationCategory.orderShipped)));
    });

    test('a return is announced as a refund', () {
      final order = _at(OrderStage.delivered);
      OrderStore.instance.requestReturn(order.id);
      _sync();

      final returned = NotificationStore.instance.items.firstWhere(
        (n) => n.category == NotificationCategory.orderReturned,
      );
      expect(returned.body, contains('refund'));
    });

    test('a failed order gets no parcel announcements', () {
      final order = _at(OrderStage.delivered);
      OrderStore.instance.markFailed(order.id);
      NotificationStore.instance.resetForTest();
      _sync();

      final categories = NotificationStore.instance.items
          .map((n) => n.category)
          .toSet();
      // It never became a parcel, so saying it shipped would be a lie.
      expect(categories, isNot(contains(NotificationCategory.orderShipped)));
      expect(categories, isNot(contains(NotificationCategory.orderDelivered)));
      expect(
        categories,
        contains(NotificationCategory.orderCancelled),
        reason: 'a failure is reported, just not as a journey',
      );
    });

    test('order notifications carry the order they are about', () {
      final order = _at(OrderStage.placed);
      _sync();

      for (final item in NotificationStore.instance.items) {
        expect(item.orderId, order.id);
      }
    });
  });

  group('read, dismiss and undo', () {
    test('everything arrives unread', () {
      _at(OrderStage.placed);
      _sync();
      expect(
        NotificationStore.instance.unreadCount,
        NotificationStore.instance.count,
      );
      expect(NotificationStore.instance.hasUnread, isTrue);
    });

    test('one can be marked read without touching the others', () {
      _at(OrderStage.delivered);
      _sync();
      final before = NotificationStore.instance.unreadCount;

      NotificationStore.instance.markRead(
        NotificationStore.instance.items.first.id,
      );
      expect(NotificationStore.instance.unreadCount, before - 1);
    });

    test('marking all read clears the badge', () {
      _at(OrderStage.delivered);
      _sync();
      NotificationStore.instance.markAllRead();

      expect(NotificationStore.instance.unreadCount, 0);
      expect(NotificationStore.instance.hasUnread, isFalse);
      expect(
        NotificationStore.instance.isEmpty,
        isFalse,
        reason: 'read is not deleted',
      );
    });

    test('a dismissed notification does not come back on the next sync', () {
      _at(OrderStage.placed);
      _sync();
      final victim = NotificationStore.instance.items.first;

      NotificationStore.instance.remove(victim.id);
      expect(_sync(), 0);
      expect(
        NotificationStore.instance.items.any((n) => n.id == victim.id),
        isFalse,
        reason: 'dismissing it means dismissing it',
      );
    });

    test('undo puts it back where it was', () {
      _at(OrderStage.delivered);
      _sync();
      final victim = NotificationStore.instance.items[1];
      final index = NotificationStore.instance.indexOf(victim.id);

      NotificationStore.instance.remove(victim.id);
      NotificationStore.instance.restore(victim, index);
      expect(NotificationStore.instance.indexOf(victim.id), index);
    });

    test('newest is first', () {
      _at(OrderStage.delivered);
      _sync();
      final items = NotificationStore.instance.items;
      for (var i = 1; i < items.length; i++) {
        expect(
          items[i - 1].createdAt.isBefore(items[i].createdAt),
          isFalse,
          reason: 'entry $i is out of order',
        );
      }
    });
  });

  group('settings', () {
    test('everything is on by default', () {
      for (final group in NotificationGroup.values) {
        expect(NotificationSettings.instance.isEnabled(group), isTrue);
      }
    });

    test('a muted group produces nothing', () {
      NotificationSettings.instance.setEnabled(NotificationGroup.orders, false);
      _at(OrderStage.delivered);
      _sync();

      final groups = NotificationStore.instance.items
          .map((n) => n.category.group)
          .toSet();
      expect(groups, isNot(contains(NotificationGroup.orders)));
      expect(
        groups,
        contains(NotificationGroup.payment),
        reason: 'other groups are unaffected',
      );
    });

    test('turning a group back on does not backfill what it missed', () {
      NotificationSettings.instance.setEnabled(NotificationGroup.orders, false);
      _at(OrderStage.delivered);
      _sync();

      NotificationSettings.instance.setEnabled(NotificationGroup.orders, true);
      expect(_sync(), 0, reason: 'a muted push is gone, not queued');
    });

    test('a muted setting survives a reload', () async {
      NotificationSettings.instance.setEnabled(
        NotificationGroup.promotions,
        false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      NotificationSettings.instance.resetForTest();
      await NotificationSettings.instance.load();
      expect(
        NotificationSettings.instance.isEnabled(NotificationGroup.promotions),
        isFalse,
      );
    });
  });

  group('persistence', () {
    test('the feed and its read state survive a reload', () async {
      _at(OrderStage.placed);
      _sync();
      NotificationStore.instance.markAllRead();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final before = NotificationStore.instance.count;
      NotificationStore.instance.resetForTest();
      await NotificationStore.instance.load();

      expect(NotificationStore.instance.count, before);
      expect(NotificationStore.instance.unreadCount, 0);
    });

    test('a corrupt feed degrades to empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_notifications': 'not json',
      });
      NotificationStore.instance.resetForTest();
      await NotificationStore.instance.load();
      expect(NotificationStore.instance.isEmpty, isTrue);
    });

    test('an unknown category is dropped rather than guessed at', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_notifications':
            '{"items":[{"id":"a","category":"fromTheFuture","title":"X",'
            '"createdAt":1},{"id":"b","category":"promotion","title":"Y",'
            '"createdAt":2}],"delivered":["a","b"]}',
      });
      NotificationStore.instance.resetForTest();
      await NotificationStore.instance.load();
      expect(NotificationStore.instance.items.map((n) => n.id), ['b']);
    });

    test('dismissals survive a reload too', () async {
      _at(OrderStage.placed);
      _sync();
      final victim = NotificationStore.instance.items.first;
      NotificationStore.instance.remove(victim.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      NotificationStore.instance.resetForTest();
      await NotificationStore.instance.load();
      expect(_sync(), 0, reason: 'the dismissal was remembered');
    });
  });

  group('relative time', () {
    final now = DateTime(2026, 8, 23, 12);

    test('reads the way a person would say it', () {
      expect(formatRelative(now, now: now), 'Just now');
      expect(
        formatRelative(now.subtract(const Duration(seconds: 40)), now: now),
        'Just now',
      );
      expect(
        formatRelative(now.subtract(const Duration(minutes: 5)), now: now),
        '5 min ago',
      );
      expect(
        formatRelative(now.subtract(const Duration(hours: 1)), now: now),
        '1 hour ago',
      );
      expect(
        formatRelative(now.subtract(const Duration(hours: 3)), now: now),
        '3 hours ago',
      );
      expect(
        formatRelative(DateTime(2026, 8, 22, 23), now: now),
        'Yesterday',
        reason: 'calendar days, not 24-hour blocks',
      );
      expect(formatRelative(DateTime(2026, 8, 20, 12), now: now), '3 days ago');
      expect(formatRelative(DateTime(2026, 7, 4, 12), now: now), '4 Jul');
    });

    test(
      'a timestamp in the future rounds to now rather than reading oddly',
      () {
        expect(
          formatRelative(now.add(const Duration(minutes: 5)), now: now),
          'Just now',
        );
      },
    );

    test('day headings name today and yesterday', () {
      expect(formatDateHeading(now, now: now), 'Today');
      expect(
        formatDateHeading(DateTime(2026, 8, 22, 9), now: now),
        'Yesterday',
      );
      expect(
        formatDateHeading(DateTime(2026, 8, 1, 9), now: now),
        '1 Aug 2026',
      );
    });
  });

  group('NotificationsScreen', () {
    testWidgets('explains itself when empty', (tester) async {
      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Nothing to catch up on'), findsOneWidget);
      expect(find.text('Mark all read'), findsNothing);
    });

    testWidgets('lists notifications under a day heading', (tester) async {
      _useTallWindow(tester);
      _at(OrderStage.delivered);
      _sync();

      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Order delivered'), findsWidgets);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('Mark all read clears every unread marker', (tester) async {
      _useTallWindow(tester);
      _at(OrderStage.delivered);
      _sync();

      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      expect(NotificationStore.instance.unreadCount, 0);
      expect(find.text('Mark all read'), findsNothing);
      expect(find.byTooltip('Mark as read'), findsNothing);
    });

    testWidgets('a single one can be marked read from its dot', (tester) async {
      _useTallWindow(tester);
      _at(OrderStage.delivered);
      _sync();
      final before = NotificationStore.instance.unreadCount;

      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mark as read').first);
      await tester.pumpAndSettle();
      expect(NotificationStore.instance.unreadCount, before - 1);
    });

    testWidgets('tapping an order notification opens that order', (
      tester,
    ) async {
      _useTallWindow(tester);
      final order = _at(OrderStage.delivered);
      _sync();

      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Order delivered').first);
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text(order.displayReference), findsWidgets);
    });

    testWidgets('swiping a notification away dismisses it', (tester) async {
      _useTallWindow(tester);
      _at(OrderStage.delivered);
      _sync();
      final before = NotificationStore.instance.count;

      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(NotificationStore.instance.count, before - 1);
      expect(find.text('Undo'), findsOneWidget);
    });
  });

  group('NotificationBell', () {
    testWidgets('shows the unread count and opens the feed', (tester) async {
      _at(OrderStage.placed);
      _sync();
      final unread = NotificationStore.instance.unreadCount;

      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: NotificationBell()))),
      );
      await tester.pumpAndSettle();

      expect(find.text('$unread'), findsOneWidget);

      await tester.tap(find.byType(NotificationBell));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('carries no badge when everything has been read', (
      tester,
    ) async {
      _at(OrderStage.placed);
      _sync();
      NotificationStore.instance.markAllRead();

      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: NotificationBell()))),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });

  group('NotificationSettingsScreen', () {
    testWidgets('offers one switch per group and toggles it', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const NotificationSettingsScreen()));
      await tester.pumpAndSettle();

      for (final group in NotificationGroup.values) {
        expect(find.text(group.label), findsOneWidget, reason: group.label);
      }
      expect(
        find.byType(Switch),
        findsNWidgets(NotificationGroup.values.length),
      );

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(
        NotificationSettings.instance.isEnabled(NotificationGroup.orders),
        isFalse,
      );
    });

    testWidgets('says plainly that muting does not queue anything', (
      tester,
    ) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const NotificationSettingsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('will not fill in what you missed'),
        findsOneWidget,
      );
    });
  });
}

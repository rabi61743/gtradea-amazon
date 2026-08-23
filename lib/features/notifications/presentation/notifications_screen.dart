import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/time_format.dart';
import '../../orders/data/order_store.dart';
import '../../orders/presentation/order_detail_screen.dart';
import '../data/notification_store.dart';
import 'notification_settings_screen.dart';

/// Everything the shopper has been told, newest first, grouped by day.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    NotificationSettings.instance.load();
    NotificationStore.instance.load();
    OrderStore.instance.load();

    // Catch up on anything the orders have done since this was last opened,
    // including while the app was closed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    NotificationStore.instance.syncFromOrders(OrderStore.instance.orders);
  }

  /// A clock, only while an order can still produce something new. The
  /// relative timestamps also go stale without it -- "Just now" has to become
  /// "2 min ago" on its own.
  void _syncTicker() {
    final anyMoving =
        OrderStore.instance.orders.any((order) => !order.isSettled(_now));
    if (!anyMoving) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _sync();
      _syncTicker();
    });
  }

  void _open(AppNotification notification) {
    NotificationStore.instance.markRead(notification.id);

    final orderId = notification.orderId;
    if (orderId == null) return;
    // An order notification is a shortcut to that order, which is the only
    // useful place a tap on it could go.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
    );
  }

  void _dismiss(AppNotification notification) {
    final store = NotificationStore.instance;
    final index = store.indexOf(notification.id);
    store.remove(notification.id);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Notification dismissed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restore(notification, index),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        NotificationStore.instance,
        NotificationSettings.instance,
      ]),
      builder: (context, _) {
        final store = NotificationStore.instance;
        final items = store.items;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (store.hasUnread)
                TextButton(
                  onPressed: store.markAllRead,
                  child: const Text('Mark all read'),
                ),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Notification settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          body: items.isEmpty
              ? const _NoNotifications()
              : ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  children: [
                    for (final entry in _groupByDay(items, _now)) ...[
                      _DayHeading(label: entry.key),
                      for (final notification in entry.value)
                        Dismissible(
                          key: ValueKey(notification.id),
                          direction: DismissDirection.endToStart,
                          background: const _DismissBackground(),
                          onDismissed: (_) => _dismiss(notification),
                          child: _NotificationTile(
                            notification: notification,
                            now: _now,
                            onTap: () => _open(notification),
                            onMarkRead: notification.read
                                ? null
                                : () => store.markRead(notification.id),
                          ),
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  /// Days in order, each with its notifications.
  ///
  /// A list rather than a map so the order is the list's, not the hash's.
  static List<MapEntry<String, List<AppNotification>>> _groupByDay(
    List<AppNotification> items,
    DateTime now,
  ) {
    final groups = <MapEntry<String, List<AppNotification>>>[];
    for (final item in items) {
      final heading = formatDateHeading(item.createdAt, now: now);
      if (groups.isNotEmpty && groups.last.key == heading) {
        groups.last.value.add(item);
      } else {
        groups.add(MapEntry(heading, [item]));
      }
    }
    return groups;
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.now,
    required this.onTap,
    this.onMarkRead,
  });

  final AppNotification notification;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !notification.read;
    final (colour, icon) = categoryTone(context, notification.category);

    return Material(
      // Unread carries a tint as well as the dot: a single small dot is easy
      // to miss, and colour alone is not a cue everyone can use.
      color: unread
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colour.withValues(alpha: 0.12),
                ),
                child: Icon(icon, size: 19, color: colour),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatRelative(notification.createdAt, now: now),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              // Swipe dismisses, but a swipe is not discoverable and is hard
              // for some people, so unread also gets a plain tappable target.
              SizedBox(
                width: 34,
                child: unread
                    ? IconButton(
                        icon: const Icon(Icons.circle, size: 10),
                        color: theme.colorScheme.primary,
                        tooltip: 'Mark as read',
                        visualDensity: VisualDensity.compact,
                        onPressed: onMarkRead,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      color: theme.colorScheme.error.withValues(alpha: 0.12),
      child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
    );
  }
}

class _NoNotifications extends StatelessWidget {
  const _NoNotifications();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing to catch up on',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Order updates, payment news and offers will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Colour and icon for a category, shared with the settings screen so the two
/// cannot disagree about what an order update looks like.
(Color, IconData) categoryTone(
  BuildContext context,
  NotificationCategory category,
) {
  final theme = Theme.of(context);

  return switch (category) {
    NotificationCategory.orderPlaced => (
        theme.colorScheme.primary,
        Icons.receipt_long_outlined,
      ),
    NotificationCategory.orderConfirmed => (
        theme.colorScheme.primary,
        Icons.task_alt,
      ),
    NotificationCategory.orderPacked => (
        const Color(0xFF2563EB),
        Icons.inventory_2_outlined,
      ),
    NotificationCategory.orderShipped => (
        const Color(0xFF2563EB),
        Icons.local_shipping_outlined,
      ),
    NotificationCategory.orderOutForDelivery => (
        const Color(0xFFF97316),
        Icons.delivery_dining,
      ),
    NotificationCategory.orderDelivered => (
        const Color(0xFF059669),
        Icons.check_circle_outline,
      ),
    NotificationCategory.orderCancelled => (
        theme.colorScheme.error,
        Icons.cancel_outlined,
      ),
    NotificationCategory.orderReturned => (
        const Color(0xFFB45309),
        Icons.assignment_return_outlined,
      ),
    NotificationCategory.payment => (
        const Color(0xFF059669),
        Icons.payments_outlined,
      ),
    NotificationCategory.promotion => (
        const Color(0xFFE84326),
        Icons.local_offer_outlined,
      ),
    NotificationCategory.account => (
        theme.colorScheme.primary,
        Icons.person_outline,
      ),
  };
}

/// The bell, with its unread count. Lives here so the header and any other
/// entry point show the same thing.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.color, this.onOpened});

  final Color? color;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationStore.instance,
      builder: (context, _) {
        final unread = NotificationStore.instance.unreadCount;

        return IconButton(
          icon: Badge.count(
            count: unread,
            isLabelVisible: unread > 0,
            child: Icon(
              unread > 0 ? Icons.notifications : Icons.notifications_none,
              color: color,
            ),
          ),
          tooltip: unread > 0
              ? '$unread unread ${unread == 1 ? 'notification' : 'notifications'}'
              : 'Notifications',
          onPressed: () {
            onOpened?.call();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          },
        );
      },
    );
  }
}


import 'dart:async';

import '../../../core/theme/colors.dart';
import '../data/device_notifications.dart';
import '../../../core/network/api_error.dart';
import '../../quotes/data/quote_repository.dart';
import '../../quotes/presentation/quote_request_detail_screen.dart';
import '../../quotes/presentation/quote_requests_screen.dart';
import '../../support/data/support_repository.dart';
import '../../support/presentation/support_tickets_screen.dart';
import '../../support/presentation/ticket_detail_screen.dart';

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
    unawaited(_checkPermission());
  }

  /// Whether the device will show these on the lock screen.
  NotificationPermission _permission = NotificationPermission.granted;

  Future<void> _checkPermission() async {
    final state = await DeviceNotifications.instance.permission();
    if (mounted) setState(() => _permission = state);
  }

  /// Asks for permission here, and only here.
  ///
  /// This screen is the one place where the question makes obvious sense --
  /// the shopper is looking at their notifications and is being asked whether
  /// they want them on the lock screen too. Asking on first launch, before
  /// there is anything to notify about, is the pattern people refuse out of
  /// hand and can then never be asked again.
  Future<void> _askPermission() async {
    final state = await DeviceNotifications.instance.request();
    if (!mounted) return;
    setState(() => _permission = state);
    if (state == NotificationPermission.denied) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Turn notifications on for GTradeA in your device settings to '
              'see them on your lock screen.',
            ),
          ),
        );
    }
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
    final anyMoving = OrderStore.instance.orders.any(
      (order) => !order.isSettled(_now),
    );
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

  /// Opens whatever the notification is about.
  ///
  /// Each kind has one useful destination and no other: an order goes to that
  /// order, a quote to that quote, a support reply to that thread. A
  /// notification carrying no id -- a promotion, an account note -- is read
  /// and left where it is, because there is nowhere for it to go.
  Future<void> _open(AppNotification notification) async {
    NotificationStore.instance.markRead(notification.id);

    final orderId = notification.orderId;
    if (orderId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
      );
      return;
    }

    // The id the server put in the payload, when it put one there. Its key
    // is spelled differently by different producers, so several spellings are
    // read -- and when none of them is present the notification still goes
    // somewhere useful rather than nowhere at all.
    final targetId = notification.targetId;

    switch (notification.category) {
      case NotificationCategory.quote:
        await _openQuote(targetId);
      case NotificationCategory.support:
        await _openTicket(targetId);
      default:
        return;
    }
  }

  Future<void> _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  /// Fetches the quote by the id the notification carried, so the screen opens
  /// on the request the shopper was told about rather than on a list.
  Future<void> _openQuote(String? id) async {
    if (id == null || id.isEmpty) {
      await _push(const QuoteRequestsScreen());
      return;
    }
    try {
      final request = await QuoteRepository.instance.byId(id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuoteRequestDetailScreen(request: request),
        ),
      );
    } on ApiError {
      // The quote could not be read; the list is still somewhere to go.
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const QuoteRequestsScreen()));
    }
  }

  Future<void> _openTicket(String? id) async {
    if (id == null || id.isEmpty) {
      await _push(const SupportTicketsScreen());
      return;
    }
    try {
      final ticket = await SupportRepository.instance.byId(id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TicketDetailScreen(ticket: ticket)),
      );
    } on ApiError {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SupportTicketsScreen()));
    }
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
              ? Column(
                  children: [
                    _PermissionBanner(
                      state: _permission,
                      onAsk: _askPermission,
                    ),
                    const Expanded(child: _NoNotifications()),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  children: [
                    _PermissionBanner(
                      state: _permission,
                      onAsk: _askPermission,
                    ),
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
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w500,
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
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Order updates, payment news and offers will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    NotificationCategory.quote => (
      AppColors.commerceOrange,
      Icons.request_quote_outlined,
    ),
    NotificationCategory.support => (
      theme.colorScheme.primary,
      Icons.support_agent,
    ),
  };
}

/// The bell, with its unread count. Lives here so the header and any other
/// entry point show the same thing.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    this.color,
    this.size = 24,
    this.onOpened,
  });

  final Color? color;

  /// The glyph size. The header derives its right-hand inset from the same
  /// number, so the two cannot drift apart.
  final double size;

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
              // The size this bell was handed, not a copy of it.
              //
              // This was hardcoded to 21, which happened to be what the header
              // was passing, so the two agreed by coincidence rather than by
              // construction. The header derives its right-hand inset from the
              // size it passes -- see SearchHeader._bellEdge -- so the moment
              // that number changed, the glyph stayed put and the bell sat a
              // pixel off its margin. Same class of drift the derivation was
              // written to end.
              //
              // Smaller glyph, same 48pt box: the header row got tighter, the
              // thing people actually have to hit did not.
              size: size,
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

/// Offers lock-screen notifications, or explains why they are not appearing.
///
/// Absent entirely once they are allowed: a banner that stays after the answer
/// is just clutter on a screen the shopper opened to read something else.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.state, required this.onAsk});

  final NotificationPermission state;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    if (state == NotificationPermission.granted) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final asked = state == NotificationPermission.denied;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                asked
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asked
                          ? 'Notifications are turned off'
                          : 'Get these on your lock screen',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      asked
                          // Android stops showing the dialog after a refusal,
                          // so there is nothing to offer but the truth about
                          // where to change it.
                          ? 'Turn on notifications for GTradeA in your device '
                                'settings to see quotes and support replies '
                                'as they arrive.'
                          : 'Show quotes and support replies on your device '
                                'as soon as they arrive.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!asked) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: onAsk,
                        child: const Text('Turn on'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';
import '../../orders/data/order_store.dart';

/// What a notification is about.
///
/// One value per thing the shopper can be told, rather than a single "order"
/// bucket: the icon, the wording and the settings toggle all key off this, and
/// "Out for delivery" deserves to look different from "Order placed".
enum NotificationCategory {
  orderPlaced('Order placed', NotificationGroup.orders),
  orderConfirmed('Order confirmed', NotificationGroup.orders),
  orderPacked('Order packed', NotificationGroup.orders),
  orderShipped('Order shipped', NotificationGroup.orders),
  orderOutForDelivery('Out for delivery', NotificationGroup.orders),
  orderDelivered('Order delivered', NotificationGroup.orders),
  orderCancelled('Order cancelled', NotificationGroup.orders),
  orderReturned('Return and refund', NotificationGroup.orders),
  payment('Payment update', NotificationGroup.payment),
  promotion('Promotions and offers', NotificationGroup.promotions),
  account('Account update', NotificationGroup.account);

  const NotificationCategory(this.label, this.group);
  final String label;
  final NotificationGroup group;
}

/// What a shopper can switch off.
///
/// Four switches rather than eleven: nobody wants "Order packed" but not
/// "Order shipped", and a settings page with eleven toggles is one nobody
/// reads. The categories stay separate for display; only the control is
/// grouped.
enum NotificationGroup {
  orders('Order updates', 'Placed, packed, shipped and delivered'),
  payment('Payment updates', 'Charges, refunds and failures'),
  promotions('Promotions and offers', 'Sales, discounts and seasonal deals'),
  account('Account updates', 'Sign-ins and changes to your account');

  const NotificationGroup(this.label, this.detail);
  final String label;
  final String detail;
}

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.orderId,
  });

  /// Stable and derived from what the notification is about, never random:
  /// it is what stops the same delivery being announced twice.
  final String id;

  final NotificationCategory category;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// Set on order notifications, so tapping one can open that order.
  final String? orderId;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        category: category,
        title: title,
        body: body,
        createdAt: createdAt,
        read: read ?? this.read,
        orderId: orderId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'title': title,
        'body': body,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'read': read,
        'orderId': orderId,
      };

  static AppNotification? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final createdAt = json['createdAt'];
    if (id is! String || id.isEmpty || title is! String || createdAt is! int) {
      return null;
    }

    NotificationCategory? category;
    final name = json['category'];
    if (name is String) {
      for (final value in NotificationCategory.values) {
        if (value.name == name) category = value;
      }
    }
    // A category written by a newer build is one this build cannot render an
    // icon or a settings toggle for. Dropping it beats guessing.
    if (category == null) return null;

    return AppNotification(
      id: id,
      category: category,
      title: title,
      body: json['body'] is String ? json['body'] as String : '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      read: json['read'] == true,
      orderId: json['orderId'] is String ? json['orderId'] as String : null,
    );
  }
}

/// Which groups the shopper wants to hear about.
///
/// Separate from the notification list because it outlives it: emptying the
/// list must not switch everything back on.
class NotificationSettings extends ChangeNotifier {
  NotificationSettings._();

  static final instance = NotificationSettings._();

  static const _key = 'gtradea_notification_settings';

  final Set<NotificationGroup> _muted = {};
  bool _loaded = false;

  bool isEnabled(NotificationGroup group) => !_muted.contains(group);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_key);
      if (stored != null) {
        for (final name in stored) {
          for (final group in NotificationGroup.values) {
            if (group.name == name) _muted.add(group);
          }
        }
      }
    } catch (_) {
      // Unreadable: everything on, which is the default a shopper expects.
    }
    _loaded = true;
    notifyListeners();
  }

  void setEnabled(NotificationGroup group, bool enabled) {
    final changed = enabled ? _muted.remove(group) : _muted.add(group);
    if (!changed) return;
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _muted.clear();
    _loaded = false;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        _muted.map((group) => group.name).toList(),
      );
    } catch (_) {
      // Best effort, like the other stores.
    }
  }
}

/// The notification feed.
///
/// Order notifications are **derived, not evented.** An order's status comes
/// from the time since it was placed, so there is no moment at which the app
/// could have pushed "Shipped" -- it may not even have been running. Instead
/// [syncFromOrders] works out which announcements an order should have
/// produced by now and materialises the missing ones. That makes the feed
/// correct after a restart, and correct for an order that progressed while the
/// app was closed.
///
/// Every notification's id is derived from what it is about, and every id ever
/// produced is remembered in [_delivered]. That is what makes the sync
/// idempotent, and it is also what stops a notification the shopper deleted
/// from reappearing on the next sync.
class NotificationStore extends ChangeNotifier {
  NotificationStore._();

  static final instance = NotificationStore._();

  static const _guestKey = 'gtradea_notifications';

  /// The feed is a feed, not an archive. Older entries fall off the end.
  static const maxEntries = 60;

  final List<AppNotification> _items = [];

  /// Ids already handled, whether they became a notification or were dropped
  /// because their group was muted or the shopper deleted them.
  final Set<String> _delivered = {};

  String? _scope;
  bool _loaded = false;
  bool _bound = false;
  Future<void>? _loading;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isLoaded => _loaded;

  int get unreadCount => _items.where((item) => !item.read).length;
  bool get hasUnread => _items.any((item) => !item.read);

  static String storageKeyFor(String? email) => (email == null || email.isEmpty)
      ? _guestKey
      : 'gtradea_notifications_$email';

  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    (auth ?? AuthStore.instance).addListener(_onIdentityChanged);
  }

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _scope = AuthStore.instance.account?.email;
    await _readInto(storageKeyFor(_scope));
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  Future<void> _switchTo(String? email) async {
    if (email == _scope) return;
    _scope = email;
    // Notifications are not carried across identities the way a cart is.
    // They are about orders, and the orders themselves are already scoped --
    // announcing another account's deliveries would be a privacy leak, and
    // re-announcing this account's is what the sync is for.
    _items.clear();
    _delivered.clear();
    await _readInto(storageKeyFor(email));
    _loaded = true;
    notifyListeners();
  }

  /// Materialises the notifications [orders] should have produced by [now].
  ///
  /// Safe to call as often as you like: anything already announced is skipped.
  /// Returns the number of new notifications.
  int syncFromOrders(List<Order> orders, {DateTime? now}) {
    final at = now ?? DateTime.now();
    var added = 0;

    for (final order in orders) {
      // Payment first, because it is about placing the order rather than about
      // the parcel, and it should sit below the "Order placed" entry.
      added += _offer(
        id: 'payment:${order.id}',
        category: NotificationCategory.payment,
        createdAt: order.placedAt,
        orderId: order.id,
        title: order.paymentState.label,
        body: switch (order.paymentState) {
          PaymentState.cashOnDelivery =>
            'Pay ${_money(order.totals.total)} to the courier for ${order.id}.',
          PaymentState.pending =>
            'We are waiting for confirmation of ${_money(order.totals.total)} '
                'for ${order.id}.',
          PaymentState.paid =>
            '${_money(order.totals.total)} received for ${order.id}.',
          PaymentState.failed =>
            'The payment for ${order.id} did not go through.',
        },
      );

      final reached = order.stage(at);
      for (final stage in OrderStage.values) {
        if (stage.index > reached.index) break;
        // A failed order never got as far as a parcel, so it gets no stage
        // announcements beyond being placed.
        if (order.outcome == OrderOutcome.failed &&
            stage != OrderStage.placed) {
          break;
        }

        final category = _categoryFor(stage);
        added += _offer(
          id: 'order:${order.id}:${stage.name}',
          category: category,
          // When the carrier says it happened. Falling back to the order date
          // keeps a notification in a sane place in the feed when a step
          // carries no timestamp.
          createdAt: order.whenStageReached(stage) ?? order.placedAt,
          orderId: order.id,
          // The category's wording, not the stage's: a timeline row reads
          // "Delivered" in the context of an order, but a notification arrives
          // on its own and has to say what was delivered.
          title: category.label,
          body: _bodyFor(stage, order),
        );
      }

      final outcome = order.outcome;
      if (outcome != null) {
        added += _offer(
          id: 'order:${order.id}:${outcome.name}',
          category: outcome == OrderOutcome.returned
              ? NotificationCategory.orderReturned
              : NotificationCategory.orderCancelled,
          createdAt: order.outcomeAt ?? order.placedAt,
          orderId: order.id,
          title: switch (outcome) {
            OrderOutcome.cancelled => 'Order cancelled',
            OrderOutcome.returned => 'Return requested',
            OrderOutcome.failed => 'Order failed',
          },
          body: switch (outcome) {
            OrderOutcome.cancelled =>
              '${order.id} was cancelled. Nothing will be delivered.',
            OrderOutcome.returned =>
              'A courier will collect ${order.id}. Your refund of '
                  '${_money(order.totals.total)} follows once it arrives back.',
            OrderOutcome.failed =>
              '${order.id} could not be placed because the payment failed.',
          },
        );
      }
    }

    if (added > 0) {
      _sortAndTrim();
      notifyListeners();
      unawaited(_persist());
    }
    return added;
  }

  /// Records something that happened to the account itself.
  void recordAccountEvent({
    required String id,
    required String title,
    required String body,
    DateTime? at,
  }) {
    if (_offer(
          id: 'account:$id',
          category: NotificationCategory.account,
          createdAt: at ?? DateTime.now(),
          title: title,
          body: body,
        ) ==
        0) {
      return;
    }
    _sortAndTrim();
    notifyListeners();
    unawaited(_persist());
  }

  /// Records an offer. Ids are the caller's, so the same promotion is not
  /// announced twice across restarts.
  void recordPromotion({
    required String id,
    required String title,
    required String body,
    DateTime? at,
  }) {
    if (_offer(
          id: 'promo:$id',
          category: NotificationCategory.promotion,
          createdAt: at ?? DateTime.now(),
          title: title,
          body: body,
        ) ==
        0) {
      return;
    }
    _sortAndTrim();
    notifyListeners();
    unawaited(_persist());
  }

  /// Adds a notification unless it has been handled before or its group is
  /// muted. Returns 1 when something was actually added.
  int _offer({
    required String id,
    required NotificationCategory category,
    required DateTime createdAt,
    required String title,
    required String body,
    String? orderId,
  }) {
    if (_delivered.contains(id)) return 0;
    // Marked handled either way. A muted group must not backfill everything it
    // missed the moment it is switched back on -- that is not how a shopper
    // expects notifications to behave.
    _delivered.add(id);

    if (!NotificationSettings.instance.isEnabled(category.group)) return 0;

    _items.add(AppNotification(
      id: id,
      category: category,
      title: title,
      body: body,
      createdAt: createdAt,
      orderId: orderId,
    ));
    return 1;
  }

  void markRead(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1 || _items[index].read) return;
    _items[index] = _items[index].copyWith(read: true);
    notifyListeners();
    unawaited(_persist());
  }

  void markAllRead() {
    if (!hasUnread) return;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].read) _items[i] = _items[i].copyWith(read: true);
    }
    notifyListeners();
    unawaited(_persist());
  }

  /// Removes one notification for good. It stays in [_delivered], so the next
  /// sync does not put it back.
  void remove(String id) {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length == before) return;
    notifyListeners();
    unawaited(_persist());
  }

  void restore(AppNotification notification, int index) {
    if (_items.any((item) => item.id == notification.id)) return;
    _items.insert(index.clamp(0, _items.length), notification);
    notifyListeners();
    unawaited(_persist());
  }

  int indexOf(String id) => _items.indexWhere((item) => item.id == id);

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _items.clear();
    _delivered.clear();
    _scope = null;
    _loaded = false;
    _bound = false;
    _loading = null;
  }

  static NotificationCategory _categoryFor(OrderStage stage) =>
      switch (stage) {
        OrderStage.placed => NotificationCategory.orderPlaced,
        OrderStage.confirmed => NotificationCategory.orderConfirmed,
        OrderStage.packed => NotificationCategory.orderPacked,
        OrderStage.shipped => NotificationCategory.orderShipped,
        OrderStage.outForDelivery => NotificationCategory.orderOutForDelivery,
        OrderStage.delivered => NotificationCategory.orderDelivered,
      };

  static String _bodyFor(OrderStage stage, Order order) => switch (stage) {
        OrderStage.placed =>
          'We have got your order ${order.id}. We will confirm it shortly.',
        OrderStage.confirmed =>
          '${order.id} is confirmed and going to the warehouse.',
        OrderStage.packed => '${order.id} has been packed and is ready to go.',
        OrderStage.shipped =>
          '${order.id} is on its way with ${order.courier}.',
        OrderStage.outForDelivery =>
          '${order.id} is out for delivery today. Keep your phone nearby.',
        OrderStage.delivered => '${order.id} has been delivered. Enjoy it.',
      };

  /// Rupees without importing the storefront's formatter into the data layer.
  static String _money(num amount) {
    final whole = amount.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
      buffer.write(whole[i]);
    }
    return 'Rs. $buffer';
  }

  /// Newest first, capped.
  void _sortAndTrim() {
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_items.length > maxEntries) {
      _items.removeRange(maxEntries, _items.length);
    }
  }

  Future<void> _readInto(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final items = decoded['items'];
      if (items is List) {
        _items.addAll(
          items
              .whereType<Map>()
              .map((e) => AppNotification.fromJson(e.cast<String, dynamic>()))
              .whereType<AppNotification>(),
        );
      }
      final delivered = decoded['delivered'];
      if (delivered is List) {
        _delivered.addAll(delivered.whereType<String>());
      }
      _sortAndTrim();
    } catch (_) {
      // Unreadable feed: start empty rather than blocking the app.
    }
  }

  Future<void> _persist() {
    final key = storageKeyFor(_scope);
    // Trimmed alongside the feed. Without a bound this grows forever, and its
    // only job is to stop recent things being announced twice.
    final delivered = _delivered.length > maxEntries * 4
        ? _delivered.toList().sublist(_delivered.length - maxEntries * 4)
        : _delivered.toList();

    final payload = jsonEncode({
      'items': _items.map((item) => item.toJson()).toList(),
      'delivered': delivered,
    });
    return _write(key, payload);
  }

  /// Serialised, for the same reason the cart and order stores serialise
  /// theirs: two rapid mutations must not land out of order.
  Future<void> _writes = Future<void>.value();

  Future<void> _write(String key, String payload) {
    return _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, payload);
      } catch (_) {
        // Best effort, like the other stores.
      }
    });
  }
}

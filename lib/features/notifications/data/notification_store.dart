import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_store.dart';
import 'notification_repository.dart';
import 'device_notifications.dart';
import 'notification_sound.dart';
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
  account('Account update', NotificationGroup.account),
  // Raised by the server, not worked out here: a seller answering a quote and
  // support replying to a ticket are things only the shop knows about.
  quote('Quote update', NotificationGroup.quotes),
  support('Support reply', NotificationGroup.support);

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
  account('Account updates', 'Sign-ins and changes to your account'),
  quotes('Quote requests', 'Prices and replies from sellers'),
  support('Support replies', 'Answers to the messages you send us');

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
    this.targetId,
    this.fromServer = false,
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

  /// The quote request or support ticket this is about, when it is about one.
  final String? targetId;

  /// True when the shop raised this rather than the device working it out.
  ///
  /// It decides where a read goes: marking a server notification read has to
  /// reach the server, or it comes back unread on the next sync.
  final bool fromServer;

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

  /// Where [accountId]'s choices live. A guest's are the original key.
  ///
  /// Per account: two people sharing a device each decide what they are told
  /// about, and one muting promotions does not mute them for the other.
  static String storageKeyFor(String? accountId) =>
      (accountId == null || accountId.isEmpty) ? _key : '${_key}_$accountId';

  final Set<NotificationGroup> _muted = {};
  bool _loaded = false;

  /// The account whose choices are held; null for a guest.
  String? _scope;
  bool _bound = false;
  int _epoch = 0;

  bool isEnabled(NotificationGroup group) => !_muted.contains(group);
  bool get isLoaded => _loaded;

  /// Follows the active account for the rest of the app's life.
  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    (auth ?? AuthStore.instance).addListener(_onIdentityChanged);
  }

  void _onIdentityChanged() {
    final id = AuthStore.instance.account?.id;
    if (id == _scope && _loaded) return;
    _scope = id;
    _epoch++;
    // Everything on until this account's own choices are read, rather than
    // the last account's mutes applying for the length of a disk read.
    _muted.clear();
    notifyListeners();
    // As with the first load: choices still under the device-wide key become
    // this account's, once, only if it has none of its own yet.
    unawaited(_readInto(storageKeyFor(id), _epoch, migrateLegacy: true));
  }

  Future<void> load() async {
    if (_loaded) return;
    _scope = AuthStore.instance.account?.id;
    await _readInto(storageKeyFor(_scope), _epoch, migrateLegacy: true);
  }

  Future<void> _readInto(
    String key,
    int epoch, {
    bool migrateLegacy = false,
  }) async {
    final found = <NotificationGroup>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      var stored = prefs.getStringList(key);
      // Before choices were kept per account they were the device's, set by
      // whoever was signed in. They become that account's, once.
      if (migrateLegacy && stored == null && key != _key) {
        stored = prefs.getStringList(_key);
        if (stored != null) {
          await prefs.setStringList(key, stored);
          await prefs.remove(_key);
        }
      }
      if (stored != null) {
        for (final name in stored) {
          for (final group in NotificationGroup.values) {
            if (group.name == name) found.add(group);
          }
        }
      }
    } catch (_) {
      // Unreadable: everything on, which is the default a shopper expects.
    }
    if (epoch != _epoch) return;
    _muted
      ..clear()
      ..addAll(found);
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
    _scope = null;
    _epoch++;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        storageKeyFor(_scope),
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

  /// The server notifications this device has already chimed for.
  ///
  /// Separate from [_delivered], which is about what has been *shown*: a
  /// notification can legitimately be shown again after a reinstall, and it
  /// must not sound again for it.
  final Set<String> _announced = {};

  /// True once a sync has completed, so the first one -- which is every
  /// notification the account already had -- is silent.
  bool _syncedOnce = false;

  /// The most device notifications one batch may post.
  static const _maxPosted = 5;

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

  /// Tells the shopper that something arrived: on the device, or failing that
  /// with a chime.
  ///
  /// **Exactly one sound per batch.** A posted device notification already
  /// carries the platform's own tone -- the one the shopper chose, at the
  /// notification volume, silenced by Do Not Disturb -- so playing the in-app
  /// chime on top of it made two sounds for one event. The chime is the
  /// fallback for when nothing was posted: permission refused, no notification
  /// service, or the post failed.
  ///
  /// One device notification per arrival rather than one per batch: the shade
  /// is a list, and collapsing four events into a single line would lose
  /// three. Capped, because a shopper returning after a fortnight should not
  /// have forty pushed at them at once. [_announced] is what stops the same
  /// event being posted twice.
  Future<void> _announce(List<AppNotification> arrived) async {
    var anyPosted = false;
    for (final row in arrived.take(_maxPosted)) {
      if (await DeviceNotifications.instance.show(row)) anyPosted = true;
    }
    if (!anyPosted) await NotificationSound.instance.play();
  }

  /// Reads the list, and refreshes the shop's half of it.
  ///
  /// Called on a cold start, on pull-to-refresh, and by the live event that
  /// says something arrived. It used to return immediately once loaded, which
  /// meant a realtime notification event refreshed nothing at all -- the one
  /// path that most needed to reach the server was the one that never did.
  Future<void> load() {
    if (_loaded) return syncFromServer();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _scope = AuthStore.instance.account?.email;
    await _readInto(storageKeyFor(_scope));
    _loaded = true;
    _loading = null;
    notifyListeners();
    // The device's own copy is on screen first, then the shop's. Waiting on a
    // request before showing anything would leave the bell empty on every cold
    // start.
    await syncFromServer();
  }

  /// Merges the shop's notifications into the list.
  ///
  /// **This is what was missing.** Everything a server raises -- a seller
  /// answering a quote, support replying to a ticket -- lives in the shop's
  /// notifications table, and this store only ever read what the device could
  /// work out for itself. A live event arrived, called [load], and reloaded
  /// local storage.
  ///
  /// Server rows win where the ids collide, because the server is the
  /// authority on whether one has been read. Locally-derived notifications --
  /// the order announcements this app has always made -- are left alone.
  ///
  /// Failures are swallowed: a notification list that empties itself because
  /// the network blinked is worse than one that is briefly out of date.
  /// Bumped on every change of account, so a list asked for as one account
  /// is never merged into the next one's.
  int _epoch = 0;

  Future<void> syncFromServer() async {
    if (!AuthStore.instance.isSignedIn) return;
    final epoch = _epoch;
    List<AppNotification> rows;
    try {
      rows = await NotificationRepository.instance.list();
    } on ApiError {
      return;
    }
    if (epoch != _epoch) return;
    // A successful read counts as a sync even when it changes nothing, or the
    // next one would be treated as the first and stay silent for something
    // that genuinely just arrived.
    final first = !_syncedOnce;
    _syncedOnce = true;

    if (rows.isEmpty && _items.every((item) => !item.fromServer)) return;

    final byId = {for (final item in _items) item.id: item};
    for (final row in rows) {
      // A row removed on this device stays removed rather than reappearing.
      if (_delivered.contains(row.id) && !byId.containsKey(row.id)) continue;
      byId[row.id] = row;
    }
    // Anything the server no longer has is gone from the server's half only.
    final serverIds = {for (final row in rows) row.id};
    byId.removeWhere((id, item) => item.fromServer && !serverIds.contains(id));

    // What is genuinely new: on the server, unread, and not chimed for
    // before. Worked out before the list is replaced, because afterwards there
    // is nothing left to compare against.
    final arrived = [
      for (final row in rows)
        if (!row.read && !_announced.contains(row.id)) row,
    ];
    _announced.addAll(rows.map((row) => row.id));

    _items
      ..clear()
      ..addAll(byId.values);
    _sortAndTrim();
    notifyListeners();
    unawaited(_persist());

    // Silent on the first sync: everything the account already had is not
    // news, and a chime on opening the app is exactly the "plays on load"
    // nobody wants.
    if (!first && arrived.isNotEmpty) {
      // Awaited: posting is a handful of quick platform calls, and letting the
      // sync finish first made the order of a batch depend on scheduling.
      await _announce(arrived);
    }
  }

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  Future<void> _switchTo(String? email) async {
    if (email == _scope) return;
    _epoch++;
    _scope = email;
    // Notifications are not carried across identities the way a cart is.
    // They are about orders, and the orders themselves are already scoped --
    // announcing another account's deliveries would be a privacy leak, and
    // re-announcing this account's is what the sync is for.
    _items.clear();
    _delivered.clear();
    // A different account starts over: its first sync is silent, and nothing
    // the previous one chimed for counts as announced here.
    _announced.clear();
    _syncedOnce = false;
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

    _items.add(
      AppNotification(
        id: id,
        category: category,
        title: title,
        body: body,
        createdAt: createdAt,
        orderId: orderId,
      ),
    );
    return 1;
  }

  void markRead(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1 || _items[index].read) return;
    final item = _items[index];
    _items[index] = item.copyWith(read: true);
    notifyListeners();
    unawaited(_persist());
    // Or it comes back unread on the next sync, and the badge counts it again.
    // Best effort: the shopper has read it either way, and a failed request is
    // not a reason to show it as unread on the device it was read on.
    if (item.fromServer) {
      unawaited(
        NotificationRepository.instance.markRead(id).catchError((_) {}),
      );
    }
  }

  void markAllRead() {
    if (!hasUnread) return;
    final anyFromServer = _items.any((item) => !item.read && item.fromServer);
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].read) _items[i] = _items[i].copyWith(read: true);
    }
    notifyListeners();
    unawaited(_persist());
    if (anyFromServer) {
      unawaited(
        NotificationRepository.instance.markAllRead().catchError((_) {}),
      );
    }
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

  /// Deletes several notifications for good, the server first.
  ///
  /// Returns the ids that could **not** be deleted, so the caller can say so
  /// and leave them on screen. Nothing is taken off the list until the server
  /// has agreed to it: a row that vanishes and comes back on the next sync is
  /// worse than one that never went.
  ///
  /// Notifications this device derived from its own orders have no server row
  /// to delete -- those go straight away.
  ///
  /// The requests go together rather than one after another: deleting six
  /// selected rows should not take six round trips end to end.
  Future<Set<String>> deleteMany(Iterable<String> ids) async {
    final wanted = ids.toSet();
    final byId = {
      for (final item in _items)
        if (wanted.contains(item.id)) item.id: item,
    };
    if (byId.isEmpty) return const {};

    final failed = <String>{};
    await Future.wait([
      for (final entry in byId.entries)
        if (entry.value.fromServer)
          NotificationRepository.instance
              .remove(entry.key)
              .catchError((Object _) => failed.add(entry.key)),
    ]);

    final gone = byId.keys.where((id) => !failed.contains(id)).toSet();
    if (gone.isEmpty) return failed;

    _items.removeWhere((item) => gone.contains(item.id));
    // Kept in [_delivered] by the same rule [remove] follows, so the next sync
    // does not put them back.
    notifyListeners();
    unawaited(_persist());
    return failed;
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
    _announced.clear();
    _syncedOnce = false;
    _scope = null;
    _loaded = false;
    _bound = false;
    _loading = null;
  }

  static NotificationCategory _categoryFor(OrderStage stage) => switch (stage) {
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
    OrderStage.shipped => '${order.id} is on its way with ${order.courier}.',
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

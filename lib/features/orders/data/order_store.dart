import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';
import '../../cart/data/cart_store.dart';

/// The happy path a parcel walks, in order.
///
/// Only these six are stages. Cancelled, returned and failed are not further
/// along the same road -- they are departures from it, and modelling them as
/// extra stages would put "Cancelled" after "Delivered" on the timeline.
enum OrderStage {
  placed('Order placed'),
  confirmed('Confirmed'),
  packed('Packed'),
  shipped('Shipped'),
  outForDelivery('Out for delivery'),
  delivered('Delivered');

  const OrderStage(this.label);
  final String label;
}

/// A departure from the happy path.
enum OrderOutcome {
  cancelled('Cancelled'),
  returned('Returned'),
  failed('Failed');

  const OrderOutcome(this.label);
  final String label;
}

enum PaymentState {
  cashOnDelivery('Cash on delivery', 'Pay the courier when it arrives'),
  pending('Payment pending', 'Waiting for confirmation'),
  paid('Paid', 'Payment received'),
  failed('Payment failed', 'The payment did not go through');

  const PaymentState(this.label, this.detail);
  final String label;
  final String detail;
}

/// One placed order.
///
/// The lines are [CartLine]s, the same snapshots the cart held, so an order
/// keeps the prices the shopper agreed to rather than whatever the catalogue
/// says later.
@immutable
class Order {
  const Order({
    required this.id,
    required this.placedAt,
    required this.lines,
    required this.delivery,
    this.discount = 0,
    this.couponCode,
    required this.recipient,
    required this.address,
    required this.paymentState,
    this.outcome,
    this.outcomeAt,
  });

  final String id;
  final DateTime placedAt;
  final List<CartLine> lines;

  /// The delivery actually charged, frozen. See [CartTotals.of].
  final num delivery;

  /// What a coupon took off, and which one. Frozen for the same reason as the
  /// delivery: an offer expiring must not rewrite what an old order cost.
  final num discount;
  final String? couponCode;

  final String recipient;
  final String address;
  final PaymentState paymentState;

  /// Set only when the order left the happy path.
  final OrderOutcome? outcome;
  final DateTime? outcomeAt;

  CartTotals get totals => CartTotals.of(
        lines,
        delivery: delivery,
        discount: discount,
        couponCode: couponCode,
      );

  /// How long after placement each stage is reached.
  ///
  /// **Compressed on purpose.** There is no courier API here, so progress is
  /// derived from the clock in order to be observable at all -- a real build
  /// replaces [stageAt] with the carrier's status and this table disappears.
  /// The estimated delivery is read off the same table, so the two can never
  /// contradict each other.
  static const stageAfter = <Duration>[
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 9),
    Duration(minutes: 14),
  ];

  /// Which stage an order placed at [placedAt] has reached by [now].
  static OrderStage stageAt(DateTime placedAt, DateTime now) {
    final elapsed = now.difference(placedAt);
    var reached = OrderStage.placed;
    for (var i = 0; i < stageAfter.length; i++) {
      if (elapsed >= stageAfter[i]) reached = OrderStage.values[i];
    }
    return reached;
  }

  /// The furthest stage reached.
  ///
  /// An order that left the happy path is frozen at the stage it had got to
  /// when it left: a parcel cancelled while packed did not go on to ship.
  OrderStage stage([DateTime? now]) {
    final at = outcomeAt ?? now ?? DateTime.now();
    return stageAt(placedAt, at);
  }

  DateTime whenStageReached(OrderStage stage) =>
      placedAt.add(stageAfter[stage.index]);

  DateTime get estimatedDelivery => whenStageReached(OrderStage.delivered);

  /// True once nothing further will happen on its own.
  bool isSettled([DateTime? now]) =>
      outcome != null || stage(now) == OrderStage.delivered;

  /// What to show as the headline status.
  String statusLabel([DateTime? now]) =>
      outcome?.label ?? stage(now).label;

  /// Cancelling is only honest while the parcel has not left.
  bool canCancel([DateTime? now]) =>
      outcome == null && stage(now).index < OrderStage.shipped.index;

  /// Returns are offered once it has actually arrived.
  bool canReturn([DateTime? now]) =>
      outcome == null && stage(now) == OrderStage.delivered;

  /// A courier reference only exists once something was handed to a courier.
  String? trackingNumber([DateTime? now]) {
    if (outcome == OrderOutcome.cancelled || outcome == OrderOutcome.failed) {
      return null;
    }
    if (stage(now).index < OrderStage.shipped.index) return null;
    return 'GTX${id.replaceAll(RegExp('[^0-9A-Z]'), '')}';
  }

  String get courier => 'GtradeA Express';

  Order copyWith({OrderOutcome? outcome, DateTime? outcomeAt}) => Order(
        id: id,
        placedAt: placedAt,
        lines: lines,
        delivery: delivery,
        discount: discount,
        couponCode: couponCode,
        recipient: recipient,
        address: address,
        paymentState: outcome == OrderOutcome.failed
            ? PaymentState.failed
            : paymentState,
        outcome: outcome ?? this.outcome,
        outcomeAt: outcomeAt ?? this.outcomeAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'placedAt': placedAt.millisecondsSinceEpoch,
        'lines': lines.map((line) => line.toJson()).toList(),
        'delivery': delivery,
        'discount': discount,
        'couponCode': couponCode,
        'recipient': recipient,
        'address': address,
        'paymentState': paymentState.name,
        'outcome': outcome?.name,
        'outcomeAt': outcomeAt?.millisecondsSinceEpoch,
      };

  static Order? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final placedAt = json['placedAt'];
    if (id is! String || id.isEmpty || placedAt is! int) return null;

    final rawLines = json['lines'];
    final lines = rawLines is List
        ? rawLines
            .whereType<Map>()
            .map((e) => CartLine.fromJson(e.cast<String, dynamic>()))
            .whereType<CartLine>()
            .toList()
        : <CartLine>[];
    // An order with no readable lines is not an order; it would render as an
    // empty receipt for a total nobody can check.
    if (lines.isEmpty) return null;

    return Order(
      id: id,
      placedAt: DateTime.fromMillisecondsSinceEpoch(placedAt),
      lines: lines,
      delivery: json['delivery'] is num ? json['delivery'] as num : 0,
      discount: json['discount'] is num ? json['discount'] as num : 0,
      couponCode:
          json['couponCode'] is String ? json['couponCode'] as String : null,
      recipient: json['recipient'] is String
          ? json['recipient'] as String
          : 'Guest',
      address: json['address'] is String ? json['address'] as String : '',
      paymentState: _enumByName(
        PaymentState.values,
        json['paymentState'],
        PaymentState.cashOnDelivery,
      ),
      outcome: _enumByNameOrNull(OrderOutcome.values, json['outcome']),
      outcomeAt: json['outcomeAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['outcomeAt'] as int)
          : null,
    );
  }

  static T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      _enumByNameOrNull(values, name) ?? fallback;

  static T? _enumByNameOrNull<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Orders the shopper has placed, newest first.
///
/// Scoped per shopper exactly like [CartStore]: a guest key and a key per
/// account, with guest orders carried into the account on sign-in. An order
/// placed before signing in is still that person's order.
class OrderStore extends ChangeNotifier {
  OrderStore._();

  static final instance = OrderStore._();

  static const _guestKey = 'gtradea_orders';

  final List<Order> _orders = [];
  String? _scope;
  bool _loaded = false;
  bool _bound = false;
  Future<void>? _loading;

  List<Order> get orders => List.unmodifiable(_orders);
  int get count => _orders.length;
  bool get isEmpty => _orders.isEmpty;
  bool get isLoaded => _loaded;

  static String storageKeyFor(String? email) =>
      (email == null || email.isEmpty) ? _guestKey : 'gtradea_orders_$email';

  Order? byId(String id) {
    for (final order in _orders) {
      if (order.id == id) return order;
    }
    return null;
  }

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
    final hadPending = _orders.isNotEmpty;

    final stored = <Order>[];
    await _readInto(stored, storageKeyFor(_scope));
    for (final order in stored) {
      if (_orders.any((existing) => existing.id == order.id)) continue;
      _orders.add(order);
    }
    _sort();

    _loaded = true;
    _loading = null;
    notifyListeners();

    if (hadPending) unawaited(_persist());
  }

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  Future<void> _switchTo(String? email) async {
    if (email == _scope) return;

    final wasGuest = _scope == null || _scope!.isEmpty;
    final carried = wasGuest ? List<Order>.from(_orders) : const <Order>[];

    _scope = email;
    _orders.clear();
    await _readInto(_orders, storageKeyFor(email));

    if (email != null && carried.isNotEmpty) {
      for (final order in carried) {
        if (_orders.any((existing) => existing.id == order.id)) continue;
        _orders.add(order);
      }
      unawaited(_clearStored(_guestKey));
      unawaited(_persist());
    }
    _sort();

    _loaded = true;
    notifyListeners();
  }

  /// Records a placed order and returns it.
  Order place({
    required List<CartLine> lines,
    required num delivery,
    num discount = 0,
    String? couponCode,
    required String recipient,
    required String address,
    required PaymentState paymentState,
    DateTime? placedAt,
  }) {
    final when = placedAt ?? DateTime.now();
    final order = Order(
      id: _nextId(when),
      placedAt: when,
      lines: List.unmodifiable(lines),
      delivery: delivery,
      discount: discount,
      couponCode: couponCode,
      recipient: recipient,
      address: address,
      paymentState: paymentState,
    );

    _orders.insert(0, order);
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
    return order;
  }

  /// Human-readable and unique within a millisecond, which is as fine-grained
  /// as two orders can realistically be placed here.
  String _nextId(DateTime when) {
    var candidate = 'GT${when.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    var suffix = 1;
    while (_orders.any((order) => order.id == candidate)) {
      candidate = 'GT${when.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}$suffix';
      suffix++;
    }
    return candidate;
  }

  bool cancel(String id, {DateTime? now}) =>
      _settle(id, OrderOutcome.cancelled, now, (order) => order.canCancel(now));

  bool requestReturn(String id, {DateTime? now}) =>
      _settle(id, OrderOutcome.returned, now, (order) => order.canReturn(now));

  /// Marks an order failed.
  ///
  /// No code path invents a failure -- there is no payment gateway here to
  /// fail. This exists so the state is reachable when one is wired up, and so
  /// the screens that render it can be tested.
  bool markFailed(String id, {DateTime? now}) =>
      _settle(id, OrderOutcome.failed, now, (order) => order.outcome == null);

  bool _settle(
    String id,
    OrderOutcome outcome,
    DateTime? now,
    bool Function(Order) allowed,
  ) {
    final index = _orders.indexWhere((order) => order.id == id);
    if (index == -1) return false;
    if (!allowed(_orders[index])) return false;

    _orders[index] = _orders[index]
        .copyWith(outcome: outcome, outcomeAt: now ?? DateTime.now());
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  void clear() {
    if (_orders.isEmpty) return;
    _orders.clear();
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _orders.clear();
    _scope = null;
    _loaded = false;
    _bound = false;
    _loading = null;
  }

  /// Newest first. Orders are appended on load and inserted on placement, and
  /// a merge can interleave two sources, so the order is asserted rather than
  /// assumed.
  void _sort() => _orders.sort((a, b) => b.placedAt.compareTo(a.placedAt));

  Future<void> _readInto(List<Order> target, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      target.addAll(
        decoded
            .whereType<Map>()
            .map((e) => Order.fromJson(e.cast<String, dynamic>()))
            .whereType<Order>(),
      );
    } catch (_) {
      // Unreadable history: show none rather than blocking the account page.
    }
  }

  /// Key and payload captured before the first await, so a write meant for the
  /// guest cannot land under an account key switched to in between.
  Future<void> _persist() {
    final key = storageKeyFor(_scope);
    final payload = jsonEncode(_orders.map((order) => order.toJson()).toList());
    return _write(key, payload);
  }

  /// Writes run one after another, in the order they were asked for.
  ///
  /// Without the chain, two mutations in quick succession -- placing an order
  /// and immediately cancelling it -- are two concurrent writes whose
  /// completion order is not guaranteed, so the older payload can land last
  /// and the newer state is silently lost on the next read.
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

  Future<void> _clearStored(String key) {
    return _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {
        // See _write.
      }
    });
  }
}

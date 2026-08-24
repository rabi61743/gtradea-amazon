import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../cart/data/cart_store.dart';
import 'orders_repository.dart';

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
    this.reference,
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
    this.server,
    this.tracking,
  });

  final String id;

  /// What the shopper sees and quotes to support. The id is a UUID; the
  /// reference is the short number the server prints on the order.
  ///
  /// Falls back to the id for an order placed on this device that the server
  /// has not numbered yet.
  final String? reference;

  String get displayReference => reference ?? id;

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

  /// The order as the server describes it, once it has been fetched.
  ///
  /// Null only for an order this device placed and has not yet read back.
  final ServerOrder? server;

  /// The carrier's view, when the tracking endpoint has answered.
  final OrderTracking? tracking;

  CartTotals get totals => CartTotals.of(
        lines,
        delivery: delivery,
        discount: discount,
        couponCode: couponCode,
      );

  /// Which stage this order has reached.
  ///
  /// Read from the carrier where there is a carrier, and from the order's own
  /// status otherwise. Nothing here is derived from the clock: an order does
  /// not become "shipped" because five minutes passed, and the previous
  /// build's compressed timetable was a placeholder that said it did.
  ///
  /// The [now] parameter is kept so the screens and their tests need no
  /// change, and is deliberately unused.
  OrderStage stage([DateTime? now]) {
    final steps = tracking?.timeline ?? const <TrackingStep>[];
    if (steps.isNotEmpty) {
      OrderStage? furthest;
      for (final step in steps) {
        if (step.state == TrackingStepState.upcoming) continue;
        final mapped = _stageFromCode(step.stage) ?? _stageFromText(step.label);
        if (mapped == null) continue;
        if (furthest == null || mapped.index > furthest.index) furthest = mapped;
      }
      if (furthest != null) return furthest;
    }

    final status = server?.status;
    if (status != null && status.isNotEmpty) {
      return _stageFromText(status) ?? OrderStage.placed;
    }

    // Placed on this device and not yet read back. It has been placed, and
    // claiming anything further would be a guess.
    return OrderStage.placed;
  }

  /// Maps a carrier stage code onto the six stages this app shows.
  ///
  /// The carrier's vocabulary is its own and can grow; an unrecognised code
  /// contributes nothing rather than resetting the progress to the start.
  static OrderStage? _stageFromCode(String code) =>
      _stageFromText(code.toLowerCase().replaceAll('_', ' '));

  static OrderStage? _stageFromText(String raw) {
    final text = raw.toLowerCase();
    // Checked before 'deliver', because "out for delivery" contains it and is
    // emphatically not the same thing as delivered.
    if (text.contains('out for deliver') || text.contains('out_for_deliver')) {
      return OrderStage.outForDelivery;
    }
    if (text.contains('deliver') || text.contains('complete')) {
      return OrderStage.delivered;
    }
    if (text.contains('ship') ||
        text.contains('transit') ||
        text.contains('dispatch')) {
      return OrderStage.shipped;
    }
    if (text.contains('pack') || text.contains('ready')) {
      return OrderStage.packed;
    }
    if (text.contains('confirm') || text.contains('accept')) {
      return OrderStage.confirmed;
    }
    if (text.contains('placed') || text.contains('pending')) {
      return OrderStage.placed;
    }
    return null;
  }

  /// When each stage was actually reached, where the carrier said so.
  DateTime? whenStageReached(OrderStage stage) {
    for (final step in tracking?.timeline ?? const <TrackingStep>[]) {
      if (step.state == TrackingStepState.upcoming) continue;
      final mapped = _stageFromCode(step.stage) ?? _stageFromText(step.label);
      if (mapped == stage) return step.reachedAt;
    }
    if (stage == OrderStage.placed) return placedAt;
    if (stage == OrderStage.delivered) return tracking?.deliveredAt;
    return null;
  }

  /// The window the order is expected in, as the carrier quotes it.
  ///
  /// Null when nobody has committed to one yet -- which the screen says, rather
  /// than inventing a date the shop has not promised.
  DateTime? get estimatedDelivery =>
      tracking?.deliveredAt ?? tracking?.etaTo ?? tracking?.etaFrom;

  /// True when the estimate is a guess rather than a commitment.
  bool get deliveryIsEstimate => tracking?.etaEstimated ?? true;

  bool get isBehindSchedule => tracking?.behindSchedule ?? false;

  /// True once nothing further will happen on its own.
  bool isSettled([DateTime? now]) =>
      outcome != null ||
      (server?.isCancelled ?? false) ||
      stage(now) == OrderStage.delivered;

  /// What to show as the headline status.
  ///
  /// The carrier's own wording wins where there is any: it knows more about
  /// its states than a six-way client-side map does.
  String statusLabel([DateTime? now]) {
    if (outcome != null) return outcome!.label;
    if (server?.isCancelled ?? false) return OrderOutcome.cancelled.label;
    final carrier = tracking?.statusLabel;
    if (carrier != null && carrier.isNotEmpty) return carrier;
    return stage(now).label;
  }

  /// Cancelling is only honest while the parcel has not left.
  bool canCancel([DateTime? now]) =>
      outcome == null &&
      !(server?.isCancelled ?? false) &&
      !(server?.isDelivered ?? false) &&
      stage(now).index < OrderStage.shipped.index;

  /// Returns are offered once it has actually arrived.
  bool canReturn([DateTime? now]) =>
      outcome == null &&
      !(server?.isCancelled ?? false) &&
      stage(now) == OrderStage.delivered;

  /// The carrier's own reference, or nothing.
  ///
  /// Never invented. A made-up number that no courier can look up is worse
  /// than no number, because a shopper will spend time trying to use it.
  String? trackingNumber([DateTime? now]) {
    if (outcome == OrderOutcome.cancelled || outcome == OrderOutcome.failed) {
      return null;
    }
    // Nothing to track until something was handed to a courier. A shipment
    // number that exists before dispatch is not one anybody can look up yet.
    if (stage(now).index < OrderStage.shipped.index) return null;
    final number = tracking?.shipments.firstOrNull?.shipmentNo;
    return (number != null && number.isNotEmpty) ? number : null;
  }

  /// How the parcel is travelling, where the carrier said.
  String? get courier {
    final label = tracking?.shipments.firstOrNull?.modeLabel;
    return (label != null && label.isNotEmpty) ? label : null;
  }

  /// Builds the screen's view of an order from the server's record.
  ///
  /// [cached] is whatever this device already held for the same order. Used
  /// only to fill gaps -- a photograph the server does not return, or the
  /// tracking already fetched -- never to override a figure the server sent.
  factory Order.fromServer(ServerOrder row, [Order? cached]) {
    final address = row.shippingAddress;
    final recipient = asString(address['full_name']) ??
        asString(address['name']) ??
        cached?.recipient ??
        '';

    final lines = row.items.isEmpty
        ? (cached?.lines ?? const <CartLine>[])
        : [
            for (final item in row.items)
              CartLine(
                productId: item.sourceProductId ?? item.productId ?? item.id,
                variantLabel: item.variantLabel,
                title: item.name,
                unitPrice: item.unitPrice ?? 0,
                imageUrl: item.imageUrl,
                quantity: item.quantity,
              ),
          ];

    return Order(
      id: row.id,
      // Shown to the shopper and quoted to support; the id is a UUID nobody
      // can read over the phone.
      reference: row.orderNumber.isEmpty ? row.id : row.orderNumber,
      placedAt: row.placedAt ?? cached?.placedAt ?? DateTime.now(),
      lines: List.unmodifiable(lines),
      delivery: cached?.delivery ?? 0,
      discount: cached?.discount ?? 0,
      couponCode: cached?.couponCode,
      recipient: recipient,
      address: _addressLine(address) ?? cached?.address ?? '',
      paymentState: _paymentStateOf(row),
      outcome: row.isCancelled ? OrderOutcome.cancelled : null,
      server: row,
      tracking: cached?.tracking,
    );
  }

  Order withTracking(OrderTracking tracking) => Order(
        id: id,
        reference: reference,
        placedAt: placedAt,
        lines: lines,
        delivery: delivery,
        discount: discount,
        couponCode: couponCode,
        recipient: recipient,
        address: address,
        paymentState: paymentState,
        outcome: outcome,
        outcomeAt: outcomeAt,
        server: server,
        tracking: tracking,
      );

  /// The address on one line, from whichever fields the server filled in.
  static String? _addressLine(Map<String, dynamic> address) {
    final parts = [
      asString(address['address_line1']) ?? asString(address['street']),
      asString(address['address_line2']),
      asString(address['city']),
      asString(address['state']),
      asString(address['postal_code']),
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Free text on the wire, so matched by substring rather than mapped from a
  /// closed set the server never promised.
  static PaymentState _paymentStateOf(ServerOrder row) {
    if (row.paymentFailed) return PaymentState.failed;
    if (row.isPaid) return PaymentState.paid;
    final method = row.paymentMethod?.toLowerCase() ?? '';
    if (method.contains('cod') || method.contains('cash')) {
      return PaymentState.cashOnDelivery;
    }
    return PaymentState.pending;
  }

  Order copyWith({OrderOutcome? outcome, DateTime? outcomeAt}) => Order(
        id: id,
        reference: reference,
        server: server,
        tracking: tracking,
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
        'reference': reference,
        // Enough of the server's record to show the right stage offline. The
        // whole row is not worth caching -- the tracking is fetched again on
        // open anyway, and a stale carrier timeline is worse than none.
        'serverStatus': server?.status,
        'serverPaymentStatus': server?.paymentStatus,
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
      reference: asString(json['reference']),
      server: asString(json['serverStatus']) == null
          ? null
          : ServerOrder(
              id: id,
              orderNumber: asString(json['reference']) ?? '',
              status: asString(json['serverStatus'])!,
              paymentStatus: asString(json['serverPaymentStatus']) ?? '',
            ),
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

  // ---------------------------------------------------------------------
  // Server
  // ---------------------------------------------------------------------

  bool _refreshing = false;
  ApiError? _error;

  ApiError? get error => _error;
  bool get isRefreshing => _refreshing;

  /// Fetches the account's orders and replaces what is held.
  ///
  /// Orders are the server's record, not this device's. The local copy exists
  /// only so the list renders on a dead connection.
  Future<void> refreshFromServer() async {
    if (!AuthStore.instance.isSignedIn || _refreshing) return;
    _refreshing = true;
    notifyListeners();

    try {
      final rows = await OrdersRepository.instance.list();
      final cached = {for (final order in _orders) order.id: order};
      _orders
        ..clear()
        ..addAll(rows.map((row) => Order.fromServer(row, cached[row.id])));
      _sort();
      _error = null;
    } on ApiError catch (e) {
      // Whatever was cached stays. An empty order history shown because the
      // network failed is the single most alarming thing this screen can say.
      _error = e;
    } finally {
      _refreshing = false;
      notifyListeners();
      unawaited(_persist());
    }
  }

  /// Loads the carrier's view of one order and attaches it.
  ///
  /// Separate from the order itself because it is a separate request, it fails
  /// on its own, and most screens never need it.
  Future<void> loadTracking(String orderId) async {
    if (!AuthStore.instance.isSignedIn) return;
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index == -1) return;

    try {
      final tracking = await OrdersRepository.instance.tracking(orderId);
      final at = _orders.indexWhere((order) => order.id == orderId);
      if (at == -1) return;
      _orders[at] = _orders[at].withTracking(tracking);
      notifyListeners();
    } on ApiError {
      // The order still renders without it; the screen says tracking is not
      // available rather than failing whole.
    }
  }

  /// Asks the server to cancel, then takes its word for what happened.
  ///
  /// Returns false when the request was refused, so the screen can say the
  /// parcel has already gone out rather than appearing to succeed.
  Future<bool> requestCancellation(
    String orderId, {
    String reason = 'changed_mind',
    String? details,
  }) async {
    try {
      await OrdersRepository.instance.requestCancellation(
        orderId: orderId,
        reason: reason,
        details: details,
      );
      await refreshFromServer();
      return true;
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestReturnFor(
    String orderId, {
    String reason = 'changed_mind',
    String? details,
  }) async {
    final order = byId(orderId);
    final items = order?.server?.items ?? const <ServerOrderItem>[];
    if (items.isEmpty) return false;

    try {
      await OrdersRepository.instance.requestReturn(
        orderId: orderId,
        reason: reason,
        details: details,
        items: [
          for (final item in items)
            (orderItemId: item.id, quantity: item.quantity),
        ],
      );
      await refreshFromServer();
      return true;
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      return false;
    }
  }

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

    // The account's orders are the record. The cache above only exists so the
    // list renders before this answers, and on a dead connection.
    await refreshFromServer();
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

    if (email != null) unawaited(refreshFromServer());
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

  /// Puts orders in the store without a server, for tests.
  @visibleForTesting
  void seedForTest(List<Order> orders) {
    for (final order in orders) {
      _orders.removeWhere((existing) => existing.id == order.id);
      _orders.add(order);
    }
    _sort();
    _loaded = true;
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

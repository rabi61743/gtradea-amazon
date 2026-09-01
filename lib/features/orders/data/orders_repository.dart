import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// One line of an order, as the server recorded it.
///
/// A snapshot, not a link to the catalogue: what was bought and what it cost
/// at the time. A product whose price later moved, or which was withdrawn
/// entirely, must still show correctly on an old order.
class ServerOrderItem {
  const ServerOrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    this.unitPrice,
    this.imageUrl,
    this.variantLabel,
    this.productId,
    this.sourceProductId,
  });

  /// The order_items row id. Returning an item needs this, not the product id.
  final String id;

  final String name;
  final int quantity;
  final num? unitPrice;
  final String? imageUrl;
  final String? variantLabel;

  /// Null on an imported line, which carries [sourceProductId] instead. Which
  /// one is set is what decides whether the product can be reviewed or
  /// reordered.
  final String? productId;
  final String? sourceProductId;

  num get lineTotal => (unitPrice ?? 0) * quantity;

  factory ServerOrderItem.fromJson(
    Map<String, dynamic> json,
  ) => ServerOrderItem(
    id: asString(json['id']) ?? '',
    name: asString(json['product_name']) ?? asString(json['name']) ?? 'Item',
    quantity: asInt(json['quantity']) ?? 1,
    unitPrice: asNum(json['unit_price']) ?? asNum(json['price']),
    imageUrl: asString(json['product_image']) ?? asString(json['image_url']),
    variantLabel: asString(json['variant_label']),
    productId: asString(json['product_id']),
    sourceProductId: asString(json['source_product_id']),
  );
}

/// An order as the server holds it.
///
/// `status` and `paymentStatus` are free text, not enums. The server is free to
/// add a state, and a client that treated them as a closed set would fail to
/// decode an order rather than showing an unfamiliar label.
class ServerOrder {
  const ServerOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    this.placedAt,
    this.totalAmount,
    this.advanceAmount,
    this.remainingAmount,
    this.paymentMethod,
    this.shippingAddress = const {},
    this.items = const [],
  });

  final String id;
  final String orderNumber;

  /// Free text, lowercased on the way in so every comparison downstream can
  /// stop worrying about case.
  final String status;
  final String paymentStatus;

  final DateTime? placedAt;

  /// Postgres `numeric` reaches JSON as a string often enough that a cast here
  /// would be a real bug, so these are parsed rather than cast.
  final num? totalAmount;
  final num? advanceAmount;
  final num? remainingAmount;

  final String? paymentMethod;
  final Map<String, dynamic> shippingAddress;
  final List<ServerOrderItem> items;

  /// True once the goods have arrived. Matched by substring because the server
  /// says 'delivered' in some places and 'completed' in others.
  bool get isDelivered =>
      status.contains('deliver') || status.contains('complete');

  bool get isCancelled =>
      status.contains('cancel') || status.contains('refund');

  bool get isPaid =>
      paymentStatus.contains('paid') || paymentStatus.contains('complete');

  bool get paymentFailed => paymentStatus.contains('fail');

  factory ServerOrder.fromJson(Map<String, dynamic> json) => ServerOrder(
    id: asString(json['id']) ?? '',
    orderNumber: asString(json['order_number']) ?? '',
    status: (asString(json['status']) ?? '').toLowerCase(),
    paymentStatus: (asString(json['payment_status']) ?? '').toLowerCase(),
    placedAt: asDate(json['created_at']) ?? asDate(json['placed_at']),
    totalAmount: asNum(json['total_amount']),
    advanceAmount: asNum(json['advance_amount']),
    remainingAmount: asNum(json['remaining_amount']),
    paymentMethod: asString(json['payment_method']),
    shippingAddress: asMap(json['shipping_address']),
    items: asRows(json['items'] ?? json['order_items'])
        .map(ServerOrderItem.fromJson)
        .toList(growable: false),
  );
}

/// Where one step of the journey has got to.
enum TrackingStepState {
  done,
  current,
  upcoming;

  /// Lenient by design. This is the only enum decoded straight off the wire in
  /// this domain, and a value nobody anticipated must not blank a whole
  /// tracking screen -- an unfamiliar step is simply one not reached yet.
  static TrackingStepState parse(Object? raw) {
    switch (asString(raw)?.toLowerCase()) {
      case 'done':
      case 'complete':
      case 'completed':
        return TrackingStepState.done;
      case 'current':
      case 'active':
      case 'in_progress':
        return TrackingStepState.current;
      default:
        return TrackingStepState.upcoming;
    }
  }
}

class TrackingStep {
  const TrackingStep({
    required this.stage,
    required this.label,
    required this.state,
    this.reachedAt,
  });

  /// An upper-snake code such as ORDER_CONFIRMED or TRANSIT. Not an enum: the
  /// carrier's vocabulary is the carrier's to change.
  final String stage;

  /// What to show. Server-authored, rendered verbatim.
  final String label;

  final TrackingStepState state;
  final DateTime? reachedAt;

  bool get isDelivery => stage.toUpperCase().contains('DELIVER');

  factory TrackingStep.fromJson(Map<String, dynamic> json) => TrackingStep(
    stage: asString(json['stage']) ?? '',
    label: asString(json['label']) ?? '',
    state: TrackingStepState.parse(json['status']),
    reachedAt: asDate(json['reachedAt']),
  );
}

/// A parcel, and where it has got to.
class TrackingShipment {
  const TrackingShipment({
    this.shipmentNo = '',
    this.mode = '',
    this.modeLabel = '',
    this.stageMessage,
    this.delayed = false,
    this.delayMessage,
    this.etaFrom,
    this.etaTo,
    this.timeline = const [],
  });

  final String shipmentNo;

  /// air, sea or land. Anything else renders as a plain parcel rather than
  /// failing -- the mode is decoration, not information the shopper acts on.
  final String mode;
  final String modeLabel;
  final String? stageMessage;
  final bool delayed;
  final String? delayMessage;
  final DateTime? etaFrom;
  final DateTime? etaTo;
  final List<TrackingStep> timeline;

  factory TrackingShipment.fromJson(Map<String, dynamic> json) {
    final eta = asMap(json['eta']);
    return TrackingShipment(
      shipmentNo: asString(json['shipmentNo']) ?? '',
      mode: asString(json['mode']) ?? '',
      modeLabel: asString(json['modeLabel']) ?? '',
      stageMessage: asString(json['stageMessage']),
      delayed: asBool(json['delayed']),
      delayMessage: asString(json['delayMessage']),
      etaFrom: asDate(eta['from']),
      etaTo: asDate(eta['to']),
      timeline: asRows(json['timeline'])
          .map(TrackingStep.fromJson)
          .toList(growable: false),
    );
  }
}

/// The carrier's view of an order.
///
/// The one camelCase payload in this API; every other order endpoint is
/// snake_case. Decoded exactly as sent rather than normalised, because
/// normalising it would be a second place for the two conventions to drift.
class OrderTracking {
  const OrderTracking({
    this.orderNo = '',
    this.statusLabel = '',
    this.stageCode = '',
    this.stageLabel = '',
    this.placedAt,
    this.deliveredAt,
    this.etaFrom,
    this.etaTo,
    this.etaEstimated = false,
    this.behindSchedule = false,
    this.shipments = const [],
    this.updates = const [],
  });

  final String orderNo;

  /// Server-authored summary of where the order is. Shown verbatim -- the
  /// carrier knows more about its own states than a client-side map would.
  final String statusLabel;

  final String stageCode;
  final String stageLabel;
  final DateTime? placedAt;
  final DateTime? deliveredAt;
  final DateTime? etaFrom;
  final DateTime? etaTo;

  /// True when the window is a guess rather than a commitment.
  final bool etaEstimated;
  final bool behindSchedule;

  final List<TrackingShipment> shipments;
  final List<TrackingUpdate> updates;

  bool get hasShipments => shipments.isNotEmpty;

  /// The whole journey, flattened. Most orders are a single parcel; when there
  /// are several, the first one's timeline is the one the stepper follows.
  List<TrackingStep> get timeline =>
      shipments.isEmpty ? const [] : shipments.first.timeline;

  factory OrderTracking.fromJson(Map<String, dynamic> json) {
    final stage = asMap(json['orderStage']);
    final eta = asMap(json['completionEta']);
    return OrderTracking(
      orderNo: asString(json['orderNo']) ?? '',
      statusLabel: asString(json['statusLabel']) ?? '',
      stageCode: asString(stage['code']) ?? '',
      stageLabel: asString(stage['label']) ?? '',
      placedAt: asDate(json['placedAt']),
      deliveredAt: asDate(json['deliveredAt']),
      etaFrom: asDate(eta['from']),
      etaTo: asDate(eta['to']),
      etaEstimated: asBool(json['etaEstimated']),
      behindSchedule: asBool(json['etaBehindSchedule']),
      shipments: asRows(json['shipments'])
          .map(TrackingShipment.fromJson)
          .toList(growable: false),
      updates: asRows(json['updates'])
          .map(TrackingUpdate.fromJson)
          .toList(growable: false),
    );
  }
}

/// One entry in the running log of what has happened to an order.
class TrackingUpdate {
  const TrackingUpdate({required this.title, this.at, this.type = ''});

  final String title;
  final DateTime? at;
  final String type;

  factory TrackingUpdate.fromJson(Map<String, dynamic> json) => TrackingUpdate(
    title: asString(json['title']) ?? '',
    at: asDate(json['at']),
    type: asString(json['type']) ?? '',
  );
}

/// A cancellation or return the shopper has asked for.
class OrderRequest {
  const OrderRequest({
    required this.id,
    required this.number,
    required this.status,
    required this.reason,
    required this.isReturn,
    this.createdAt,
  });

  final String id;
  final String number;
  final String status;
  final String reason;
  final bool isReturn;
  final DateTime? createdAt;

  factory OrderRequest.fromJson(
    Map<String, dynamic> json, {
    required bool isReturn,
  }) => OrderRequest(
    id: asString(json['id']) ?? '',
    // Two endpoints, two names for the same thing.
    number:
        asString(json['return_number']) ??
        asString(json['request_number']) ??
        '',
    status: (asString(json['status']) ?? 'pending').toLowerCase(),
    reason: asString(json['reason']) ?? '',
    isReturn: isReturn,
    createdAt: asDate(json['created_at']),
  );
}

/// Orders, their tracking, and the requests raised against them.
class OrdersRepository {
  OrdersRepository._();

  static final OrdersRepository instance = OrdersRepository._();

  Dio get _dio => ApiClient.http;

  /// Every order, newest first as the server sends them.
  ///
  /// A bare array. If the server ever wrapped it, an empty list would be
  /// indistinguishable from having no orders -- so the rows are read through
  /// the same tolerant helper as everything else.
  Future<List<ServerOrder>> list() => guarded(() async {
    final res = await _dio.get('/orders');
    return asRows(res.data, key: 'orders')
        .map(ServerOrder.fromJson)
        .where((order) => order.id.isNotEmpty)
        .toList(growable: false);
  });

  Future<ServerOrder> byId(String id) => guarded(() async {
    final res = await _dio.get('/orders/${Uri.encodeComponent(id)}');
    return ServerOrder.fromJson(asMap(res.data));
  });

  Future<OrderTracking> tracking(String id) => guarded(() async {
    final res = await _dio.get('/orders/${Uri.encodeComponent(id)}/tracking');
    return OrderTracking.fromJson(asMap(res.data));
  });

  /// Asks to cancel. The server decides; this only raises the request.
  Future<void> requestCancellation({
    required String orderId,
    required String reason,
    String? details,
  }) => guarded(() async {
    await _dio.post(
      '/order-cancellations',
      data: {
        'order_id': orderId,
        'reason': reason,
        // Omitted rather than sent empty: the two mean different things to
        // the server, and an empty string is not "no details given".
        'reason_details': ?(details != null && details.isNotEmpty
            ? details
            : null),
      },
    );
  });

  Future<void> requestReturn({
    required String orderId,
    required String reason,
    required List<({String orderItemId, int quantity})> items,
    String refundMethod = 'original_payment',
    String? details,
  }) => guarded(() async {
    await _dio.post(
      '/returns',
      data: {
        'order_id': orderId,
        'reason': reason,
        'refund_method': refundMethod,
        'reason_details': ?(details != null && details.isNotEmpty
            ? details
            : null),
        'items': [
          for (final item in items)
            {'order_item_id': item.orderItemId, 'quantity': item.quantity},
        ],
      },
    );
  });

  /// Both kinds of request, in one list.
  Future<List<OrderRequest>> requests() => guarded(() async {
    final results = await Future.wait([
      _requests('/order-cancellations', 'requests', isReturn: false),
      _requests('/returns', 'returns', isReturn: true),
    ]);
    return [...results[0], ...results[1]];
  });

  Future<List<OrderRequest>> _requests(
    String path,
    String key, {
    required bool isReturn,
  }) async {
    try {
      final res = await _dio.get(path);
      return asRows(res.data, key: key)
          .map((row) => OrderRequest.fromJson(row, isReturn: isReturn))
          .toList(growable: false);
    } catch (_) {
      // One list failing should not hide the other.
      return const [];
    }
  }
}

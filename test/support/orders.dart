import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/data/orders_repository.dart';

/// The carrier stage codes the six shown stages map onto.
const _stageCodes = {
  OrderStage.placed: 'ORDER_PLACED',
  OrderStage.confirmed: 'ORDER_CONFIRMED',
  OrderStage.packed: 'PACKED',
  OrderStage.shipped: 'TRANSIT',
  OrderStage.outForDelivery: 'OUT_FOR_DELIVERY',
  OrderStage.delivered: 'DELIVERED',
};

/// A `/orders` row.
Map<String, dynamic> orderJson({
  String id = 'order-1',
  String orderNumber = 'GT-1001',
  String status = 'pending',
  String paymentStatus = 'pending',
  String paymentMethod = 'cod',
  DateTime? placedAt,
  List<CartLine> lines = const [],
}) => {
  'id': id,
  'order_number': orderNumber,
  'status': status,
  'payment_status': paymentStatus,
  'payment_method': paymentMethod,
  'created_at': (placedAt ?? DateTime.now()).toUtc().toIso8601String(),
  // A string, as Postgres numeric reaches JSON.
  'total_amount': '2260',
  'shipping_address': const {
    'full_name': 'Rabi',
    'address_line1': 'Jhamsikhel',
    'city': 'Lalitpur',
    'state': 'Bagmati',
  },
  'items': [
    for (var i = 0; i < lines.length; i++)
      {
        'id': 'item-$i',
        'product_name': lines[i].title,
        'quantity': lines[i].quantity,
        'unit_price': lines[i].unitPrice,
        'variant_label': lines[i].variantLabel,
        'source_product_id': lines[i].productId,
        'product_image': lines[i].imageUrl,
      },
  ],
};

/// A `/orders/{id}/tracking` payload with the timeline walked up to [reached].
///
/// camelCase, because that endpoint is camelCase while every other order
/// endpoint is snake_case -- a fixture that quietly normalised it would prove
/// nothing about the decoding.
Map<String, dynamic> trackingJson({
  required OrderStage reached,
  String shipmentNo = 'SHIP-77',
  String statusLabel = '',
  DateTime? deliveredAt,
  DateTime? etaTo,
  bool behindSchedule = false,
}) => {
  'orderNo': 'GT-1001',
  'statusLabel': statusLabel,
  'orderStage': {'code': _stageCodes[reached], 'label': reached.label},
  'completionEta': {'to': etaTo?.toUtc().toIso8601String()},
  'etaEstimated': false,
  'etaBehindSchedule': behindSchedule,
  'deliveredAt': deliveredAt?.toUtc().toIso8601String(),
  'shipments': [
    {
      // A carrier assigns a consignment number when the parcel is handed over,
      // not when the order is placed. The fixture used to emit one at every
      // stage, which meant the app's "no number before dispatch" test passed
      // because of a client-side stage gate rather than because of the data.
      'shipmentNo': reached.index >= OrderStage.shipped.index ? shipmentNo : '',
      'mode': 'land',
      'modeLabel': 'Road freight',
      'timeline': [
        for (final stage in OrderStage.values)
          {
            'stage': _stageCodes[stage],
            'label': stage.label,
            'status': stage.index < reached.index
                ? 'done'
                : stage.index == reached.index
                ? 'current'
                : 'upcoming',
            'reachedAt': stage.index <= reached.index
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          },
      ],
    },
  ],
  'updates': const [],
};

/// A tracking payload written in a **carrier's** vocabulary.
///
/// [trackingJson] above builds its steps out of `OrderStage`, so a test using
/// it asserts the app's own six labels and cannot tell whether the screen is
/// rendering the server's words or its own. This one knows nothing about
/// `OrderStage`: every label, code and state is given by the caller, so a test
/// written against it fails if the app substitutes a vocabulary of its own.
Map<String, dynamic> carrierTrackingJson({
  List<({String stage, String label, String status, DateTime? at})> steps =
      const [],
  List<Map<String, dynamic>> shipments = const [],
  String shipmentNo = 'SHIP-77',
  String modeLabel = 'Road freight',
  String mode = 'land',
  String statusLabel = '',
  String? stageMessage,
  bool delayed = false,
  String? delayMessage,
  List<Map<String, dynamic>> updates = const [],
  DateTime? etaTo,
}) => {
  'orderNo': 'GT-1001',
  'statusLabel': statusLabel,
  'completionEta': {'to': etaTo?.toUtc().toIso8601String()},
  'etaEstimated': false,
  'shipments': shipments.isNotEmpty
      ? shipments
      : [
          {
            'shipmentNo': shipmentNo,
            'mode': mode,
            'modeLabel': modeLabel,
            'stageMessage': stageMessage,
            'delayed': delayed,
            'delayMessage': delayMessage,
            'timeline': [
              for (final step in steps)
                {
                  'stage': step.stage,
                  'label': step.label,
                  'status': step.status,
                  'reachedAt': step.at?.toUtc().toIso8601String(),
                },
            ],
          },
        ],
  'updates': updates,
};

/// One shipment, for the multi-parcel case.
Map<String, dynamic> carrierShipment({
  required String shipmentNo,
  required String modeLabel,
  String mode = 'land',
  List<({String stage, String label, String status, DateTime? at})> steps =
      const [],
}) => {
  'shipmentNo': shipmentNo,
  'mode': mode,
  'modeLabel': modeLabel,
  'timeline': [
    for (final step in steps)
      {
        'stage': step.stage,
        'label': step.label,
        'status': step.status,
        'reachedAt': step.at?.toUtc().toIso8601String(),
      },
  ],
};

/// Puts one order in the store, at a given stage, without a server.
Order seedOrder({
  OrderStage reached = OrderStage.placed,
  String id = 'order-1',
  String status = 'pending',
  String paymentStatus = 'pending',
  String paymentMethod = 'cod',
  List<CartLine> lines = const [],
  DateTime? placedAt,
  bool withTracking = true,
  DateTime? etaTo,
  bool behindSchedule = false,

  /// Used instead of [trackingJson] when given, so a test can hand the store a
  /// carrier payload the app has no vocabulary for.
  Map<String, dynamic>? trackingOverride,
}) {
  var order = Order.fromServer(
    ServerOrder.fromJson(
      orderJson(
        id: id,
        status: status,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        placedAt: placedAt,
        lines: lines,
      ),
    ),
  );

  if (trackingOverride != null) {
    order = order.withTracking(OrderTracking.fromJson(trackingOverride));
  } else if (withTracking) {
    order = order.withTracking(
      OrderTracking.fromJson(
        trackingJson(
          reached: reached,
          deliveredAt: reached == OrderStage.delivered ? DateTime.now() : null,
          etaTo: etaTo ?? DateTime.now().add(const Duration(days: 3)),
          behindSchedule: behindSchedule,
        ),
      ),
    );
  }

  OrderStore.instance.seedForTest([order]);
  return order;
}

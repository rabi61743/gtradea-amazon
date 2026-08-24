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
}) =>
    {
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
}) =>
    {
      'orderNo': 'GT-1001',
      'statusLabel': statusLabel,
      'orderStage': {'code': _stageCodes[reached], 'label': reached.label},
      'completionEta': {'to': etaTo?.toUtc().toIso8601String()},
      'etaEstimated': false,
      'etaBehindSchedule': behindSchedule,
      'deliveredAt': deliveredAt?.toUtc().toIso8601String(),
      'shipments': [
        {
          'shipmentNo': shipmentNo,
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
}) {
  var order = Order.fromServer(ServerOrder.fromJson(orderJson(
    id: id,
    status: status,
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    placedAt: placedAt,
    lines: lines,
  )));

  if (withTracking) {
    order = order.withTracking(OrderTracking.fromJson(trackingJson(
      reached: reached,
      deliveredAt: reached == OrderStage.delivered ? DateTime.now() : null,
      etaTo: etaTo ?? DateTime.now().add(const Duration(days: 3)),
      behindSchedule: behindSchedule,
    )));
  }

  OrderStore.instance.seedForTest([order]);
  return order;
}

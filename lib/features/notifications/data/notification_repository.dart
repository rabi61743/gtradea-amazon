import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import 'notification_store.dart';

/// The shop's own notifications, at `/notifications`.
///
/// The routes the storefront already uses. This is the half that was missing:
/// everything a *server* raises -- a seller answering a quote, support replying
/// to a ticket -- is written to this table, and the app had no way to read it.
/// Its notification list was built entirely from what this device could work
/// out for itself, which is why those two events never appeared.
class NotificationRepository {
  NotificationRepository._();

  static final NotificationRepository instance = NotificationRepository._();

  Dio get _dio => ApiClient.http;

  /// The most recent notifications for the signed-in account.
  ///
  /// The server scopes them to the caller; there is no id in the path, so
  /// there is no way to ask for anybody else's.
  Future<List<AppNotification>> list({int limit = 50}) => guarded(() async {
    final res = await _dio.get('/notifications');
    return asRows(res.data, key: 'notifications')
        .map(notificationFromServer)
        .whereType<AppNotification>()
        .take(limit)
        .toList(growable: false);
  });

  Future<void> markRead(String id) => guarded(() async {
    await _dio.patch('/notifications/${Uri.encodeComponent(id)}/read');
  });

  Future<void> markAllRead() => guarded(() async {
    await _dio.post('/notifications/mark-all-read');
  });

  Future<void> remove(String id) => guarded(() async {
    await _dio.delete('/notifications/${Uri.encodeComponent(id)}');
  });
}

/// Reads one server row into the notification this app already models.
///
/// Deliberately tolerant. The row's shape is the server's, and the pieces this
/// app needs -- what it is about, and which thing it points at -- are spelled
/// differently by different producers. Reading several spellings costs
/// nothing; guessing one and getting it wrong costs the notification.
AppNotification? notificationFromServer(Map<String, dynamic> json) {
  final id = asString(json['id']);
  if (id == null || id.isEmpty) return null;

  final title = asString(json['title']) ?? '';
  final body =
      asString(json['message']) ??
      asString(json['body']) ??
      asString(json['description']) ??
      '';
  if (title.isEmpty && body.isEmpty) return null;

  final type =
      (asString(json['type']) ?? asString(json['notification_type']) ?? '')
          .toLowerCase();
  final data = asMap(json['data']);

  return AppNotification(
    id: id,
    category: categoryForServerType(type),
    title: title.isEmpty ? body : title,
    body: title.isEmpty ? '' : body,
    createdAt: asDate(json['created_at']) ?? DateTime.now(),
    read: asBool(json['is_read']) || asBool(json['read']),
    // Orders already had a home on this model, so an order notification keeps
    // opening the order screen exactly as it did.
    orderId: asString(json['order_id']) ?? asString(data['order_id']),
    targetId: _targetId(json, data),
    fromServer: true,
  );
}

/// What the notification points at, whatever the producer called it.
String? _targetId(Map<String, dynamic> json, Map<String, dynamic> data) {
  for (final key in const [
    'reference_id',
    'entity_id',
    'resource_id',
    'request_id',
    'product_request_id',
    'quote_id',
    'ticket_id',
    'support_ticket_id',
  ]) {
    final value = asString(json[key]) ?? asString(data[key]);
    if (value != null && value.isNotEmpty) return value;
  }
  // A bare id inside the payload, which is what a producer that names nothing
  // else tends to send.
  final inner = asString(data['id']);
  return (inner == null || inner.isEmpty) ? null : inner;
}

/// Which of this app's categories a server type belongs to.
///
/// Matched on substrings rather than an exact list: the server's vocabulary is
/// its own and gains entries without asking, and a `quote_price_updated` that
/// fell through to "account" would be filed under a switch the shopper may
/// have turned off.
NotificationCategory categoryForServerType(String type) {
  bool has(String word) => type.contains(word);

  if (has('quote') || has('product_request') || has('request')) {
    return NotificationCategory.quote;
  }
  if (has('support') || has('ticket')) return NotificationCategory.support;
  if (has('refund')) return NotificationCategory.orderReturned;
  if (has('deliver')) return NotificationCategory.orderDelivered;
  if (has('ship')) return NotificationCategory.orderShipped;
  if (has('cancel')) return NotificationCategory.orderCancelled;
  if (has('order')) return NotificationCategory.orderPlaced;
  if (has('payment') || has('paid')) return NotificationCategory.payment;
  if (has('promo') || has('offer') || has('deal')) {
    return NotificationCategory.promotion;
  }
  return NotificationCategory.account;
}

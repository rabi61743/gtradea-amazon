import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// Quote requests against `/product-requests`.
///
/// The endpoint this app should have been using all along: the sibling
/// storefront has posted to it since it shipped, and it was measured live
/// answering 401 unauthenticated and 400 on an empty body -- a real, validating
/// endpoint rather than the 404 everything else in this area returns.
///
/// It replaces routing quote requests through the support ticket queue. A quote
/// is not a support ticket: it is a question to the seller about a specific
/// listing, and the server keeps them apart.
/// Where a quote request has got to.
///
/// The server's own five values. The labels are the ones the storefront
/// prints, so a shopper who asked on the website and checks in the app is told
/// the same thing about the same request.
enum QuoteStatus {
  pending('pending', 'Received'),
  reviewing('reviewing', 'Under review'),
  quoted('quoted', 'Quote ready'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Declined'),
  other('', '');

  const QuoteStatus(this.code, this.label);

  final String code;
  final String label;

  /// The status for a server value, or [other] carrying it verbatim.
  ///
  /// An unrecognised status is shown as the server wrote it rather than hidden:
  /// a queue that gains a sixth state should not make requests look stateless.
  static QuoteStatus of(String raw) {
    final value = raw.trim().toLowerCase();
    for (final status in values) {
      if (status.code == value && status.code.isNotEmpty) return status;
    }
    return other;
  }

  /// Whether the seller has answered with a price.
  bool get isAnswered => this == quoted || this == approved;

  bool get isDeclined => this == rejected;
}

/// One request to price a listing.
class QuoteRequest {
  const QuoteRequest({
    required this.id,
    required this.title,
    required this.status,
    this.statusRaw = '',
    this.imageUrl,
    this.askedPrice,
    this.quotedPrice,
    this.quantity,
    this.lastMessage,
    this.seller,
    this.createdAt,
    this.lastMessageAt,
  });

  final String id;
  final String title;
  final QuoteStatus status;

  /// What the server called it, kept for a status this app does not know.
  final String statusRaw;

  final String? imageUrl;

  /// The listing's own price when the request was raised, as text -- the
  /// server stores it as written rather than as a number.
  final String? askedPrice;

  /// What the seller came back with, once they have.
  final num? quotedPrice;

  final int? quantity;

  /// The most recent thing said on the thread, when there is one.
  final String? lastMessage;

  final String? seller;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;

  /// What to show as the label, falling back to the server's own word.
  String get statusLabel =>
      status == QuoteStatus.other ? _titleCase(statusRaw) : status.label;

  /// The date this request last did anything.
  DateTime? get updatedAt => lastMessageAt ?? createdAt;

  static String _titleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Requested';
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  factory QuoteRequest.fromJson(Map<String, dynamic> json) {
    final raw = asString(json['status']) ?? '';
    return QuoteRequest(
      id: asString(json['id']) ?? '',
      title: asString(json['product_title']) ?? '',
      status: QuoteStatus.of(raw),
      statusRaw: raw,
      imageUrl: asString(json['product_image_url']),
      askedPrice: asString(json['product_price']),
      quotedPrice: asNum(json['quoted_price']),
      quantity: asInt(json['quantity']),
      lastMessage: asString(json['last_message']),
      seller:
          asString(json['seller_name']) ??
          asString(asMap(json['seller'])['name']),
      createdAt: asDate(json['created_at']),
      lastMessageAt: asDate(json['last_message_at']),
    );
  }
}

class QuoteRepository {
  QuoteRepository._();

  static final QuoteRepository instance = QuoteRepository._();

  Dio get _dio => ApiClient.http;

  /// Every quote this account has asked for, newest first.
  ///
  /// The server scopes the list to the caller's own session -- there is no id
  /// in the path to ask about somebody else's -- so a shopper cannot reach
  /// another's requests by any route this app has.
  Future<List<QuoteRequest>> listMine() => guarded(() async {
    final res = await _dio.get('/product-requests');
    final requests = asRows(res.data, key: 'requests')
        .map(QuoteRequest.fromJson)
        .where((request) => request.id.isNotEmpty)
        .toList();
    requests.sort((a, b) {
      final left = a.updatedAt;
      final right = b.updatedAt;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    return List.unmodifiable(requests);
  });

  /// One request, by its own id.
  Future<QuoteRequest> byId(String id) => guarded(() async {
    final res = await _dio.get('/product-requests/${Uri.encodeComponent(id)}');
    return QuoteRequest.fromJson(asMap(res.data));
  });

  /// Posts a message onto a request, with any files already uploaded.
  ///
  /// [attachments] are storage keys from
  /// [SupportAttachmentRepository.upload]. This is where a product query's
  /// files live: the request record itself takes none, and the storefront
  /// sends them exactly this way -- its quote thread uploads to the same
  /// bucket and renders `message.attachments` off these rows, which is what
  /// puts a shopper's photograph in front of whoever prices the request.
  ///
  /// The body is never empty, because a message row with no text and no words
  /// of its own reads as a blank in the thread. The storefront writes
  /// "(attachment)"; this says the same in the shop's own voice.
  Future<void> sendMessage(
    String requestId,
    String message, {
    List<String> attachments = const [],
  }) => guarded(() async {
    await _dio.post(
      '/product-requests/${Uri.encodeComponent(requestId)}/messages',
      data: {
        'message': message.isEmpty ? '(attachment)' : message,
        if (attachments.isNotEmpty) 'attachments': attachments,
      },
    );
  });

  /// Asks the seller to price [title], and returns the request's id.
  ///
  /// Every field but the message identifies the listing, because the request
  /// lands in a queue where "a shirt" is not enough to act on.
  Future<String> submit({
    required String sourceId,
    required String title,
    String? imageUrl,
    String? price,
    String? message,
  }) => guarded(() async {
    final res = await _dio.post(
      '/product-requests',
      data: {
        'product_source_id': sourceId,
        'product_title': title,
        if (imageUrl != null && imageUrl.isNotEmpty)
          'product_image_url': imageUrl,
        if (price != null && price.isNotEmpty) 'product_price': price,
        if (message != null && message.isNotEmpty) 'message': message,
      },
    );
    return asString(asMap(res.data)['id']) ?? '';
  });
}

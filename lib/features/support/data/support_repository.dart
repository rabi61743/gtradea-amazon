import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// Support conversations, against `/support/tickets`.
///
/// Ported from the sibling app, which already talks to this endpoint, so the
/// two storefronts read the same threads rather than each inventing a shape for
/// them. The endpoint was probed before any of this was written: it answers
/// **401** rather than 404, which is what confirmed there was something real
/// behind the chat icon to open.
///
/// Attachments travel on **messages**, not on the ticket record: that is where
/// the server keeps them and, more to the point, the only place support staff
/// see them -- the admin ticket console renders `message.attachments` and has
/// no ticket-level attachment view at all. See [SupportAttachmentRepository]
/// for the upload itself.

/// Statuses where the customer can still reply.
const _openStatuses = <String>{'open', 'in_progress', 'waiting_customer'};

/// What a status means to the person who opened the ticket.
///
/// The raw enum is written from support's side and is ambiguous about who is
/// being waited on -- `waiting_customer` reads to a shopper as though *they*
/// are waiting, when it means the opposite.
String customerTicketStatusLabel(String status) => switch (status) {
  'open' => 'Open',
  'in_progress' => 'In progress',
  'waiting_customer' => 'Awaiting your reply',
  'resolved' => 'Resolved',
  'closed' => 'Closed',
  _ => status.replaceAll('_', ' '),
};

/// The categories the storefront's contact form offers, value to label.
const supportTicketCategories = <String, String>{
  'order': 'Order issues',
  'payment': 'Payment & billing',
  'shipping': 'Shipping & delivery',
  'returns': 'Returns & refunds',
  'product': 'Product questions',
  'account': 'Account & login',
  'technical': 'Technical issues',
  'general': 'General inquiry',
};

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    this.description = '',
    this.status = 'open',
    this.category = 'general',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ticketNumber;
  final String subject;
  final String description;
  final String status;
  final String category;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOpen => _openStatuses.contains(status);
  String get statusLabel => customerTicketStatusLabel(status);

  /// What the category is called, or the raw value if support has added one
  /// this app has not heard of yet.
  String get categoryLabel => supportTicketCategories[category] ?? category;

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
    id: asString(json['id']) ?? '',
    ticketNumber: asString(json['ticket_number']) ?? '',
    subject: asString(json['subject']) ?? '',
    description: asString(json['description']) ?? '',
    status: asString(json['status']) ?? 'open',
    category: asString(json['category']) ?? 'general',
    createdAt: asDate(json['created_at']),
    updatedAt: asDate(json['updated_at']),
  );
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.senderType,
    required this.message,
    this.createdAt,
    this.attachments = const [],
    this.replyToId,
  });

  final String id;

  /// `user` or `support`. Anything else is treated as support, because a
  /// message of unknown origin shown on the shopper's own side would be a lie
  /// about who said it.
  final String senderType;

  final String message;
  final DateTime? createdAt;

  /// Storage keys in the `support-attachments` bucket, in the order they were
  /// sent. Keys rather than URLs: the bucket is private, so reading one back
  /// goes through the media endpoint with the caller's own credentials.
  final List<String> attachments;

  /// The message this one answers, when it answers one.
  ///
  /// Read under several names because the field is new to this endpoint and
  /// the server's own spelling is not published: whichever of these it uses,
  /// the thread finds it. Null when the message is not a reply.
  final String? replyToId;

  bool get isMine => senderType == 'user';

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    id: asString(json['id']) ?? '',
    senderType: asString(json['sender_type']) ?? 'support',
    message: asString(json['message']) ?? '',
    createdAt: asDate(json['created_at']),
    attachments: [
      for (final row in (json['attachments'] as List? ?? const []))
        ?asString(row),
    ],
    replyToId:
        asString(json['reply_to_message_id']) ??
        asString(json['reply_to']) ??
        asString(json['parent_message_id']) ??
        asString(json['in_reply_to']),
  );
}

class SupportRepository {
  SupportRepository._();

  static final SupportRepository instance = SupportRepository._();

  Dio get _dio => ApiClient.http;

  /// Every conversation this account has opened, newest first.
  Future<List<SupportTicket>> listMine() => guarded(() async {
    final res = await _dio.get('/support/tickets');
    return asRows(res.data, key: 'tickets')
        .map(SupportTicket.fromJson)
        .where((ticket) => ticket.id.isNotEmpty)
        .toList(growable: false);
  });

  /// One conversation's current state.
  ///
  /// Worth re-reading rather than trusting the row the list passed along:
  /// support can close a ticket while it is open on screen, and a stale
  /// "Awaiting your reply" invites a message nobody will answer.
  Future<SupportTicket> byId(String id) => guarded(() async {
    final res = await _dio.get('/support/tickets/$id');
    return SupportTicket.fromJson(asMap(res.data));
  });

  Future<List<SupportMessage>> messages(String ticketId) => guarded(() async {
    final res = await _dio.get('/support/tickets/$ticketId/messages');
    return asRows(res.data, key: 'messages')
        .map(SupportMessage.fromJson)
        .where((message) => message.id.isNotEmpty)
        .toList(growable: false);
  });

  /// Posts a reply, with any files already uploaded to the support bucket.
  ///
  /// [attachments] are storage keys from [SupportAttachmentRepository.upload],
  /// which is the shape the storefront sends and the admin console reads.
  Future<void> send(
    String ticketId,
    String message, {
    List<String> attachments = const [],
    String? replyToId,
  }) => guarded(() async {
    await _dio.post(
      '/support/tickets/$ticketId/messages',
      data: {
        'message': message,
        if (attachments.isNotEmpty) 'attachments': attachments,
        // Sent under the name the rest of this API uses for a foreign key.
        // Whether the server keeps it is its own business -- the thread reads
        // the reference back off the server rather than remembering it here,
        // so a field that is dropped shows up as a reply that arrives without
        // its quote rather than as one that lies about being stored.
        'reply_to_message_id': ?replyToId,
      },
    );
  });

  /// Opens a conversation.
  ///
  /// The email is required by the server even for a signed-in account, so the
  /// sheet fills it from the session rather than asking for something it
  /// already knows.
  Future<SupportTicket> create({
    required String email,
    required String subject,
    required String description,
    String category = 'general',
    String? name,
  }) => guarded(() async {
    final res = await _dio.post(
      '/support/tickets',
      data: {
        'email': email,
        'subject': subject,
        'description': description,
        'category': category,
        if (name != null && name.isNotEmpty) 'name': name,
      },
    );
    return SupportTicket.fromJson(asMap(res.data));
  });
}

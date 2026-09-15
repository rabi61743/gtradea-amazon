import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_store.dart';
import '../../quotes/data/quote_repository.dart';

/// The words every request-to-stock opens with.
///
/// They are how the shop's team tells one apart in the Product requests queue
/// they already work from: the same queue, the same replies, the same
/// notifications back to the customer -- this is a request for the product to
/// be stocked, not for a price.
const restockMarker = 'Request to stock';

/// Requests-to-stock, as this account has made them.
///
/// There is no separate restock system on the server, and this is not one.
/// A request is a product request on `/product-requests` -- the endpoint the
/// quote sheet and the storefront already post to -- so it is stored against
/// the customer by their session, lands in the shop's existing admin queue,
/// and is answered through the existing notifications. The server only ever
/// lists the caller's own requests, so no other customer's are reachable here.
///
/// The server neither types these nor refuses a second request for the same
/// product. So the duplicate check happens here, against this account's own
/// list read fresh from the server immediately before sending.
class RestockRequests extends ChangeNotifier {
  RestockRequests._() {
    _owner = AuthStore.instance.account?.id;
    AuthStore.instance.addListener(_onAuthChanged);
  }

  static final instance = RestockRequests._();

  /// The account these requests belong to. Another account's are dropped the
  /// moment it changes, never shown under the next one.
  String? _owner;

  /// This account's requests as the server last listed them; null until read.
  List<QuoteRequest>? _mine;
  Future<List<QuoteRequest>>? _listing;

  /// Why the last read failed, when it did.
  ApiError? _listError;

  /// Products a request is being sent for right now. A second tap while one
  /// is in flight does nothing, so one tap is one request.
  final Set<String> _sending = {};

  bool get isListed => _mine != null;
  ApiError? get listError => _listError;
  bool isSending(String productId) => _sending.contains(productId);

  void _onAuthChanged() {
    final id = AuthStore.instance.account?.id;
    if (id == _owner) return;
    _owner = id;
    _mine = null;
    _listing = null;
    _listError = null;
    _sending.clear();
    notifyListeners();
  }

  /// The request this account already has open for a product, if any.
  ///
  /// Matched on the product's id where the server returns it, and on its title
  /// where it does not. A declined or completed request is not open: the
  /// customer may ask again.
  QuoteRequest? existingFor({required String productId, required String title}) {
    final mine = _mine;
    if (mine == null) return null;
    for (final request in mine) {
      if (!_isOpen(request)) continue;
      final sameProduct = request.sourceId != null
          ? request.sourceId == productId
          : request.title.trim() == title.trim();
      if (sameProduct) return request;
    }
    return null;
  }

  static bool _isOpen(QuoteRequest request) =>
      !request.status.isDeclined && request.status != QuoteStatus.approved;

  /// Reads this account's requests from the server.
  Future<void> refresh() async {
    if (!AuthStore.instance.isSignedIn) return;
    final owner = _owner;
    final listing = _listing ??= QuoteRepository.instance.listMine();
    try {
      final rows = await listing;
      if (owner != _owner) return;
      _mine = rows;
      _listError = null;
    } on ApiError catch (e) {
      if (owner != _owner) return;
      _listError = e;
      rethrow;
    } finally {
      if (identical(_listing, listing)) _listing = null;
      notifyListeners();
    }
  }

  /// Tells the shop's team this account wants [title], and returns the request
  /// that now stands for it.
  ///
  /// Returns the existing request instead of raising a second one when this
  /// account already has one open. Returns null when a request for this
  /// product is already being sent. Throws [ApiError] when the server could
  /// not be reached or refused it; nothing is claimed as sent until it was.
  Future<QuoteRequest?> request({
    required String productId,
    required String title,
    String? imageUrl,
    String? price,
    String? variantLabel,
  }) async {
    if (!_sending.add(productId)) return null;
    notifyListeners();
    final owner = _owner;
    try {
      await refresh();
      final existing = existingFor(productId: productId, title: title);
      if (existing != null) return existing;

      final id = await QuoteRepository.instance.submit(
        sourceId: productId,
        title: title,
        imageUrl: imageUrl,
        price: price,
        message: [
          '$restockMarker: I would like to buy this, but it is currently '
              'unavailable. Please let me know when it can be ordered.',
          if (variantLabel != null && variantLabel.isNotEmpty)
            'Option: $variantLabel',
        ].join('\n'),
      );
      if (owner != _owner) return null;

      // Read back rather than assumed, so the state on screen is the
      // server's. Kept even if the read fails: the request was accepted.
      final sent = QuoteRequest(
        id: id,
        title: title,
        status: QuoteStatus.pending,
        statusRaw: QuoteStatus.pending.code,
        imageUrl: imageUrl,
        sourceId: productId,
        createdAt: DateTime.now(),
      );
      try {
        await refresh();
      } on ApiError {
        // The list is refreshed next time; the request stands.
      }
      final listed = existingFor(productId: productId, title: title);
      if (listed != null) return listed;
      _mine = [sent, ...?_mine];
      return sent;
    } finally {
      _sending.remove(productId);
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTest() {
    _owner = AuthStore.instance.account?.id;
    _mine = null;
    _listing = null;
    _listError = null;
    _sending.clear();
  }
}

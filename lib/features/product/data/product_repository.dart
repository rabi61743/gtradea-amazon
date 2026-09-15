import 'package:dio/dio.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';

/// Product detail, and the record of having looked at one.
///
/// Detail does not live behind the `/api/v1` gateway prefix like everything
/// else -- it is served by a separate sourcing service at `<base>/api/1688`.
/// Hence the absolute URLs: they override the shared client's base rather than
/// needing a second client.
class ProductRepository {
  ProductRepository._();

  static final ProductRepository instance = ProductRepository._();

  Dio get _dio => ApiClient.http;

  /// Records answered recently, keyed by the id they were asked for.
  ///
  /// Short-lived on purpose: it exists so that going back to a product just
  /// looked at is instant, not so the app can serve yesterday's price. Keyed
  /// by `num_iid` and never consulted for any other id, so a cache hit is
  /// always the record that was asked for.
  final Map<String, _CachedDetail> _cache = {};

  /// Requests in flight, keyed the same way.
  ///
  /// Two callers asking for the same product at the same moment -- the page
  /// and a prefetch, say -- share one request rather than making two.
  final Map<String, Future<Map<String, dynamic>>> _inflight = {};

  /// How long a record stays worth reusing.
  static const cacheTtl = Duration(minutes: 5);

  /// The clock, so a test can age the cache without waiting.
  DateTime Function() now = DateTime.now;

  /// The full record for one catalogue offer.
  ///
  /// Returns the raw `{item, pricing}` envelope; the view model does the
  /// shaping, so a field the server adds later needs no change here.
  Future<Map<String, dynamic>> detail(String numIid) {
    final cached = _cache[numIid];
    if (cached != null && now().difference(cached.at) < cacheTtl) {
      return Future.value(cached.body);
    }
    // Never two requests for one product. The future is shared, so a second
    // caller waits on the first rather than starting another.
    return _inflight[numIid] ??= _fetchDetail(numIid).whenComplete(() {
      _inflight.remove(numIid);
    });
  }

  /// Warms the cache for a product that is about to be opened.
  ///
  /// Deliberately swallows everything: a prefetch that failed must never be
  /// visible, and the page's own fetch will report the failure properly when
  /// it happens for real.
  Future<void> prefetchDetail(String numIid) async {
    try {
      await detail(numIid);
    } on ApiError {
      // See above.
    }
  }

  /// Drops what is remembered. For tests, and for a shopper signing out.
  void clearDetailCache() {
    _cache.clear();
    _inflight.clear();
  }

  Future<Map<String, dynamic>> _fetchDetail(String numIid) {
    return guarded(() async {
      final res = await _dio.get(
        '${Env.apiBaseUrl}/api/1688/product',
        queryParameters: {'num_iid': numIid},
        options: guestCall,
      );
      final body = asMap(res.data);

      // This service reports a missing product as HTTP 200 with success:false.
      // Left unchecked it would decode as an empty product and render a blank
      // page rather than "we could not find this".
      if (body['success'] == false) {
        throw ApiError.fromEnvelope(body, status: 404);
      }
      if (body['item'] is! Map) {
        throw const ApiError(
          statusCode: 404,
          message: 'This product is no longer available.',
        );
      }
      _cache[numIid] = _CachedDetail(body: body, at: now());
      return body;
    });
  }

  /// Records that the shopper looked at this.
  ///
  /// Best effort and deliberately unawaited by callers: it feeds the
  /// recently-viewed list, and a failure there must never affect opening a
  /// product. Needs a session, so it does nothing useful for a guest -- which
  /// is why the failure is swallowed rather than surfaced.
  Future<void> recordView({
    required String numIid,
    String? name,
    String? imageUrl,
    String? priceLabel,
  }) async {
    try {
      await _dio.post(
        '/product-views',
        data: {
          'source': '1688',
          'source_product_id': numIid,
          'product_data': {
            'name': ?name,
            'image_url': ?imageUrl,
            'price_label': ?priceLabel,
          },
        },
      );
    } catch (_) {
      // Signed out, offline, or the server said no. None of those are worth
      // interrupting a shopper over.
    }
  }
}

/// One remembered record, with when it arrived.
class _CachedDetail {
  const _CachedDetail({required this.body, required this.at});

  final Map<String, dynamic> body;
  final DateTime at;
}

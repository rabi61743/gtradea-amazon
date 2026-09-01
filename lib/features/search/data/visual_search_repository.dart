import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../catalog/data/product.dart';

/// One page of visual matches.
class VisualMatches {
  const VisualMatches({
    required this.products,
    required this.total,
    required this.page,
    required this.pageCount,
    this.fromCache = false,
  });

  final List<Product> products;

  /// How many the server found in total, which is usually far more than one
  /// page. Worth showing: "660 similar" reads very differently from twenty.
  final int total;

  final int page;
  final int pageCount;

  /// The server answered from its own cache. Not shown to the shopper; useful
  /// when a search that took three seconds yesterday comes back instantly.
  final bool fromCache;

  bool get hasMore => page < pageCount;
}

/// Finds products that look like a photograph.
///
/// This is a different service from the rest of the catalogue: it lives at
/// `/api/1688/image-search`, **not** under `/api/v1`, so every call here passes
/// an absolute URL to override the Dio base rather than a path. Getting that
/// wrong is a 404 that looks like a missing feature.
///
/// The contract, confirmed against production:
///
/// ```
/// POST /api/1688/image-search
/// {"image": "<base64>", "page": 1, "pageSize": 20}
///   -> {"products": [...], "totalResults": 660, "page": 1,
///       "pageCount": 33, "from_cache": false}
/// ```
///
/// It also accepts `imageUrl` instead of `image`, and answers
/// `400 {"error": "image (base64) or imageUrl required"}` when given neither.
class VisualSearchRepository {
  VisualSearchRepository._();

  static final VisualSearchRepository instance = VisualSearchRepository._();

  Dio get _dio => ApiClient.http;

  static String get endpoint => '${Env.apiBaseUrl}/api/1688/image-search';

  /// Matches for a photograph the catalogue already hosts.
  ///
  /// The service takes `imageUrl` in place of `image`, which is the right
  /// half of the contract to use for a picture that is already on the web:
  /// downloading a product photograph only to send it back up as base64 costs
  /// the shopper the bytes twice and the wait once, for a file the service can
  /// fetch itself.
  Future<VisualMatches> searchByUrl(
    String imageUrl, {
    int page = 1,
    int pageSize = 20,
  }) => _post({'imageUrl': imageUrl, 'page': page, 'pageSize': pageSize});

  /// The picture behind a catalogue address, for the history thumbnail.
  ///
  /// Only ever for the history: the search itself hands the service the URL
  /// and never needs the bytes. Null rather than throwing, because failing to
  /// keep a thumbnail must not cost the shopper results already on screen.
  Future<Uint8List?> pictureBytes(String imageUrl) async {
    try {
      final res = await _dio.get<List<int>>(
        imageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          extra: const {'skipAuth': true},
        ),
      );
      final bytes = res.data;
      return bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Matches for a base64-encoded photograph.
  Future<VisualMatches> search(
    String base64Image, {
    int page = 1,
    int pageSize = 20,
  }) {
    return _post({'image': base64Image, 'page': page, 'pageSize': pageSize});
  }

  Future<VisualMatches> _post(Map<String, Object?> body) {
    final page = asInt(body['page']) ?? 1;
    return guarded(() async {
      final res = await _dio.post(
        endpoint,
        data: body,
        options: Options(
          extra: const {'skipAuth': true},
          // Recognition is slow -- a real photograph measured around three
          // seconds against production, and a cold one can be slower. The
          // app-wide twenty seconds is too tight to rely on here.
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 45),
        ),
      );

      final result = asMap(res.data);

      // The service says so rather than failing, and a shopper told "no
      // matches" when they were actually throttled would simply try again and
      // be throttled harder.
      if (result['rate_limited'] == true) {
        throw const ApiError(
          statusCode: 429,
          message: 'Too many image searches just now. Give it a minute.',
        );
      }

      final rows = asRows(result['products']);
      return VisualMatches(
        products: rows
            .map(_product)
            .where((p) => p.numIid.isNotEmpty && p.title.isNotEmpty)
            .toList(growable: false),
        total: asInt(result['totalResults']) ?? rows.length,
        page: asInt(result['page']) ?? page,
        pageCount: asInt(result['pageCount']) ?? 1,
        fromCache: asBool(result['from_cache']),
      );
    });
  }

  /// A match row as a catalogue product.
  ///
  /// Nearly the feed's shape, with one difference worth handling rather than
  /// shrugging at: the minimum order arrives as `min_order_quantity` here and
  /// `min_order` everywhere else. Missing it would put a five-unit wholesale
  /// line in the cart as a single item.
  static Product _product(Map<String, dynamic> row) {
    final moq = asInt(row['min_order_quantity']) ?? asInt(row['min_order']);
    return Product.fromJson({...row, 'min_order': ?moq});
  }
}

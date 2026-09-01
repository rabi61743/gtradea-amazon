import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import 'help_content.dart';

/// The knowledge base behind the Help Center.
///
/// The same three endpoints the website reads, so an article published once is
/// published everywhere. Nothing here is compiled in: a shop with an empty
/// knowledge base gets empty lists, which the screen says out loud rather than
/// filling with invented topics.
class HelpRepository {
  HelpRepository._();

  static final HelpRepository instance = HelpRepository._();

  Dio get _dio => ApiClient.http;

  /// The published topics.
  ///
  /// Read without a credential: help is public, and requiring a session would
  /// hide it from the shopper most likely to need it.
  Future<List<HelpCategory>> categories() => guarded(() async {
    final res = await _dio.get('/help/categories', options: guestCall);
    return asRows(res.data, key: 'categories')
        .map(HelpCategory.fromJson)
        .where((category) => category.name.isNotEmpty)
        .toList(growable: false);
  });

  /// Articles, filtered the way the gateway filters them.
  ///
  /// Every parameter is optional and omitted when null, because the server
  /// treats an absent filter and an empty one differently -- `search=` matches
  /// nothing, where no `search` key at all matches everything.
  Future<List<HelpArticle>> articles({
    String? categorySlug,
    HelpAudience? audience,
    bool featured = false,
    String? search,
    int? limit,
  }) => guarded(() async {
    final res = await _dio.get(
      '/help/articles',
      options: guestCall,
      queryParameters: {
        'category_slug': ?categorySlug,
        'audience': ?audience?.query,
        if (featured) 'featured': 'true',
        'search': ?(search == null || search.trim().isEmpty
            ? null
            : search.trim()),
        'limit': ?limit,
      },
    );
    return asRows(res.data, key: 'articles')
        .map(HelpArticle.fromJson)
        .where((article) => article.title.isNotEmpty)
        .toList(growable: false);
  });

  /// The address the shop wants to be written to.
  ///
  /// A setting rather than a constant: the same key the website reads, so the
  /// two cannot end up printing different addresses. Null when unset, and the
  /// screen then offers no email button at all rather than a broken one.
  Future<String?> supportEmail() => _setting('support_email');

  /// The number the shop answers, or null when it publishes none.
  Future<String?> supportPhone() => _setting('support_phone');

  /// One free-text setting, or null when it is unset or blank.
  ///
  /// The endpoint answers either the setting row or the value directly, and an
  /// unseeded key comes back with a null value -- a normal state, not an error.
  Future<String?> _setting(String key) => guarded(() async {
    final res = await _dio.get('/site-settings/$key', options: guestCall);
    final body = asMap(res.data);
    final value = body.containsKey('setting_value')
        ? body['setting_value']
        : body;
    final text = asString(value)?.trim();
    return (text == null || text.isEmpty) ? null : text;
  });
}

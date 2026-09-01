import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// One of the shop's written pages: terms, privacy, returns.
class LegalPage {
  const LegalPage({
    required this.title,
    required this.body,
    this.slug = '',
    this.html = '',
  });

  final String title;

  /// The slug it was read from, so a list of pages can open one of them.
  final String slug;

  /// The page as plain text. The server stores it as HTML, which the checkout
  /// sheet does not render, so it is flattened once here rather than in each
  /// screen that shows it.
  final String body;

  /// The markup as the server stores it.
  ///
  /// Kept beside [body] rather than replacing it: a policy is written in
  /// headings and lists, and flattening it to one run of text loses the
  /// structure that makes it readable. [legalBlocks] turns this into something
  /// a long document can be read from, while [body] stays exactly what it was
  /// for the one-paragraph sheet at checkout.
  final String html;

  factory LegalPage.fromJson(Map<String, dynamic> json) {
    final content = asString(json['content']) ?? '';
    return LegalPage(
      title: asString(json['title']) ?? '',
      slug: asString(json['slug']) ?? '',
      body: stripHtml(content),
      html: content,
    );
  }
}

/// The shop's own written pages, at `GET /pages/{slug}`.
///
/// A real route, not a catch-all: `/pages/terms` returns
/// `{id, slug, title, content}` while `/pages/zzznonsense` returns 404. That
/// matters, because the site itself answers 200 to any path at all -- the
/// storefront is a single-page app -- so linking the checkout to
/// `gtradea.com/terms` would have been a link this app could never verify.
///
/// Checkout asks the shopper to agree to these. Showing them the shop's actual
/// current text, rather than a copy pasted into the app that drifts from it, is
/// the difference between consent and a formality.
class LegalPageRepository {
  LegalPageRepository._();

  static final LegalPageRepository instance = LegalPageRepository._();

  Dio get _dio => ApiClient.http;

  /// Read once per run: these change rarely and are the same for everybody.
  final _cache = <String, LegalPage>{};

  void resetForTest() => _cache.clear();

  Future<LegalPage> bySlug(String slug) => guarded(() async {
    final cached = _cache[slug];
    if (cached != null) return cached;

    final res = await _dio.get('/pages/$slug', options: guestCall);
    final page = LegalPage.fromJson(asMap(res.data));
    return _cache[slug] = page;
  });

  /// The buyer terms the checkbox at checkout refers to.
  Future<LegalPage> terms() => bySlug('terms');

  /// Every page the shop publishes, at `GET /pages`.
  ///
  /// The same route the website reads, so a policy edited once is edited
  /// everywhere. Which pages exist is the shop's decision -- there is no list
  /// of slugs compiled in here, because a shop that publishes a tenth policy
  /// should not need an app release to show it.
  Future<List<LegalPage>> list() => guarded(() async {
    final res = await _dio.get('/pages', options: guestCall);
    final pages = asRows(res.data, key: 'pages')
        .map(LegalPage.fromJson)
        .where((page) => page.title.isNotEmpty && page.slug.isNotEmpty)
        .toList(growable: false);
    // Reading one out of the list saves a second request for it.
    for (final page in pages) {
      _cache.putIfAbsent(page.slug, () => page);
    }
    return pages;
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_store.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/data/product.dart';
import 'interest_profile.dart';

/// One real source of products, paged by offset.
///
/// Every source is an existing catalogue endpoint -- a department by sales or
/// by newest, a keyword search, a department's trending list, the discover
/// feed. Nothing is invented here; this only decides which to ask next.
class _Source {
  _Source({required this.familiar, required this.fetch, this.pageSize = 12});

  /// True for a source drawn from the shopper's interests, false for the
  /// discovery mixed in beside them.
  final bool familiar;
  final Future<List<Product>> Function(int offset, int pageSize) fetch;
  final int pageSize;

  final List<Product> _buffer = [];
  int _offset = 0;
  bool _exhausted = false;
  Future<void>? _refilling;

  bool get isDone => _exhausted && _buffer.isEmpty;

  /// Fetches the next page into the buffer. One at a time per source.
  Future<void> refill() => _refilling ??= _doRefill().whenComplete(() {
    _refilling = null;
  });

  Future<void> _doRefill() async {
    if (_exhausted) return;
    try {
      final page = await fetch(_offset, pageSize);
      _offset += page.length;
      _buffer.addAll(page);
      if (page.length < pageSize) _exhausted = true;
    } on ApiError {
      // A source that fails is set aside for this feed; the others carry on.
      _exhausted = true;
    }
  }

  /// Up to [count] products that [accept] allows, fetching more if needed.
  Future<List<Product>> take(int count, bool Function(Product) accept) async {
    final out = <Product>[];
    while (out.length < count) {
      if (_buffer.isEmpty) {
        if (_exhausted) break;
        await refill();
        if (_buffer.isEmpty) break;
      }
      final product = _buffer.removeAt(0);
      if (accept(product)) out.add(product);
    }
    return out;
  }
}

/// The "New for You" feed: products picked from this shopper's real signals,
/// a page at a time.
///
/// Familiar and new are mixed: three picks from the shopper's interests --
/// popular and newest in the departments they buy and browse, and matches for
/// what they searched for and bought -- then one from the discover feed, so the
/// feed never closes into only what they already know. Nothing already in the
/// cart, saved or bought is offered, nothing is shown twice in one feed, and
/// products shown on recent visits are passed over so coming back is not the
/// same page again.
class ForYouFeed {
  ForYouFeed._(this.profile, this._sources, this._recentlyShown);

  final InterestProfile profile;
  final List<_Source> _sources;
  final Set<String> _recentlyShown;

  /// Every product this feed has shown, so none appears twice.
  final _shown = <String>{};

  int _turn = 0;

  bool get isExhausted => _sources.every((source) => source.isDone);

  /// Builds the sources for [profile] from the catalogue.
  static Future<ForYouFeed> build(
    InterestProfile profile, {
    Set<String> recentlyShown = const {},
    math.Random? random,
  }) async {
    final catalog = CatalogRepository.instance;
    final cids = await _cidsFor(profile.departments.take(3).toList());
    final sources = <_Source>[];

    // The departments this shopper buys and browses: popular there, and what
    // is newly listed there.
    for (final name in profile.departments.take(3)) {
      final cid = cids[name];
      if (cid != null) {
        sources
          ..add(
            _Source(
              familiar: true,
              fetch: (offset, size) => catalog.categoryProducts(
                cid,
                sort: ProductSort.sales,
                pageSize: size,
                offset: offset,
              ),
            ),
          )
          ..add(
            _Source(
              familiar: true,
              fetch: (offset, size) => catalog.categoryProducts(
                cid,
                sort: ProductSort.newest,
                pageSize: size,
                offset: offset,
              ),
            ),
          );
      } else {
        // A department name the storefront tree does not carry -- most of the
        // catalogue's own labels -- is searched for instead, still on the
        // shop's own index and still ordered by what sells and what is new.
        sources
          ..add(
            _Source(
              familiar: true,
              fetch: (offset, size) => catalog.search(
                query: name,
                sort: ProductSort.sales,
                pageSize: size,
                offset: offset,
              ),
            ),
          )
          ..add(
            _Source(
              familiar: true,
              fetch: (offset, size) => catalog.search(
                query: name,
                sort: ProductSort.newest,
                pageSize: size,
                offset: offset,
              ),
            ),
          );
      }
    }

    // What they searched for, and things like what they bought and carry.
    for (final phrase in profile.phrases.take(4)) {
      sources.add(
        _Source(
          familiar: true,
          fetch: (offset, size) =>
              catalog.search(query: phrase, pageSize: size, offset: offset),
        ),
      );
    }

    // Trending in their strongest department that the tree knows.
    final strongest = profile.departments
        .map((name) => cids[name])
        .whereType<String>()
        .firstOrNull;
    if (strongest != null) {
      sources.add(
        _Source(
          familiar: true,
          pageSize: 40,
          fetch: (offset, size) async => offset > 0
              ? const <Product>[]
              : catalog.trending(categoryCid: strongest, limit: size),
        ),
      );
    }

    // Discovery: the discover feed from a different point each time, so the
    // new half of the mix is new on every visit too.
    final start = (random ?? math.Random()).nextInt(3000);
    sources.add(
      _Source(
        familiar: false,
        pageSize: 20,
        fetch: (offset, size) =>
            catalog.discover(pageSize: size, offset: start + offset),
      ),
    );

    return ForYouFeed._(profile, sources, recentlyShown);
  }

  /// Storefront department ids for department names, where the tree has
  /// them. The same walk the cart's recommendations use.
  static Future<Map<String, String>> _cidsFor(List<String> names) async {
    if (names.isEmpty) return const {};
    try {
      await CatalogStore.instance.categories.load();
    } catch (_) {
      return const {};
    }
    final tree = CatalogStore.instance.categories.value ?? const <Category>[];
    final byName = <String, String>{};
    void walk(Category category) {
      byName.putIfAbsent(category.name.toLowerCase().trim(), () => category.cid);
      for (final child in category.children) {
        walk(child);
      }
    }

    for (final category in tree) {
      walk(category);
    }
    return {
      for (final name in names) name: ?byName[name.toLowerCase().trim()],
    };
  }

  bool _accept(Product product) {
    if (!product.hasPrice) return false;
    if (profile.known.contains(product.numIid)) return false;
    if (_recentlyShown.contains(product.numIid)) return false;
    return _shown.add(product.numIid);
  }

  /// The next [size] products.
  ///
  /// The first call asks several sources at once, so the first screen does
  /// not wait on them one after another. Returns fewer than [size] only when
  /// every source has run dry.
  Future<List<Product>> nextPage({int size = 20}) async {
    final familiar = _sources.where((s) => s.familiar).toList();
    final discovery = _sources.where((s) => !s.familiar).toList();

    if (_turn == 0) {
      await Future.wait([
        for (final source in [...familiar.take(4), ...discovery])
          source.refill(),
      ]);
    }

    final page = <Product>[];
    var idle = 0;
    while (page.length < size && idle < _sources.length * 2) {
      // Three from the shopper's interests, then one to discover.
      final wantDiscovery = _turn % 4 == 3 || familiar.every((s) => s.isDone);
      final pool = wantDiscovery && discovery.any((s) => !s.isDone)
          ? discovery
          : familiar;
      final live = pool.where((s) => !s.isDone).toList();
      _turn++;
      if (live.isEmpty) {
        idle++;
        if (isExhausted) break;
        continue;
      }
      final source = live[_turn % live.length];
      final picked = await source.take(
        math.min(3, size - page.length),
        _accept,
      );
      if (picked.isEmpty) {
        idle++;
      } else {
        idle = 0;
        page.addAll(picked);
      }
    }
    return page;
  }
}

/// What the feed has shown this account on recent visits, so the next visit
/// leads with something else. On this device, per account, and capped.
class ForYouHistory {
  ForYouHistory._();

  static const _cap = 400;

  static String _key(String? accountId) =>
      'gtradea_for_you_shown_${accountId ?? 'guest'}';

  static Future<Set<String>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(AuthStore.instance.account?.id));
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.whereType<String>().toSet() : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> remember(Iterable<String> ids) async {
    try {
      final key = _key(AuthStore.instance.account?.id);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      final existing = raw == null
          ? <String>[]
          : (jsonDecode(raw) as List).whereType<String>().toList();
      final merged = [...existing.where((id) => !ids.contains(id)), ...ids];
      final kept = merged.length > _cap
          ? merged.sublist(merged.length - _cap)
          : merged;
      await prefs.setString(key, jsonEncode(kept));
    } catch (_) {
      // Best effort: forgetting what was shown costs variety, nothing else.
    }
  }
}

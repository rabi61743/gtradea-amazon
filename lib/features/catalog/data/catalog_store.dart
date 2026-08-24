import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/async/loadable.dart';
import 'catalog_repository.dart';
import 'product.dart';

/// The catalogue reads the whole app shares.
///
/// One instance of each, so opening browse after the home page does not fetch
/// the department tree a second time, and so the tree is on screen instantly
/// when it does. Everything here is public data, which is why it is cached to
/// disk without regard to who is signed in.
class CatalogStore {
  CatalogStore._();

  static final CatalogStore instance = CatalogStore._();

  /// Every department and its children. Changes rarely, so it is cached and
  /// shown immediately while a fresh copy loads behind it.
  final categories = Loadable<List<Category>>(
    CatalogRepository.instance.categoryTree,
    cacheKey: 'categories',
    encode: encodeCategories,
    decode: decodeCategories,
  );

  /// The main feed on the home page.
  final discover = Loadable<List<Product>>(
    () => CatalogRepository.instance.discover(pageSize: 24),
    cacheKey: 'discover',
    encode: encodeProducts,
    decode: decodeProducts,
  );

  final banners = Loadable<List<HeroBanner>>(
    CatalogRepository.instance.heroBanners,
  );

  final _rails = <String, Loadable<List<Product>>>{};

  /// Best sellers in one department, loaded once per department per session.
  ///
  /// Kept rather than rebuilt so scrolling the home page up and down does not
  /// refetch every rail it passes.
  Loadable<List<Product>> rail(String categoryCid) {
    return _rails.putIfAbsent(
      categoryCid,
      () => Loadable<List<Product>>(
        () => CatalogRepository.instance
            .trending(categoryCid: categoryCid, limit: 12),
        cacheKey: 'rail_$categoryCid',
        encode: encodeProducts,
        decode: decodeProducts,
      ),
    );
  }

  @visibleForTesting
  void resetForTest() {
    categories.invalidate();
    discover.invalidate();
    banners.invalidate();
    for (final rail in _rails.values) {
      rail.invalidate();
    }
    _rails.clear();
  }

  /// A pull-to-refresh on the home page: everything already on screen, asked
  /// again. Rails that were never opened are left alone.
  Future<void> refreshHome() async {
    await Future.wait([
      banners.refresh(),
      discover.refresh(),
      categories.refresh(),
      ..._rails.values.map((rail) => rail.refresh()),
    ]);
  }
}

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/async/loadable.dart';
import '../../flash_sale/data/flash_sale.dart';
import '../../flash_sale/data/flash_sale_repository.dart';
import '../../search/data/trending_searches.dart';
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

  /// The shop's brand names, for the filter sheet's switched-off brand control.
  ///
  /// Cached like the tree: twenty-five names that change about never. Failure
  /// is not worth reporting -- the control they label does nothing either way.
  final brands = Loadable<List<String>>(
    CatalogRepository.instance.brands,
    cacheKey: 'brands',
    encode: (names) => names,
    decode: (raw) =>
        (raw as List).map((e) => e.toString()).toList(growable: false),
  );

  /// The main feed on the home page.
  final discover = Loadable<List<Product>>(
    () => CatalogRepository.instance.discover(pageSize: 24),
    cacheKey: 'discover',
    encode: encodeProducts,
    decode: decodeProducts,
  );

  /// A changing handful of products from across the whole catalogue.
  ///
  /// **Not cached to disk**, unlike [discover], and that is the whole point: a
  /// cached copy would hand every cold open the same "random" set, which is the
  /// one thing this section must not do. The cost is that it has nothing to
  /// show on an offline open -- correct here, because there is no such thing as
  /// a stale-but-still-true random pick.
  final randomPicks = Loadable<List<Product>>(
    () => CatalogRepository.instance.randomPicks(limit: 20),
  );

  final banners = Loadable<List<HeroBanner>>(
    CatalogRepository.instance.heroBanners,
  );

  /// What other shoppers are searching for.
  ///
  /// Not cached to disk. The point of the list is that it is current, and a
  /// week-old copy of "what is trending" is a contradiction -- better to show
  /// nothing on a cold, offline open than yesterday's answer stated as today's.
  final trendingSearches = Loadable<List<TrendingQuery>>(
    TrendingSearchRepository.instance.list,
  );

  /// The flash sale on now, or null when there is not one.
  ///
  /// Not cached to disk, unlike the rest of this store: a sale is defined by
  /// its deadline, and a cached one painted from yesterday's copy would count
  /// down to a time that has already passed before the network could correct
  /// it.
  final flashSale = Loadable<FlashSale?>(FlashSaleRepository.instance.current);

  final _rails = <String, Loadable<List<Product>>>{};

  /// Best sellers in one department, loaded once per department per session.
  ///
  /// Kept rather than rebuilt so scrolling the home page up and down does not
  /// refetch every rail it passes.
  Loadable<List<Product>> rail(String categoryCid) {
    return _rails.putIfAbsent(
      categoryCid,
      () => Loadable<List<Product>>(
        () => CatalogRepository.instance.trending(
          categoryCid: categoryCid,
          limit: 12,
        ),
        cacheKey: 'rail_$categoryCid',
        encode: encodeProducts,
        decode: decodeProducts,
      ),
    );
  }

  @visibleForTesting
  void resetForTest() {
    categories.invalidate();
    brands.invalidate();
    discover.invalidate();
    randomPicks.invalidate();
    banners.invalidate();
    flashSale.invalidate();
    trendingSearches.invalidate();
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
      // Refetched with the rest, so a pull-to-refresh deals a new hand rather
      // than redrawing the same one.
      randomPicks.refresh(),
      categories.refresh(),
      // Refetched with the rest, which is what makes pull-to-refresh the way
      // out of an ended sale: the next window arrives with it.
      flashSale.refresh(),
      ..._rails.values.map((rail) => rail.refresh()),
    ]);
  }
}

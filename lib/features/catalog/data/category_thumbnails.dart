import 'catalog_repository.dart';

/// A picture for a category the catalogue has none for.
///
/// Artwork on `/alibaba-categories` runs out at the third level, and unevenly:
/// Hanfu carries it on four of five children, while every one of Antenna's six,
/// Audio Devices' five, Capacitor's twelve and Diode's eleven comes back with a
/// null `image_url`.
///
/// The obvious substitute -- a product already filed under that category -- is
/// not available either. Asked directly, **two of those thirty-four have a
/// single product between them**; the rest are empty. So there is nothing to
/// borrow from the category itself.
///
/// What does exist is the keyword search over the live 1688 catalogue, which
/// ranks properly: "Zener Diode" returns a Zener diode, "ceramic capacitor" a
/// ceramic capacitor, "TV antenna" a TV antenna. This asks it for the
/// category's own name and keeps the first photograph.
///
/// **What that picture is, said plainly:** a real product from the live
/// catalogue whose listing matches the category's name. It is not a curated
/// category image and not a stock photo, and it is not claimed to be either --
/// it is a thumbnail standing for a category, which is what a category tile is.
/// The honest alternative was a coloured panel, and the right fix is still for
/// the backoffice to set `image_url` on these rows, at which point none of this
/// runs.
class CategoryThumbnails {
  CategoryThumbnails._();

  static final CategoryThumbnails instance = CategoryThumbnails._();

  /// Resolved answers, including the misses.
  ///
  /// A null value means "asked, and there was nothing" -- kept so a category
  /// the search cannot match is not asked about again every time its tile is
  /// rebuilt, which on a scrolling grid is constantly.
  final _found = <String, String?>{};

  /// Requests in flight, so two tiles for the same category -- or one tile
  /// rebuilt mid-flight -- share a single request rather than racing.
  final _pending = <String, Future<String?>>{};

  /// A photograph for [category], or null when nothing matched.
  ///
  /// Returns immediately for a category that already has its own artwork: the
  /// point is to fill gaps, never to override what the catalogue provides.
  Future<String?> forCategory(Category category) {
    final own = category.imageUrl;
    if (own != null && own.isNotEmpty) return Future.value(own);

    final cid = category.cid;
    if (_found.containsKey(cid)) return Future.value(_found[cid]);

    final inFlight = _pending[cid];
    if (inFlight != null) return inFlight;

    final request = _search(category).then((url) {
      _found[cid] = url;
      _pending.remove(cid);
      return url;
    });
    _pending[cid] = request;
    return request;
  }

  Future<String?> _search(Category category) async {
    final name = category.name.trim();
    if (name.isEmpty) return null;

    try {
      // A plain query with no filters, which routes to the keyword endpoint --
      // the one that ranks by relevance. The filtered endpoint would not.
      final products = await CatalogRepository.instance.search(query: name);
      for (final product in products) {
        final url = product.imageUrl;
        if (url != null && url.isNotEmpty) return url;
      }
    } on Object {
      // A thumbnail is decoration. A category that cannot get one still lists
      // its name, its subcategories and its products, so a failure here is
      // remembered as "nothing" rather than shown as an error.
      return null;
    }
    return null;
  }

  /// Forgets everything, for tests.
  void resetForTest() {
    _found.clear();
    _pending.clear();
  }
}

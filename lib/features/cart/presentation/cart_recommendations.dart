import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../shared/widgets/loadable_view.dart' show LoadFailed;
import '../../../shared/widgets/page_width.dart';
import '../../../shared/widgets/section_header.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/data/product.dart';
import '../../home/widgets/product_grid.dart';
import '../../search/widgets/product_result_card.dart'
    show ResultGridSkeleton, ResultGridSpec;
import '../data/cart_store.dart';
import 'quick_add_to_cart.dart';

/// What to look at next, under the total.
///
/// The shelf reads the cart it sits under: the departments the basket is
/// already buying from decide what is offered, and a cart with nothing in it
/// falls back to the shop's own feed -- the same one the home page calls
/// "Recommended for you". Nothing here is a list this app made up; every
/// product comes back from the catalogue with its own price, picture and
/// badges, drawn by the same card the search results and the home rails use.
///
/// It asks for nothing. A shopper who came to check a total scrolls past it,
/// and when the shop has nothing to suggest -- or the request fails -- the
/// section draws no heading over an empty strip and simply is not there.
class CartRecommendations extends StatefulWidget {
  const CartRecommendations({super.key});

  /// Enough to be worth swiping, few enough that this stays a footer under a
  /// cart rather than a second storefront below it.
  static const shown = 10;

  /// How many departments of the cart get a say. The whole basket would be a
  /// request per line and a shelf with no shape to it; the two the shopper has
  /// bought from most are the signal.
  static const departments = 2;

  /// And how many sub-categories, which are asked first.
  ///
  /// Three rather than two: this is the precise signal, so it is worth a
  /// little more of the basket than the department sweep behind it -- a cart
  /// holding running shoes, a laptop sleeve and a face cream should hear from
  /// all three rather than from the two biggest.
  static const subCategories = 3;

  @override
  State<CartRecommendations> createState() => _CartRecommendationsState();
}

class _CartRecommendationsState extends State<CartRecommendations> {
  /// Everything that came back, before the cart is subtracted from it.
  ///
  /// Held unfiltered so that adding one of these to the cart re-filters in
  /// place instead of costing another round trip.
  List<Product> _pool = const [];

  bool _loading = true;

  /// True when the last request that could have filled the shelf failed, so
  /// the section offers a retry rather than going quiet.
  bool _failed = false;

  /// The cart signal the pool was built for. A cart whose departments have not
  /// changed does not need a new pool, however much the quantities moved.
  String _signature = '';

  /// Which request is the current one. An add that lands while an earlier
  /// fetch is still in flight must not be overwritten by the answer to a
  /// question the cart has already stopped asking.
  int _generation = 0;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    CartStore.instance.addListener(_onCartChanged);
    // Cached to disk and shared with the home page, so this usually costs
    // nothing; asking is what covers a cold start.
    unawaited(CatalogStore.instance.categories.load());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    CartStore.instance.removeListener(_onCartChanged);
    super.dispose();
  }

  /// The departments in the cart, the one bought from most first.
  List<String> _cartCategories() {
    final counts = <String, int>{};
    for (final line in CartStore.instance.lines) {
      final name = line.category?.trim();
      if (name == null || name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + line.quantity;
    }
    final names = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return names;
  }

  /// The sub-categories in the cart, the one bought from most first.
  ///
  /// The catalogue's own ids, carried on the line since it was added. This is
  /// the sharp signal and the name list above is the blunt one: a line filed
  /// under "Display rack" or "flange" is a leaf the department tree does not
  /// contain, so matching by name found nothing and the shelf fell through to
  /// a general feed. The id needs no matching at all.
  List<String> _cartSubCategories() {
    final counts = <String, int>{};
    for (final line in CartStore.instance.lines) {
      final cid = line.categoryCid?.trim();
      if (cid == null || cid.isEmpty) continue;
      counts[cid] = (counts[cid] ?? 0) + line.quantity;
    }
    final cids = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return cids;
  }

  /// What the pool was built for: the sub-categories first, then the
  /// departments. Both, because two lines can share a department and sit in
  /// different sub-categories -- and that is a change the shelf should answer.
  String _cartSignature() =>
      '${_cartSubCategories().join(',')}#${_cartCategories().join('|')}';

  void _onCartChanged() {
    if (!mounted) return;
    final signature = _cartSignature();
    if (signature == _signature) {
      // The line-up or a quantity moved inside the same departments. The pool
      // still stands; only the "already in the cart" filter has shifted, and
      // that is applied at paint time. A rebuild, not a request.
      setState(() {});
      return;
    }
    // Adding three things in a row is one change of mind, not three. The
    // debounce is what stops it being three requests.
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_reload()),
    );
  }

  Future<void> _reload() async {
    final categories = _cartCategories();
    final subCategories = _cartSubCategories();
    final signature = _cartSignature();
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _signature = signature;
      });
    }

    var pool = <Product>[];

    // Nearest signal of all: the sub-categories the cart is actually buying
    // from, by their own ids.
    //
    // `/categories/{cid}/products` is the endpoint that answers at this depth.
    // `/feed/trending-products` does not: handed a leaf cid it returns 200 with
    // an empty list -- measured on `10308` (Display rack) and `1032607`
    // (flange), both of which `/categories/{cid}/products` answers with six
    // siblings apiece. It is a department-level endpoint, which is why it stays
    // below as the second signal rather than the first.
    for (final cid in subCategories.take(CartRecommendations.subCategories)) {
      try {
        pool.addAll(
          await CatalogRepository.instance.categoryProducts(
            cid,
            sort: ProductSort.sales,
            pageSize: 12,
          ),
        );
      } on ApiError {
        // One sub-category failing leaves the others, and the department
        // signal below, to answer for the cart.
      }
    }

    // Then the departments this cart is buying from, which catches the lines
    // whose sub-category is unknown -- anything added before the id was
    // carried, or from the history screens, which keep no id.
    final cids = await _cidsFor(categories);
    if (pool.length < CartRecommendations.shown) {
      for (final cid in cids.take(CartRecommendations.departments)) {
        try {
          pool.addAll(
            await CatalogRepository.instance.trending(
              categoryCid: cid,
              limit: 12,
            ),
          );
        } on ApiError {
          // One department failing is not the section failing. If the other
          // one answers, the shelf is still about this cart.
        }
      }
    }

    // The storefront tree and the catalogue's own labels are two different
    // taxonomies: a line filed under "Ordinary coat" has no department id to
    // look up, and on this catalogue most of them do not. Where the tree
    // cannot place a cart line, the line's own label becomes the query
    // instead -- still the shop's search, still the shop's products, and
    // still an answer about what is actually in the basket.
    if (pool.isEmpty) {
      for (final name in categories.take(CartRecommendations.departments)) {
        try {
          pool.addAll(
            await CatalogRepository.instance.search(
              query: name,
              sort: ProductSort.sales,
              pageSize: 12,
            ),
          );
        } on ApiError {
          // As above: one label drawing a blank leaves the other its turn.
        }
      }
    }

    // An empty cart, or a catalogue with nothing to say about this one: the
    // shop's own feed, which is what the home page offers in the same spot.
    var failed = false;
    if (pool.isEmpty) {
      try {
        pool = await CatalogRepository.instance.discover(pageSize: 24);
      } on ApiError {
        // The last source there is. The section says so and offers to ask
        // again, rather than a shelf that silently never appears.
        pool = <Product>[];
        failed = true;
      }
    }

    if (!mounted || generation != _generation) return;
    setState(() {
      _pool = pool;
      _failed = failed;
      _loading = false;
    });
  }

  /// The storefront ids for the department names the cart carries.
  ///
  /// A cart line records the department by name, not by id, so the tree is
  /// what turns one into the other. Names the tree does not know simply drop
  /// out, and a cart made entirely of those falls through to the general feed.
  Future<List<String>> _cidsFor(List<String> names) async {
    if (names.isEmpty) return const [];
    await CatalogStore.instance.categories.load();
    final tree = CatalogStore.instance.categories.value ?? const <Category>[];
    if (tree.isEmpty) return const [];

    final byName = <String, String>{};
    void walk(Category category) {
      byName.putIfAbsent(
        category.name.toLowerCase().trim(),
        () => category.cid,
      );
      for (final child in category.children) {
        walk(child);
      }
    }

    for (final category in tree) {
      walk(category);
    }

    return [
      for (final name in names) ?byName[name.toLowerCase().trim()],
    ];
  }

  /// The pool, less what is already in the cart and less anything the shop
  /// cannot put a price on.
  ///
  /// Recomputed at paint time rather than stored, so an add from this very
  /// rail takes the product out of it without another request.
  List<Product> _visible() {
    final inCart = <String>{
      for (final line in CartStore.instance.lines) line.productId,
    };
    final seen = <String>{};
    final out = <Product>[];
    for (final product in _pool) {
      if (out.length == CartRecommendations.shown) break;
      // A listing with no price is a card reading "Price on request" beside a
      // total -- and its Add button could not say what it would add.
      if (!product.hasPrice) continue;
      if (inCart.contains(product.numIid)) continue;
      // Two departments overlap more often than not.
      if (!seen.add(product.numIid)) continue;
      out.add(product);
    }
    return out;
  }

  Future<void> _addToCart(Product product) async {
    if (!product.hasPrice) return;
    // A product with something to choose asks first; one sold a single way
    // goes straight in. Either way it is the same cart.
    final outcome = await quickAddToCart(context, product);
    if (outcome != QuickAdd.added || !mounted) return;
    // The cart is the page this sits on, so the line appears above without
    // anything being said. The note is only for a shopper who added from the
    // bottom of a long cart and cannot see where it landed.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${product.title} added to your cart.'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  static const _title = 'Recommended for You';
  static const _icon = Icons.auto_awesome_outlined;

  @override
  Widget build(BuildContext context) {
    // The page's own 97% measure, centred, so the grid lines up with
    // everything else on the page and uses the width it is given.
    final measure = PageWidth.insets(context, bottom: 4);

    if (_loading) {
      // Cards the size the real ones will be, in the same grid, so nothing
      // moves when the products land.
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: _title, leadingIcon: _icon),
            Padding(
              padding: measure,
              child: const ResultGridSkeleton(
                count: 4,
                specFor: ResultGridSpec.search,
              ),
            ),
          ],
        ),
      );
    }

    if (_failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: _title, leadingIcon: _icon),
            Padding(
              padding: measure,
              child: LoadFailed(
                message: 'Recommendations could not be loaded.',
                onRetry: () => unawaited(_reload()),
              ),
            ),
          ],
        ),
      );
    }

    final products = _visible();
    if (products.isEmpty) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: _title, leadingIcon: _icon),
            Padding(
              padding: measure,
              child: Text(
                'Nothing to recommend right now.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Down the page rather than along a rail: two to a row on a phone, and
    // the cards the results page uses at the results page's compact sizing --
    // small gaps both ways, so the cards themselves get the width.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ProductGrid(
        title: _title,
        leadingIcon: _icon,
        products: products,
        onAddToCart: _addToCart,
        spec: ResultGridSpec.search,
        padding: measure,
        // Whole rows at whatever column count the width gets -- two on a
        // phone, three on a tablet -- so no card sits alone at the foot.
        wholeRows: true,
      ),
    );
  }
}

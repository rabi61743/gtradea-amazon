import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/action_status.dart';
import '../../../shared/widgets/loadable_view.dart' show LoadFailed;
import '../../../shared/widgets/page_width.dart';
import '../../auth/data/auth_store.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../home/widgets/product_carousel.dart' show toggleSavedProduct;
import '../../search/widgets/product_result_card.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../data/for_you_feed.dart';
import '../data/interest_profile.dart';

/// "New for You": a feed picked from what this shopper actually does.
///
/// Built from real signals only -- orders, cart, saved items, searches and the
/// products they opened, here and on the server -- and filled from the shop's
/// own catalogue endpoints; see [ForYouFeed]. A page at a time, more as the
/// shopper scrolls.
///
/// Kept for a while between visits, so coming back to the tab is not a fresh
/// wait -- unless what the shopper has done since has changed their
/// interests, in which case the feed is rebuilt for the new ones.
class NewForYouScreen extends StatefulWidget {
  const NewForYouScreen({super.key});

  /// How long a feed is kept for its account and interests.
  static const keepFor = Duration(minutes: 15);

  @visibleForTesting
  static void clearCacheForTest() => _FeedCache.current = null;

  @override
  State<NewForYouScreen> createState() => _NewForYouScreenState();
}

/// The feed as it was left, for the next visit.
class _FeedCache {
  _FeedCache({
    required this.key,
    required this.feed,
    required this.items,
    required this.exhausted,
  });

  static _FeedCache? current;

  final String key;
  final ForYouFeed feed;
  final List<Product> items;
  final bool exhausted;
  final DateTime at = DateTime.now();

  bool fresh(String forKey) =>
      key == forKey && DateTime.now().difference(at) < NewForYouScreen.keepFor;
}

class _NewForYouScreenState extends State<NewForYouScreen> {
  static const _pageSize = 20;

  ForYouFeed? _feed;
  List<Product> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _moreFailed = false;
  String? _error;
  bool _personal = false;
  String _key = '';

  /// Which build is current, so an answer to an abandoned one is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _saveCache();
    super.dispose();
  }

  void _saveCache() {
    final feed = _feed;
    if (feed == null || _items.isEmpty) return;
    _FeedCache.current = _FeedCache(
      key: _key,
      feed: feed,
      items: _items,
      exhausted: _exhausted,
    );
  }

  Future<void> _open({bool force = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = _items.isEmpty || force;
      _error = null;
      _moreFailed = false;
    });

    try {
      final profile = await InterestSignals.read();
      if (!mounted || generation != _generation) return;
      final key =
          '${AuthStore.instance.account?.id ?? 'guest'}'
          '#${profile.signature}';

      final cached = _FeedCache.current;
      if (!force && cached != null && cached.fresh(key)) {
        setState(() {
          _key = key;
          _feed = cached.feed;
          _items = cached.items;
          _exhausted = cached.exhausted;
          _personal = !profile.isEmpty;
          _loading = false;
        });
        return;
      }

      final shownBefore = await ForYouHistory.read();
      final feed = await ForYouFeed.build(profile, recentlyShown: shownBefore);
      final first = await feed.nextPage(size: _pageSize);
      if (!mounted || generation != _generation) return;

      if (first.isEmpty && feed.isExhausted) {
        setState(() {
          _loading = false;
          // Every source failed or had nothing: said plainly, with a retry,
          // rather than an empty page that looks finished.
          _error = 'Recommendations could not be loaded.';
        });
        return;
      }

      unawaited(ForYouHistory.remember(first.map((p) => p.numIid)));
      setState(() {
        _key = key;
        _feed = feed;
        _items = first;
        _exhausted = feed.isExhausted;
        _personal = !profile.isEmpty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Recommendations could not be loaded.';
      });
    }
  }

  /// Asks for the next page once the frame that noticed the scroll is over.
  void _requestMore() {
    if (_loadingMore || _exhausted || _loading || _moreFailed) return;
    if (_feed == null) return;
    _loadingMore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      unawaited(_loadMore());
    });
  }

  Future<void> _loadMore() async {
    final feed = _feed;
    final generation = _generation;
    if (feed == null) return;
    try {
      final more = await feed.nextPage(size: _pageSize);
      if (!mounted || generation != _generation) return;
      unawaited(ForYouHistory.remember(more.map((p) => p.numIid)));
      setState(() {
        _items = [..._items, ...more];
        _loadingMore = false;
        _exhausted = feed.isExhausted || more.isEmpty;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  void _retryMore() {
    setState(() => _moreFailed = false);
    _requestMore();
  }

  void _add(Product product) {
    if (!product.hasPrice) return;
    final inCart = CartStore.instance.add(
      CartLine(
        productId: product.numIid,
        title: product.title,
        unitPrice: product.displayPrice!,
        imageUrl: product.imageUrl,
        quantity: product.minOrder,
        minOrder: product.minOrder,
        category: product.categoryName,
        source: '1688',
      ),
    );
    ActionStatus.addedToCart(
      context,
      title: product.title,
      inCart: inCart,
      onViewCart: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const CartScreen())),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 900) {
      _requestMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LanguageStore.instance.strings;
    final measure = PageWidth.insets(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.newForYou)),
      body: RefreshIndicator(
        onRefresh: () => _open(force: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                // Four under the line rather than eight: this is the
                // heading-to-grid gap, and the grid below it already starts
                // with a card border.
                padding: measure.copyWith(top: 6, bottom: 4),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    _personal
                        ? 'Picked from what you view, search, save and buy. '
                              'New picks every visit.'
                        : 'Popular picks from across the shop. Browse, '
                              'search and save to make this yours.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (_loading)
                SliverPadding(
                  padding: measure,
                  sliver: const SliverToBoxAdapter(
                    child: ResultGridSkeleton(
                      count: 8,
                      specFor: ResultGridSpec.discovery,
                    ),
                  ),
                )
              else if (_error != null)
                SliverPadding(
                  padding: measure,
                  sliver: SliverToBoxAdapter(
                    child: LoadFailed(
                      message: _error!,
                      onRetry: () => _open(force: true),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: measure,
                  sliver: ListenableBuilder(
                    listenable: WishlistStore.instance,
                    builder: (context, _) =>
                        _Grid(products: _items, onAdd: _add),
                  ),
                ),
              if (!_loading && _error == null)
                SliverPadding(
                  padding: measure.copyWith(top: 10, bottom: 20),
                  sliver: SliverToBoxAdapter(
                    child: Center(child: _footer(theme)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    if (_loadingMore) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (_moreFailed) {
      return TextButton.icon(
        onPressed: _retryMore,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('More could not be loaded. Try again'),
      );
    }
    if (_exhausted) {
      return Text(
        "That's everything for now. Pull down for a fresh set.",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// The cards, in the grid the search results use: same columns, same gaps,
/// same measured height. Built lazily, so only what is on screen is drawn and
/// only its pictures are fetched.
class _Grid extends StatelessWidget {
  const _Grid({required this.products, required this.onAdd});

  final List<Product> products;
  final void Function(Product product) onAdd;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.crossAxisExtent;
        final spec = ResultGridSpec.discovery(available);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: spec.columns,
            mainAxisSpacing: spec.gap,
            crossAxisSpacing: spec.gap,
            // Measured dense, because the cards are drawn dense. The two read
            // the same flag so the grid's row height and the card's own height
            // cannot drift apart.
            mainAxisExtent: ProductResultCard.heightFor(
              context,
              spec.cardWidth(available),
              padding: spec.cardPadding,
              dense: true,
            ),
          ),
          delegate: SliverChildBuilderDelegate(childCount: products.length, (
            context,
            i,
          ) {
            final product = products[i];
            return ProductResultCard(
              product: product,
              padding: spec.cardPadding,
              dense: true,
              saved: WishlistStore.instance.contains(product.numIid),
              onTap: () => openProduct(context, product),
              onToggleSaved: () => toggleSavedProduct(context, product),
              onAddToCart: () => onAdd(product),
            );
          }),
        );
      },
    );
  }
}

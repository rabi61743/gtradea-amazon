import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/category_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../home/widgets/product_carousel.dart';

/// What to look at next, under the history.
///
/// Two shelves, both the shop's own: what is selling — the catalogue sorted by
/// sales, which is the same "trending" the home page links to — and the
/// departments the server puts first in its own `sort_order`. Nothing here is
/// a list this app made up.
///
/// It sits below the history and asks for nothing: a shopper who came to look
/// at what they had seen scrolls past it untouched.
class DiscoverMoreSection extends StatefulWidget {
  const DiscoverMoreSection({super.key, this.onSeeAll});

  /// Where "See all" goes, as the screen around this knows it.
  final VoidCallback? onSeeAll;

  /// How many of each to show. Enough to be worth swiping, few enough that
  /// this stays a footer rather than a second storefront.
  static const shown = 8;

  /// The card width of this rail: more compact than the storefront's 190, so
  /// the picture and the card are about a fifth smaller in proportion.
  static const cardWidth = 150.0;

  /// How long a trending answer is reused before it is asked for again.
  static const cacheTtl = Duration(minutes: 5);

  static Future<List<Product>>? _inFlight;
  static List<Product>? _cached;
  static DateTime? _cachedAt;

  /// The trending products, if a fresh answer is already held.
  static List<Product>? get cached {
    final at = _cachedAt;
    if (_cached == null || at == null) return null;
    return DateTime.now().difference(at) < cacheTtl ? _cached : null;
  }

  /// Starts fetching the trending shelf, or joins the fetch already running.
  ///
  /// Measured on the phone, the request itself answers in about 200 ms. What
  /// made this section slow was when it was asked: it sits at the foot of a
  /// lazily built list, so its fetch only began once the shopper scrolled down
  /// to it -- and scrolling away and back rebuilt it and fetched again. The
  /// history screen calls this as it opens, so the shelf is usually ready by
  /// the time anybody reaches it, and every later build reuses the one answer.
  static Future<List<Product>> prefetch() {
    final fresh = cached;
    if (fresh != null) return Future.value(fresh);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  static Future<List<Product>> _fetch() async {
    final products = await CatalogRepository.instance.search(
      query: '',
      sort: ProductSort.sales,
      pageSize: shown + 4,
    );
    final shelf = products
        .where((p) => p.hasPrice)
        .take(shown)
        .toList(growable: false);
    _cached = shelf;
    _cachedAt = DateTime.now();
    return shelf;
  }

  @visibleForTesting
  static void resetForTest() {
    _inFlight = null;
    _cached = null;
    _cachedAt = null;
  }

  @override
  State<DiscoverMoreSection> createState() => _DiscoverMoreSectionState();
}

class _DiscoverMoreSectionState extends State<DiscoverMoreSection> {
  /// Already fetched -- by the screen as it opened, or an earlier build of
  /// this section -- draws on the first frame, with no request and no bones.
  List<Product> _trending = DiscoverMoreSection.cached ?? const [];
  late bool _loading = DiscoverMoreSection.cached == null;

  @override
  void initState() {
    super.initState();
    if (_loading) unawaited(_load());
    // The department tree is cached to disk and shared with the home page, so
    // this usually costs nothing; asking is what covers a cold start.
    unawaited(CatalogStore.instance.categories.load());
  }

  Future<void> _load() async {
    try {
      final products = await DiscoverMoreSection.prefetch();
      if (!mounted) return;
      setState(() {
        _trending = products;
        _loading = false;
      });
    } on ApiError {
      // A shelf that did not load is a shelf that is not shown. This is a
      // suggestion under somebody's history, not information they are owed.
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCategory(Category category) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CategoryScreen(category: category)),
    );
  }

  void _addToCart(Product product) {
    CartStore.instance.add(
      CartLine(
        productId: product.numIid,
        title: product.title,
        unitPrice: product.displayPrice ?? 0,
        imageUrl: product.imageUrl,
        category: product.categoryName,
        categoryCid: product.categoryCid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogStore.instance.categories,
      builder: (context, _) {
        final categories = CatalogStore.instance.categories.value ?? const [];
        final popular = categories.length <= DiscoverMoreSection.shown
            ? categories
            : categories.sublist(0, DiscoverMoreSection.shown);

        // Nothing to offer and nothing on the way: draw nothing at all rather
        // than a heading over an empty strip.
        if (!_loading && _trending.isEmpty && popular.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            _Heading(onSeeAll: widget.onSeeAll),
            if (popular.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Departments(categories: popular, onOpen: _openCategory),
            ],
            const SizedBox(height: 14),
            if (_loading)
              const ProductCarouselSkeleton(
                count: 3,
                width: DiscoverMoreSection.cardWidth,
              )
            else if (_trending.isNotEmpty)
              SizedBox(
                height: ProductCarousel.heightFor(
                  context,
                  width: DiscoverMoreSection.cardWidth,
                ),
                child: ProductCarousel(
                  title: '',
                  products: _trending,
                  onAddToCart: _addToCart,
                  width: DiscoverMoreSection.cardWidth,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The section's own line: what it is, and the way past it.
class _Heading extends StatelessWidget {
  const _Heading({this.onSeeAll});

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The brand blue the Load More button and the prices above use, so the
    // section reads as part of the same page.
    final ink = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.commerceOrange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.explore_outlined,
              size: 16,
              color: AppColors.commerceOrange,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Discover more products',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                Text(
                  'Trending on gtradea.com',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onSeeAll case final seeAll?)
            TextButton(
              onPressed: seeAll,
              style: TextButton.styleFrom(
                foregroundColor: ink,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }
}

/// The departments, in the order the shop puts them.
class _Departments extends StatelessWidget {
  const _Departments({required this.categories, required this.onOpen});

  final List<Category> categories;
  final ValueChanged<Category> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.primary;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = categories[i];
          return Material(
            color: ink.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: InkWell(
              onTap: () => onOpen(category),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  category.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

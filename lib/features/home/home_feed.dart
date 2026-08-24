import 'package:flutter/material.dart';

import '../../core/async/loadable.dart';
import '../../shared/widgets/loadable_view.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/data/catalog_store.dart';
import '../catalog/data/product.dart';
import '../catalog/presentation/catalog_visuals.dart';
import '../search/presentation/search_results_screen.dart';
import 'widgets/category_section.dart';
import 'widgets/department_grid.dart';
import 'widgets/hero_banner.dart' as banner;
import 'widgets/product_rail.dart';

/// The home feed, built from what the catalogue actually contains.
///
/// Every block below is a separate request that loads and fails on its own.
/// That is the point: the department rails are the slowest thing on the page,
/// and one of them timing out must not take the banners and the recommendation
/// rail down with it.
class HomeFeed extends StatefulWidget {
  const HomeFeed({super.key});

  @override
  State<HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<HomeFeed> {
  /// How many departments get a rail of their own before the grid.
  ///
  /// Each one is a request, so this is a real cost. Five is enough for the page
  /// to feel like a storefront without opening a dozen connections at once.
  static const _railCount = 5;

  @override
  void initState() {
    super.initState();
    CatalogStore.instance.banners.load();
    CatalogStore.instance.discover.load();
    CatalogStore.instance.categories.load();
  }

  void _openSearch(BuildContext context, {String query = '', String? cid}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchResultsScreen(query: query, categoryCid: cid),
    ));
  }

  /// Turns a campaign link into a screen.
  ///
  /// The links are web routes written by whoever set the banner up, so most of
  /// them point at pages this app does not have. Search is the one shape worth
  /// following; everything else leaves the banner as artwork rather than
  /// sending a shopper somewhere blank.
  VoidCallback? _bannerAction(BuildContext context, HeroBanner item) {
    final link = item.buttonLink;
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.path.startsWith('/search')) return null;
    final query = uri.queryParameters['q'] ?? '';
    return () => _openSearch(context, query: query);
  }

  @override
  Widget build(BuildContext context) {
    final store = CatalogStore.instance;

    return RefreshIndicator(
      onRefresh: store.refreshHome,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 14),
          LoadableView<List<HeroBanner>>(
            loadable: store.banners,
            // No skeleton: an empty strip where a banner will be is less
            // distracting than a grey box that then jumps to full height.
            loading: const SizedBox.shrink(),
            emptyCheck: (banners) => banners.isEmpty,
            builder: (context, banners) => banner.HeroBanner(
              items: [
                for (final item in banners)
                  banner.BannerItem(
                    headline: item.showTextOverlay ? item.title : '',
                    caption: item.showTextOverlay ? (item.subtitle ?? '') : '',
                    cta: item.buttonText ?? 'Shop now',
                    tint: tintForCategory(item.id),
                    imageUrl: item.imageUrl,
                    onTap: _bannerAction(context, item),
                  ),
              ],
            ),
          ),
          LoadableView<List<Product>>(
            loadable: store.discover,
            emptyCheck: (products) => products.isEmpty,
            builder: (context, products) => ProductRail(
              title: 'Recommended for you',
              leadingIcon: Icons.auto_awesome,
              items: toProductItems(context, products),
              onSeeAll: () => _openSearch(context),
            ),
          ),
          LoadableView<List<Category>>(
            loadable: store.categories,
            emptyCheck: (categories) => categories.isEmpty,
            builder: (context, categories) => Column(
              children: [
                for (final department in categories.take(_railCount))
                  _DepartmentBlock(
                    department: department,
                    rail: store.rail(department.cid),
                    onSeeAll: () => _openSearch(context, cid: department.cid),
                    onOpenChild: (child) =>
                        _openSearch(context, cid: child.cid),
                  ),
                DepartmentGrid(
                  title: 'Shop by category',
                  leadingIcon: Icons.grid_view,
                  entries: [
                    for (final department in categories)
                      DepartmentEntry(
                        label: department.name,
                        icon: iconForCategory(department.name),
                        tint: tintForCategory(department.cid),
                        imageUrl: department.imageUrl,
                        onTap: () =>
                            _openSearch(context, cid: department.cid),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One department: its best sellers, then its subcategories.
///
/// The rail loads when the block is first built rather than at startup, so a
/// shopper who never scrolls past the second department never pays for the
/// fifth one.
class _DepartmentBlock extends StatefulWidget {
  const _DepartmentBlock({
    required this.department,
    required this.rail,
    required this.onSeeAll,
    required this.onOpenChild,
  });

  final Category department;
  final Loadable<List<Product>> rail;
  final VoidCallback onSeeAll;
  final void Function(Category child) onOpenChild;

  @override
  State<_DepartmentBlock> createState() => _DepartmentBlockState();
}

class _DepartmentBlockState extends State<_DepartmentBlock> {
  @override
  void initState() {
    super.initState();
    widget.rail.load();
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.department.children;

    return Column(
      children: [
        LoadableView<List<Product>>(
          loadable: widget.rail,
          loading: const SizedBox.shrink(),
          emptyCheck: (products) => products.isEmpty,
          builder: (context, products) => ProductRail(
            title: widget.department.name,
            leadingIcon: iconForCategory(widget.department.name),
            items: toProductItems(context, products),
            onSeeAll: widget.onSeeAll,
          ),
        ),
        if (children.isNotEmpty)
          CategorySection(
            title: 'Browse ${widget.department.name}',
            leadingIcon: Icons.subdirectory_arrow_right,
            entries: [
              for (final child in children.take(8))
                CategoryEntry(
                  label: child.name,
                  icon: iconForCategory(child.name),
                  tint: tintForCategory(child.cid),
                  imageUrl: child.imageUrl,
                  onTap: () => widget.onOpenChild(child),
                ),
            ],
            onSeeAll: widget.onSeeAll,
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../shared/widgets/section_header.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../search/widgets/product_result_card.dart';
import '../../wishlist/data/wishlist_store.dart';

/// What the page lists once a department tab is chosen.
///
/// Replaces the For You feed in place rather than pushing a screen: the whole
/// point of a tab strip is that comparing three departments costs three taps,
/// not three round trips through a results page and back.
///
/// **The subcategories work the same way.** They used to push a results screen;
/// now picking one narrows this page and picking it again widens it back. Same
/// reason: a shopper comparing "Women's Sweaters" with "Women's Down Jackets"
/// should not be walking through a navigation stack to do it.
///
/// Two sources, because the two levels are not served by the same endpoint --
/// measured against production rather than assumed:
///
///   * the **department** comes from `/feed/trending-products`, which the store
///     already memoises per department, so a department visited twice repaints
///     from memory;
///   * a **subcategory** comes from `/search/products?category=`, because
///     `/feed/trending-products` answers with an empty list for every
///     subcategory cid tried -- including ones that demonstrably have products.
///     Using it for both would have made every subcategory look empty.
class DepartmentFeed extends StatefulWidget {
  const DepartmentFeed({
    super.key,
    required this.department,
    required this.onSeeAll,
    this.onSeeAllChild,
    this.onAddToCart,
  });

  final Category department;

  /// Opens the full listing for the department.
  final VoidCallback onSeeAll;

  /// Opens the full listing for a chosen subcategory. The only way out of this
  /// page, and it is a button the shopper presses rather than something that
  /// happens to them when they tap a chip.
  final void Function(Category child)? onSeeAllChild;

  final void Function(Product product)? onAddToCart;

  @override
  State<DepartmentFeed> createState() => _DepartmentFeedState();
}

class _DepartmentFeedState extends State<DepartmentFeed> {
  /// The subcategory in force, or null for the whole department.
  Category? _child;

  List<Product> _products = const [];
  bool _loading = false;
  ApiError? _error;

  /// Set when a chosen subcategory had nothing in it and the department is
  /// being shown instead, so the page can say which is which.
  String? _emptyChild;

  /// Guards against a slow request for one subcategory landing after a fast one
  /// for another and overwriting it. Two chips in quick succession is enough.
  int _generation = 0;

  @override
  void didUpdateWidget(DepartmentFeed old) {
    super.didUpdateWidget(old);
    // A different department: the old department's subcategory is not one of
    // this one's, so it goes rather than narrowing the new tab by a chip that
    // is no longer on screen.
    if (old.department.cid != widget.department.cid) {
      _generation++;
      _child = null;
      _products = const [];
      _error = null;
      _loading = false;
      _emptyChild = null;
    }
  }

  /// Narrows to a subcategory, or widens back when the same one is tapped.
  Future<void> _select(Category? child) async {
    final generation = ++_generation;
    setState(() {
      _child = child;
      _error = null;
      _emptyChild = null;
      _loading = child != null;
      _products = const [];
    });
    if (child == null) return;

    try {
      final found = await CatalogRepository.instance.search(
        categoryCid: child.cid,
        sort: ProductSort.sales,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _generation) return;

      // Nothing under it. Fourteen of the thirty-two subcategory tiles the home
      // page shows are in this state -- the tree lists what the storefront
      // could carry, not what it does -- so this is the common case rather than
      // an edge one, and dropping the shopper on a blank page is not an answer.
      if (found.isEmpty) {
        setState(() {
          _child = null;
          _loading = false;
          _emptyChild = child.name;
        });
        return;
      }

      setState(() {
        _products = found;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  static const _pageSize = 24;

  @override
  Widget build(BuildContext context) {
    final children = widget.department.children;
    final child = _child;

    return ListView(
      // Keyed on the department so switching tabs starts at the top rather
      // than holding the scroll position of the department just left.
      key: ValueKey(widget.department.cid),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (children.isNotEmpty)
          _Subcategories(
            children: children,
            selected: child,
            onSelected: _select,
          ),
        if (_emptyChild != null) _EmptyChildNotice(name: _emptyChild!),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            child == null
                ? 'Trending in ${widget.department.name}'
                : child.name,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (child == null)
          _DepartmentProducts(
            department: widget.department,
            onAddToCart: widget.onAddToCart,
          )
        else
          _ChildProducts(
            loading: _loading,
            error: _error,
            products: _products,
            name: child.name,
            onRetry: () => _select(child),
            onAddToCart: widget.onAddToCart,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: OutlinedButton.icon(
            // Points at whatever is being shown. Offering "everything in Women"
            // while the page is listing Women's Sweaters would be a button that
            // widens the results without saying it does.
            onPressed: child == null
                ? widget.onSeeAll
                : () => widget.onSeeAllChild?.call(child),
            icon: const Icon(Icons.grid_view, size: 18),
            label: Text(
              'See everything in ${child?.name ?? widget.department.name}',
            ),
          ),
        ),
      ],
    );
  }
}

/// The department's own products, from the rail the store memoises.
class _DepartmentProducts extends StatefulWidget {
  const _DepartmentProducts({required this.department, this.onAddToCart});

  final Category department;
  final void Function(Product product)? onAddToCart;

  @override
  State<_DepartmentProducts> createState() => _DepartmentProductsState();
}

class _DepartmentProductsState extends State<_DepartmentProducts> {
  @override
  void initState() {
    super.initState();
    // In initState rather than in build: kicked from build, every rebuild of
    // this widget or any ancestor started another fetch.
    CatalogStore.instance.rail(widget.department.cid).load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogStore.instance.rail(widget.department.cid),
      builder: (context, _) {
        final rail = CatalogStore.instance.rail(widget.department.cid);
        final products = rail.value;

        if (products == null && rail.isLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: ResultGridSkeleton(count: 4),
          );
        }
        if (products == null || products.isEmpty) {
          return _Nothing(name: widget.department.name);
        }
        return _Grid(products: products, onAddToCart: widget.onAddToCart);
      },
    );
  }
}

/// A chosen subcategory's products.
class _ChildProducts extends StatelessWidget {
  const _ChildProducts({
    required this.loading,
    required this.error,
    required this.products,
    required this.name,
    required this.onRetry,
    this.onAddToCart,
  });

  final bool loading;
  final ApiError? error;
  final List<Product> products;
  final String name;
  final VoidCallback onRetry;
  final void Function(Product product)? onAddToCart;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      // Card-shaped placeholders at the size the real cards will be, so
      // narrowing does not drop the page to a spinner and jump back to a grid.
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: ResultGridSkeleton(count: 4),
      );
    }

    final failed = error;
    if (failed != null) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
    }

    if (products.isEmpty) return _Nothing(name: name);
    return _Grid(products: products, onAddToCart: onAddToCart);
  }
}

/// Said when a chip was tapped and the catalogue had nothing under it.
///
/// The chip clears itself rather than sitting selected over a blank grid, so
/// this both explains the empty tap and says what is on screen now.
class _EmptyChildNotice extends StatelessWidget {
  const _EmptyChildNotice({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.category_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nothing in $name yet. Showing the whole department.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The department's own subcategories, as chips.
///
/// Real names from the tree rather than invented shortcuts. Tapping one narrows
/// the page below; tapping the selected one widens it back, which is what makes
/// this a filter rather than a menu.
class _Subcategories extends StatelessWidget {
  const _Subcategories({
    required this.children,
    required this.selected,
    required this.onSelected,
  });

  final List<Category> children;
  final Category? selected;
  final ValueChanged<Category?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          SectionHeader.edge,
          10,
          SectionHeader.edge,
          0,
        ),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final child = children[i];
          final isSelected = child.cid == selected?.cid;

          return FilterChip(
            label: Text(child.name),
            selected: isSelected,
            // Tapping the selected one clears it, so there is always a way back
            // to the whole department without hunting for one.
            onSelected: (_) => onSelected(isSelected ? null : child),
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.products, this.onAddToCart});

  final List<Product> products;
  final void Function(Product product)? onAddToCart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListenableBuilder(
        listenable: WishlistStore.instance,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final width = ProductResultCard.widthFor(constraints.maxWidth);

            return Wrap(
              spacing: ProductResultCard.gridGap,
              runSpacing: ProductResultCard.gridGap,
              children: [
                for (final product in products)
                  SizedBox(
                    width: width,
                    // The card reports its own height, so the row cannot end up
                    // shorter than the card wants and clip it.
                    height: ProductResultCard.heightFor(context, width),
                    child: ProductResultCard(
                      product: product,
                      saved: WishlistStore.instance.contains(product.numIid),
                      onTap: () => openProduct(context, product),
                      onToggleSaved: () => _toggleSaved(context, product),
                      onAddToCart: onAddToCart == null
                          ? null
                          : () => onAddToCart!(product),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _toggleSaved(BuildContext context, Product product) {
    final saved = WishlistStore.instance.toggle(
      SavedProduct(
        id: product.numIid,
        title: product.title,
        price: product.displayPrice ?? 0,
        imageUrl: product.imageUrl,
        sellerBadge: product.sellerBadge,
        salesLabel: product.salesLabel,
        category: product.categoryName,
        minOrder: product.minOrder,
      ),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Saved to your list' : 'Removed from your list',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// A department or subcategory the catalogue has nothing trending in just now.
///
/// Says so without reading as a dead end: nothing trending is not the same as
/// nothing in it, and the "See everything" button below this still works.
class _Nothing extends StatelessWidget {
  const _Nothing({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing trending in $name right now.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The department itself still has products in it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

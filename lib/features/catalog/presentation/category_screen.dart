import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../shared/widgets/section_header.dart';
import '../../home/widgets/subcategory_grid.dart';
import '../../search/presentation/search_results_screen.dart';
import '../data/catalog_repository.dart';

/// One category's own subcategories, on their own screen.
///
/// The middle step of category -> subcategory -> products. Tapping "Antenna"
/// used to jump straight to a product listing, which skipped a level the
/// catalogue actually has: Antenna holds six subcategories of its own, and
/// Capacitor twelve.
///
/// Everything here comes from `/alibaba-categories` at the moment the screen is
/// opened, keyed on the category's own cid -- names, ids and artwork. The tree
/// the app caches stops at two levels, so this is a real request rather than a
/// lookup, which is why it carries loading, empty and failure states of its own
/// instead of borrowing the home page's.
///
/// **Artwork at this depth is mostly absent.** Measured against production: all
/// six of Antenna's children, all five of Audio Devices', all twelve of
/// Capacitor's and all eleven of Diode's come back with a null `image_url`. The
/// tiles fall through to the tinted panel and the category glyph, which is what
/// that fallback was built for -- rather than a grey box or a broken-image
/// mark. Nothing here invents a picture to fill the gap.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.category});

  final Category category;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<Category>? _children;
  ApiError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await CatalogRepository.instance.subcategories(
        widget.category.cid,
      );
      if (!mounted) return;
      setState(() {
        _children = found;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _openProducts(Category category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(
          query: '',
          categoryCid: category.cid,
          // This screen already knows what it is called. The tree the results
          // page consults is two levels deep and these are the third, so
          // without this the chip reads "Department".
          categoryName: category.name,
          // Where to widen to if this subcategory turns out to be empty, which
          // at this level it usually is. This screen is that parent.
          parentCid: widget.category.cid,
          parentName: widget.category.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name)),
      body: RefreshIndicator(onRefresh: _load, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const _Loading();

    final failed = _error;
    if (failed != null) {
      return _Failed(message: failed.message, onRetry: _load);
    }

    final children = _children ?? const <Category>[];

    // Always scrollable, so pull-to-refresh still works in the empty state.
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (children.isEmpty)
          _NoSubcategories(name: widget.category.name)
        else
          SubcategoryGrid(
            title: 'Browse ${widget.category.name}',
            subtitle: children.length == 1
                ? '1 subcategory'
                : '${children.length} subcategories',
            // Every one of them, not the four a home block shows. This screen
            // exists to be the full list of the level below.
            shown: children.length,
            // The level where this catalogue's artwork runs out. See
            // CategoryThumbnails for what fills the gap and what it is not.
            fillMissingImages: true,
            children: children,
            onSelected: _openProducts,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: OutlinedButton.icon(
            // The way to products without picking a subcategory first: the only
            // action in the empty state, and a shortcut in the other.
            onPressed: () => _openProducts(widget.category),
            icon: const Icon(Icons.grid_view, size: 18),
            label: Text('See all products in ${widget.category.name}'),
          ),
        ),
      ],
    );
  }
}

/// Tiles at the size the real ones will be, rather than a centred spinner.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SectionHeader.edge,
        SectionHeader.gapAbove,
        SectionHeader.edge,
        24,
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = SubcategoryGrid.gap;
            final width = (constraints.maxWidth - gap) / 2;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: width,
                    height: width,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A category the catalogue holds no subcategories under.
///
/// Plenty are leaves, so this is an ordinary answer rather than a failure --
/// and it says so, with the products a button away instead of a dead end.
class _NoSubcategories extends StatelessWidget {
  const _NoSubcategories({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '$name has no subcategories',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'It is the last level of the catalogue here, so its products are '
            'one tap away below.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// The request failed. Says what went wrong and offers to try again.
class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      children: [
        Icon(
          Icons.cloud_off_outlined,
          size: 28,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          'Could not load subcategories',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        // The server's own words. A generic "something went wrong" is what
        // makes an outage indistinguishable from an empty catalogue.
        Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

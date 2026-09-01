import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../flash_sale/data/flash_sale.dart';
import '../../flash_sale/presentation/product_deal_banner.dart';
import '../../flash_sale/presentation/sale_countdown.dart';
import '../../search/data/search_models.dart';
import '../../search/widgets/filter_sheet.dart';
import '../data/deals_repository.dart';
import 'deal_grid.dart';

/// Everything on offer, in one browsable grid.
///
/// Where "Shop All Deals" goes. The mechanics -- the generation guard, the
/// infinite scroll, the de-duplication, the swallowed page-two errors -- are
/// lifted from `search_results_screen.dart` rather than reinvented, because
/// that screen already got each of them right and the failure modes they guard
/// against are not obvious ones.
class DealsScreen extends StatefulWidget {
  const DealsScreen({super.key, this.categoryCid});

  /// Narrows the deals to one department, when opened from inside one.
  final String? categoryCid;

  @override
  State<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends State<DealsScreen> {
  FilterSelection _selection = {};
  ProductSort _sort = ProductSort.sales;
  int _minDiscount = 0;

  List<FlashSaleItem> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _cutShort = false;
  ApiError? _error;

  /// How many catalogue rows have been read, which is not the same as how many
  /// cards are on screen once a discount band is on. Paging by the card count
  /// would re-read the rows the band rejected, forever.
  int _rowsConsumed = 0;

  /// Guards against an older request landing after a newer one and overwriting
  /// it. Changing a filter and a sort quickly makes that happen.
  int _generation = 0;

  static const _pageSize = 24;

  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
    // The deadline header reads this. Asked for here rather than assumed: this
    // screen is reachable from a department and from a deep link, not only from
    // the home page that happens to have loaded it already.
    unawaited(CatalogStore.instance.flashSale.load());
    unawaited(_run());
  }

  int get _selectedCount =>
      _selection.values.fold(0, (sum, options) => sum + options.length);

  /// The chosen price bands as one window. Several bands mean the widest of
  /// them, and any open-ended band removes that end of the window.
  (num?, num?) get _priceWindow {
    final chosen = _selection[_priceGroup] ?? const <String>{};
    if (chosen.isEmpty) return (null, null);

    num? low;
    num? high;
    var openEnded = false;

    for (final label in chosen) {
      final band = _priceBands[label];
      if (band == null) continue;
      final (bandLow, bandHigh) = band;
      if (bandLow != null) low = low == null ? bandLow : _min(low, bandLow);
      if (bandHigh == null) {
        openEnded = true;
      } else {
        high = high == null ? bandHigh : _max(high, bandHigh);
      }
    }

    return (low, openEnded ? null : high);
  }

  static num _min(num a, num b) => a < b ? a : b;
  static num _max(num a, num b) => a > b ? a : b;

  Future<void> _run() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _exhausted = false;
      _cutShort = false;
    });

    final (minPrice, maxPrice) = _priceWindow;
    try {
      final page = await DealsRepository.instance.page(
        categoryCid: widget.categoryCid,
        minPrice: minPrice,
        maxPrice: maxPrice,
        minDiscount: _minDiscount,
        sort: _sort,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _rowsConsumed = page.rowsConsumed;
        _exhausted = !page.hasMore;
        _cutShort = page.filterCutShort;
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

  void _requestMore() {
    if (_loadingMore || _exhausted || _loading || _error != null) return;
    _loadingMore = true;
    // The scroll notification arrives during layout, so the rebuild has to wait
    // for the frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      unawaited(_loadMore());
    });
  }

  Future<void> _loadMore() async {
    final generation = _generation;
    final (minPrice, maxPrice) = _priceWindow;

    try {
      final page = await DealsRepository.instance.page(
        categoryCid: widget.categoryCid,
        minPrice: minPrice,
        maxPrice: maxPrice,
        minDiscount: _minDiscount,
        sort: _sort,
        pageSize: _pageSize,
        offset: _rowsConsumed,
      );
      if (!mounted || generation != _generation) return;

      // The catalogue does return the same row twice across pages. Appending
      // blindly shows it twice.
      final seen = _items.map((i) => i.product.numIid).toSet();
      final fresh = page.items
          .where((i) => seen.add(i.product.numIid))
          .toList();

      setState(() {
        _items = [..._items, ...fresh];
        _rowsConsumed += page.rowsConsumed;
        _exhausted = !page.hasMore;
        _cutShort = page.filterCutShort;
        _loadingMore = false;
      });
    } on ApiError {
      // Deliberately quiet. The rows already on screen are good, and replacing
      // them with an error because page four failed would undermine them.
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openFilters() async {
    final chosen = await showModalBottomSheet<FilterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(
        groups: const [FilterGroup(label: _priceGroup, options: _priceLabels)],
        initial: _selection,
        // Only the server knows how many rows a price window holds, and a
        // count guessed from the page on screen would be a number made up on
        // the device.
        matchCount: null,
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _selection = chosen);
    unawaited(_run());
  }

  Future<void> _openSort() async {
    final chosen = await showModalBottomSheet<ProductSort>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Only the five the server parses. There is no "biggest discount"
            // here on purpose: the discount is worked out on this side, so
            // ordering by it could only order the rows already fetched -- and
            // each new page would shuffle the ones above it. The discount band
            // above the grid answers the same question without that.
            RadioGroup<ProductSort>(
              groupValue: _sort,
              onChanged: (value) => Navigator.of(sheetContext).pop(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in ProductSort.values)
                    RadioListTile<ProductSort>(
                      value: option,
                      title: Text(option.label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted || chosen == _sort) return;
    setState(() => _sort = chosen);
    unawaited(_run());
  }

  void _setBand(int minDiscount) {
    if (minDiscount == _minDiscount) return;
    setState(() => _minDiscount = minDiscount);
    unawaited(_run());
  }

  void _clearFilters() {
    setState(() {
      _selection = {};
      _minDiscount = 0;
    });
    unawaited(_run());
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters = _selectedCount > 0 || _minDiscount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deals'),
        actions: [
          ListenableBuilder(
            listenable: CartStore.instance,
            builder: (context, _) => IconButton(
              icon: Badge.count(
                count: CartStore.instance.count,
                isLabelVisible: CartStore.instance.count > 0,
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              tooltip: 'Cart',
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CartScreen())),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const _SaleDeadline(),
          _DiscountBands(selected: _minDiscount, onSelected: _setBand),
          _FilterBar(
            selectedCount: _selectedCount,
            sortLabel: _sort.label,
            onFilters: _openFilters,
            onSort: _openSort,
            onClear: hasFilters ? _clearFilters : null,
          ),
          Expanded(child: _body(hasFilters)),
        ],
      ),
    );
  }

  Widget _body(bool hasFilters) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: LoadFailed(
          message: error.isNetwork
              ? 'No connection. Check your network and try again.'
              : error.message,
          onRetry: _run,
        ),
      );
    }

    if (_items.isEmpty) {
      return _NoDeals(hasFilters: hasFilters, onClear: _clearFilters);
    }

    // Pulling to refresh, which this screen had no way to do: a sale's prices
    // and stock move under it, and the only way to re-read them was to leave
    // and come back.
    return RefreshIndicator(
      onRefresh: _run,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 600) _requestMore();
          return false;
        },
        child: SingleChildScrollView(
          // Always scrollable, or a short first page leaves nothing to pull.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DealGrid(
                items: _items,
                // The offer travels with the tap, so the page opens showing the
                // same discount, the same "was" price and the same deadline the
                // card did.
                onOpen: (item) => openProduct(
                  context,
                  item.product,
                  deal: ProductDeal(
                    item: item,
                    endsAt: CatalogStore.instance.flashSale.value?.endsAt,
                  ),
                ),
                onAddToCart: (item) => _addToCart(item),
              ),
              const SizedBox(height: 20),
              _Footer(
                loading: _loadingMore,
                exhausted: _exhausted,
                cutShort: _cutShort,
                onMore: _requestMore,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addToCart(FlashSaleItem item) {
    final product = item.product;
    CartStore.instance.add(
      CartLine(
        productId: product.numIid,
        title: product.title,
        // The sale price, not the catalogue price. Adding the full price from a
        // card advertising a discount is the worst bug available here.
        unitPrice: item.salePrice,
        listPrice: item.hasSaving ? item.listPrice : null,
        imageUrl: product.imageUrl,
        quantity: product.minOrder,
        minOrder: product.minOrder,
        category: product.categoryName,
        source: '1688',
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${product.title} added to your cart'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// The discount bands, as a scrolling strip of chips.
class _DiscountBands extends StatelessWidget {
  const _DiscountBands({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  static const _bands = <(int, String)>[
    (0, 'All deals'),
    (20, '20% and over'),
    (30, '30% and over'),
    (40, '40% and over'),
    (50, '50% and over'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _bands.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (value, label) = _bands[index];
          final isSelected = value == selected;

          return ChoiceChip(
            selected: isSelected,
            onSelected: (_) => onSelected(value),
            label: Text(label),
            selectedColor: AppColors.accent.withValues(alpha: 0.14),
            side: BorderSide(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            labelStyle: TextStyle(
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              color: isSelected
                  ? AppColors.accent
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

/// Filters and sort, on one row above the grid.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selectedCount,
    required this.sortLabel,
    required this.onFilters,
    required this.onSort,
    this.onClear,
  });

  final int selectedCount;
  final String sortLabel;
  final VoidCallback onFilters;
  final VoidCallback onSort;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onFilters,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  selectedCount == 0 ? 'Filters' : 'Filters ($selectedCount)',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onSort,
                icon: const Icon(Icons.swap_vert, size: 18),
                label: Text(
                  sortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
                tooltip: 'Clear filters',
                onPressed: onClear,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What sits under the grid: a spinner, the end, or a way to keep going.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.loading,
    required this.exhausted,
    required this.cutShort,
    required this.onMore,
  });

  final bool loading;
  final bool exhausted;
  final bool cutShort;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }

    // Stopped on the round-trip budget rather than on the end of the
    // catalogue. Saying "that is everything" here would be wrong, and showing
    // nothing would look like it.
    if (cutShort && !exhausted) {
      return Center(
        child: OutlinedButton.icon(
          onPressed: onMore,
          icon: const Icon(Icons.expand_more, size: 18),
          label: const Text('Load more deals'),
        ),
      );
    }

    if (exhausted) {
      return Center(
        child: Text(
          'That is every deal we have right now.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return const SizedBox(height: 4);
  }
}

class _NoDeals extends StatelessWidget {
  const _NoDeals({required this.hasFilters, required this.onClear});

  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_offer_outlined,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              hasFilters
                  ? 'Nothing matches these filters'
                  : 'No deals just now',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try a smaller discount or a wider price range.'
                  : 'Check back soon -- offers change through the day.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onClear,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                ),
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _priceGroup = 'Price';

const _priceBands = <String, (num?, num?)>{
  'Under Rs. 500': (null, 500),
  'Rs. 500 - 2,000': (500, 2000),
  'Rs. 2,000 - 10,000': (2000, 10000),
  'Over Rs. 10,000': (10000, null),
};

const _priceLabels = [
  'Under Rs. 500',
  'Rs. 500 - 2,000',
  'Rs. 2,000 - 10,000',
  'Over Rs. 10,000',
];

/// The sale's deadline, carried onto the page the deadline sent you to.
///
/// A shopper arrives here by tapping a card whose whole point is a clock
/// reading down. Landing on a grid with no clock drops the one thing that
/// brought them: the offer still has an end, and the page they came from said
/// so in four boxes.
///
/// The strip form rather than the panel: four labelled cells need a block's
/// worth of width and this is a header row, not a card.
///
/// Draws nothing when there is no live sale -- which is most of the time, since
/// this screen is also "Shop All Deals" and reachable when no flash sale is
/// running at all.
class _SaleDeadline extends StatelessWidget {
  const _SaleDeadline();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: CatalogStore.instance.flashSale,
      builder: (context, _) {
        final sale = CatalogStore.instance.flashSale.value;
        if (sale == null || sale.items.isEmpty) {
          return const SizedBox.shrink();
        }
        // A clock reading zeros advertises an offer that has stopped, the same
        // reason the card on the home page removes itself.
        if (sale.hasEndedAt(DateTime.now())) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt, size: 20, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                // The same words and the same red as the card that sent them
                // here, so the page reads as the sale rather than as a
                // different screen that happens to list it.
                'Flash Sales',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              SaleCountdown(endsAt: sale.endsAt, style: CountdownStyle.strip),
            ],
          ),
        );
      },
    );
  }
}

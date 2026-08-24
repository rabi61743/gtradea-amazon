import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/search_models.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/result_card.dart';
import '../widgets/search_field.dart';

/// Results for a query, from the catalogue search endpoint.
///
/// Every control on this screen changes the request rather than filtering what
/// already came back. That is the whole design rule here: the server holds
/// millions of rows and returns a page of them, so a filter applied locally
/// would narrow one page and quietly claim there was nothing else.
///
/// It is also why there is no rating or in-stock filter. The endpoint parses
/// `q`, `category`, `min_price`, `max_price` and `sort`, and nothing else --
/// offering a control the server ignores is worse than not offering it.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key, required this.query, this.categoryCid});

  final String query;

  /// Set when the search was started from inside a department.
  final String? categoryCid;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.query);

  late String _query = widget.query;
  FilterSelection _selection = {};
  ProductSort _sort = ProductSort.relevance;

  List<Product> _results = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  ApiError? _error;

  /// Guards against an older request landing after a newer one and overwriting
  /// it. Typing quickly makes that happen constantly.
  int _generation = 0;

  static const _pageSize = 24;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _selectedCount =>
      _selection.values.fold(0, (sum, options) => sum + options.length);

  /// The price window the chosen band means, or nulls for "any".
  (num?, num?) get _priceWindow {
    final chosen = _selection[_priceGroup] ?? const <String>{};
    if (chosen.isEmpty) return (null, null);
    num? low;
    num? high;
    for (final label in chosen) {
      final band = _priceBands[label];
      if (band == null) continue;
      // Several bands selected means the union of them, which is the widest
      // window -- picking "under 500" and "over 10,000" should not return
      // nothing.
      if (band.$1 != null) low = low == null ? band.$1 : _min(low, band.$1!);
      if (band.$2 == null) {
        high = null;
      } else if (high != null || low == null) {
        high = high == null ? band.$2 : _max(high, band.$2!);
      } else {
        high = band.$2;
      }
    }
    if (chosen.any((c) => _priceBands[c]?.$2 == null)) high = null;
    return (low, high);
  }

  static num _min(num a, num b) => a < b ? a : b;
  static num _max(num a, num b) => a > b ? a : b;

  Future<void> _run() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _exhausted = false;
    });

    final (minPrice, maxPrice) = _priceWindow;
    try {
      final products = await CatalogRepository.instance.search(
        query: _query,
        categoryCid: widget.categoryCid,
        minPrice: minPrice,
        maxPrice: maxPrice,
        sort: _sort,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = products;
        _loading = false;
        _exhausted = products.length < _pageSize;
      });
    } on ApiError catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The next page, appended.
  ///
  /// Worth having rather than a single fixed page: search returns 24 rows and
  /// a shopper who scrolls to the bottom of them has told you the first 24 were
  /// not what they wanted.
  /// Asks for the next page once the frame that noticed is over.
  ///
  /// The scroll notification arrives during layout, where setState is illegal.
  /// The guard is set synchronously so a second notification in the same frame
  /// cannot start a duplicate request; only the visible part waits.
  void _requestMore() {
    if (_loadingMore || _exhausted || _loading || _error != null) return;
    _loadingMore = true;
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
      final more = await CatalogRepository.instance.search(
        query: _query,
        categoryCid: widget.categoryCid,
        minPrice: minPrice,
        maxPrice: maxPrice,
        sort: _sort,
        pageSize: _pageSize,
        offset: _results.length,
      );
      if (!mounted || generation != _generation) return;
      // The feed can repeat a row across pages when the ordering is not
      // strictly total. Showing the same product twice reads as a bug.
      final seen = _results.map((p) => p.numIid).toSet();
      final fresh = more.where((p) => seen.add(p.numIid)).toList(growable: false);
      setState(() {
        _results = [..._results, ...fresh];
        _loadingMore = false;
        _exhausted = more.length < _pageSize;
      });
    } on ApiError {
      if (!mounted || generation != _generation) return;
      // Silent: the results already on screen are still good, and an error
      // banner under them would suggest otherwise.
      setState(() {
        _loadingMore = false;
        _exhausted = true;
      });
    }
  }

  void _search(String query) {
    final trimmed = query.trim();
    if (trimmed == _query) return;
    setState(() => _query = trimmed);
    unawaited(_run());
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<FilterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(
        groups: const [
          FilterGroup(label: _priceGroup, options: _priceLabels),
        ],
        initial: _selection,
        // The count comes back with the results, not before them: only the
        // server knows how many rows match, and guessing from the page on
        // screen would be a number made up on the device.
        matchCount: null,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _selection = result);
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
            for (final option in ProductSort.values)
              RadioGroup<ProductSort>(
                groupValue: _sort,
                onChanged: (value) => Navigator.of(sheetContext).pop(value),
                child: RadioListTile<ProductSort>(
                  value: option,
                  title: Text(option.label),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SearchField(
          controller: _controller,
          autofocus: false,
          onSubmitted: _search,
        ),
        titleSpacing: 0,
      ),
      body: Column(
        children: [
          _FilterBar(
            selectedCount: _selectedCount,
            sortLabel: _sort.label,
            onFilters: _openFilters,
            onSort: _openSort,
            onClear: _selectedCount == 0
                ? null
                : () {
                    setState(() => _selection = {});
                    unawaited(_run());
                  },
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LoadFailed(
            message: error.isNetwork
                ? 'No connection. Check your network and try again.'
                : error.message,
            onRetry: _run,
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return _EmptyResults(
        query: _query,
        hasFilters: _selectedCount > 0,
        onClear: () {
          setState(() => _selection = {});
          unawaited(_run());
        },
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // A screen's height from the end, so the next page is usually there by
        // the time the shopper reaches it.
        if (notification.metrics.extentAfter < 600) _requestMore();
        return false;
      },
      child: ListView.builder(
        itemCount: _results.length + 1,
        itemBuilder: (context, i) {
          if (i == _results.length) return _Footer(loading: _loadingMore);
          final product = _results[i];
          return ResultCard(
            result: toSearchResult(product),
            onTap: () => openProduct(context, product),
          );
        },
      ),
    );
  }
}

/// The price bands offered, and the window each one means.
///
/// Bands rather than a slider: a slider needs a maximum, and this catalogue has
/// no meaningful one -- an industrial machine and a phone case are in the same
/// index.
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

class _Footer extends StatelessWidget {
  const _Footer({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading) return const SizedBox(height: 24);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({
    required this.query,
    required this.hasFilters,
    required this.onClear,
  });

  final String query;
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
            Icon(Icons.search_off,
                size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              // Naming the query matters: it is how someone spots the typo
              // that caused this.
              query.isEmpty
                  ? 'Nothing matches these filters'
                  : 'No results for "$query"',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              hasFilters
                  ? 'Try removing a filter to widen the search.'
                  : 'Check the spelling, or try a broader word.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onClear,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

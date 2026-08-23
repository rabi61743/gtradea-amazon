import 'package:flutter/material.dart';

import '../data/search_content.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/result_card.dart';
import '../widgets/search_field.dart';

/// Results for a query: a filter bar over a list of comparable rows.
///
/// The filtering here runs against placeholder data and is intentionally
/// simple -- it exists so the bar, the sheet and the empty state are real
/// rather than decorative. A backend replaces [_matching] and nothing above it
/// changes.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key, required this.query});

  final String query;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.query);

  FilterSelection _selection = {};
  _Sort _sort = _Sort.relevance;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _selectedCount =>
      _selection.values.fold(0, (sum, options) => sum + options.length);

  /// Placeholder matching over the rating and delivery groups -- enough to
  /// prove the bar, the sheet and the empty state are wired end to end.
  ///
  /// Options within a group are OR, groups are AND, which is what shoppers
  /// expect: picking two ratings widens, adding a delivery rule narrows.
  List<SearchResult> _matching(FilterSelection selection) {
    return SearchContent.results.where((result) {
      final ratings = selection['Customer rating'] ?? const <String>{};
      if (ratings.isNotEmpty) {
        final matches = ratings.any((option) => switch (option) {
              '4★ and above' => result.rating >= 4,
              '3★ and above' => result.rating >= 3,
              '2★ and above' => result.rating >= 2,
              'Unrated' => result.rating == 0,
              _ => true,
            });
        if (!matches) return false;
      }

      final delivery = selection['Delivery'] ?? const <String>{};
      if (delivery.isNotEmpty) {
        final matches = delivery.any((option) => switch (option) {
              'Free delivery' => result.freeDelivery,
              _ => true,
            });
        if (!matches) return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<SearchResult> get _visible {
    final list = [..._matching(_selection)];
    switch (_sort) {
      case _Sort.relevance:
        break;
      case _Sort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _Sort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _Sort.rating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
    }
    return list;
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<FilterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(
        groups: SearchContent.filters,
        initial: _selection,
        matchCount: (selection) => _matching(selection).length,
      ),
    );
    if (result != null) setState(() => _selection = result);
  }

  Future<void> _openSort() async {
    final chosen = await showModalBottomSheet<_Sort>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in _Sort.values)
              RadioGroup<_Sort>(
                groupValue: _sort,
                onChanged: (value) => Navigator.of(sheetContext).pop(value),
                child: RadioListTile<_Sort>(
                  value: option,
                  title: Text(option.label),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _sort = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _visible;

    return Scaffold(
      body: Column(
        children: [
          SearchField(
            controller: _controller,
            readOnly: true,
            onTap: () => Navigator.of(context).maybePop(),
            onImageSearch: () {},
            trailing: IconButton(
              icon: Badge.count(
                count: 0,
                isLabelVisible: true,
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  color: Colors.white,
                ),
              ),
              tooltip: 'Cart',
              onPressed: () {},
            ),
          ),
          _FilterBar(
            selectedCount: _selectedCount,
            sortLabel: _sort.label,
            onFilters: _openFilters,
            onSort: _openSort,
            onClear: _selectedCount == 0
                ? null
                : () => setState(() => _selection = {}),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Text(
                  '${results.length} result${results.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    'for "${widget.query}"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? _EmptyResults(onClear: () => setState(() => _selection = {}))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) =>
                        ResultCard(result: results[i], onTap: () {}),
                  ),
          ),
        ],
      ),
    );
  }
}

enum _Sort {
  relevance('Relevance'),
  priceLow('Price: low to high'),
  priceHigh('Price: high to low'),
  rating('Customer rating');

  const _Sort(this.label);
  final String label;
}

/// Filters and sort as two explicit buttons, not the reference row of
/// attribute dropdowns.
///
/// Those dropdowns push the customer to filter one attribute at a time and
/// hide how many are active. One Filters button carrying a count says the same
/// thing in less space and survives a filter set that grows.
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
  const _EmptyResults({required this.onClear});

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
              'Nothing matches these filters',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Try removing one to widen the search.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onClear,
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }
}

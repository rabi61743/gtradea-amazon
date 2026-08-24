import 'package:flutter/material.dart';

import '../data/search_models.dart';

/// Selected options, keyed by filter-group label.
typedef FilterSelection = Map<String, Set<String>>;

/// Full-height filter sheet.
///
/// Two departures from the reference, both about not losing the customer's
/// work: it edits a *copy* so dismissing the sheet cannot silently apply
/// half-made choices, and Apply carries the resulting count so the effect is
/// visible before committing to it.
///
/// Groups are labelled. The reference lists bare numbers under "Popular
/// Filters" -- a column reading 5, 4, Non-Rated, 1, 3, 2 says nothing about
/// what it filters, and is not even in order.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.groups,
    required this.initial,
    this.matchCount,
  });

  final List<FilterGroup> groups;
  final FilterSelection initial;

  /// How many results a given selection would leave, so Apply can say so.
  ///
  /// Null when only the server can answer that. Apply then says what it does
  /// rather than promising a count nobody on this device knows.
  final int Function(FilterSelection selection)? matchCount;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final FilterSelection _draft = {
    for (final entry in widget.initial.entries) entry.key: {...entry.value},
  };

  int get _selectedCount =>
      _draft.values.fold(0, (sum, options) => sum + options.length);

  void _toggle(String group, String option) {
    setState(() {
      final set = _draft.putIfAbsent(group, () => <String>{});
      if (!set.remove(option)) set.add(option);
      if (set.isEmpty) _draft.remove(group);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = widget.matchCount?.call(_draft);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    'Filters',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_selectedCount > 0)
                  Text(
                    '$_selectedCount selected',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final group in widget.groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      group.label,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in group.options)
                          FilterChip(
                            label: Text(option),
                            selected:
                                _draft[group.label]?.contains(option) ?? false,
                            onSelected: (_) => _toggle(group.label, option),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _selectedCount == 0 ? null : () => setState(_draft.clear),
                    child: const Text('Clear all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    // Null when only the server can count. Promising a number
                    // the device worked out from one page would be a guess
                    // dressed as a fact.
                    child: Text(switch (matches) {
                      null => 'Show results',
                      0 => 'No matches',
                      1 => 'Show 1 result',
                      final n => 'Show $n results',
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

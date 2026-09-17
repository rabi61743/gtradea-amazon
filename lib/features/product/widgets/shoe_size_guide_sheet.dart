import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// One row of the standard shoe conversion chart, keyed by EU/China size --
/// the numbering 1688 shoe listings use ("36", "37.5", "42 (sneaker size)").
@immutable
class ShoeSize {
  const ShoeSize({
    required this.eu,
    required this.uk,
    required this.usMen,
    required this.usWomen,
  });

  final double eu;
  final double uk;
  final double usMen;
  final double usWomen;

  /// Foot length for this size, in centimetres, by the Chinese sizing rule
  /// sellers here size to: size = foot length (cm) x 2 - 10.
  double get footCm => (eu + 10) / 2;
}

/// The standard EU-to-UK/US chart. Approximate by nature: brands differ by
/// half a size either way, which the sheet says.
const kShoeChart = <ShoeSize>[
  ShoeSize(eu: 35, uk: 2.5, usMen: 3.5, usWomen: 5),
  ShoeSize(eu: 36, uk: 3.5, usMen: 4.5, usWomen: 6),
  ShoeSize(eu: 37, uk: 4, usMen: 5, usWomen: 6.5),
  ShoeSize(eu: 38, uk: 5, usMen: 6, usWomen: 7.5),
  ShoeSize(eu: 39, uk: 6, usMen: 7, usWomen: 8.5),
  ShoeSize(eu: 40, uk: 6.5, usMen: 7.5, usWomen: 9),
  ShoeSize(eu: 41, uk: 7.5, usMen: 8.5, usWomen: 10),
  ShoeSize(eu: 42, uk: 8, usMen: 9, usWomen: 10.5),
  ShoeSize(eu: 43, uk: 9, usMen: 10, usWomen: 11.5),
  ShoeSize(eu: 44, uk: 9.5, usMen: 10.5, usWomen: 12),
  ShoeSize(eu: 45, uk: 10.5, usMen: 11.5, usWomen: 13),
  ShoeSize(eu: 46, uk: 11, usMen: 12, usWomen: 13.5),
  ShoeSize(eu: 47, uk: 12, usMen: 13, usWomen: 14.5),
  ShoeSize(eu: 48, uk: 12.5, usMen: 13.5, usWomen: 15),
];

/// Shoe sizing, for a product's own sizes.
abstract final class ShoeSizing {
  static final _footwear = RegExp(
    r'shoe|sneaker|boot|sandal|slipper|loafer|footwear|flip[- ]?flop|'
    r'high heel|pumps|clog|espadrille|trainer|鞋|靴',
    caseSensitive: false,
  );

  /// Whether a product in [category] is footwear. The category, not the size
  /// labels, decides: trousers are sized 28-36 too.
  static bool isFootwear(String? category) =>
      category != null && _footwear.hasMatch(category);

  /// The EU size a seller's label names -- "36", "37.5", "42 (sneaker size)",
  /// "EU 40" -- or null when it names none in the chart's range.
  static double? euOf(String label) {
    final m = RegExp(r'(\d{2}(?:\.5)?)').firstMatch(label);
    if (m == null) return null;
    final v = double.parse(m.group(1)!);
    return (v >= kShoeChart.first.eu && v <= kShoeChart.last.eu) ? v : null;
  }

  /// The chart row for an EU size; a half size sits halfway between its
  /// neighbours.
  static ShoeSize? rowFor(double eu) {
    final lower = kShoeChart.lastWhere((s) => s.eu <= eu);
    if (lower.eu == eu) return lower;
    final i = kShoeChart.indexOf(lower);
    if (i + 1 >= kShoeChart.length) return null;
    final upper = kShoeChart[i + 1];
    double mid(double a, double b) => ((a + b) / 2 * 2).round() / 2;
    return ShoeSize(
      eu: eu,
      uk: mid(lower.uk, upper.uk),
      usMen: mid(lower.usMen, upper.usMen),
      usWomen: mid(lower.usWomen, upper.usWomen),
    );
  }
}

/// The Size guide for a shoe: this product's own sizes, each with its UK and
/// US equivalents and the foot length it fits, and how to measure a foot.
///
/// The sizes are the seller's, from the product's own options. The
/// conversions and foot lengths are a standard chart, not measurements the
/// seller published -- the catalogue has none -- and the sheet says so.
class ShoeSizeGuideSheet extends StatefulWidget {
  const ShoeSizeGuideSheet({super.key, required this.sizes, this.initialSize});

  /// The product's size labels, in the seller's order.
  final List<String> sizes;
  final String? initialSize;

  static const accent = AppColors.commerceOrange;

  static Future<void> show(
    BuildContext context, {
    required List<String> sizes,
    String? initialSize,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.94,
        child: ShoeSizeGuideSheet(sizes: sizes, initialSize: initialSize),
      ),
    );
  }

  @override
  State<ShoeSizeGuideSheet> createState() => _ShoeSizeGuideSheetState();
}

class _ShoeSizeGuideSheetState extends State<ShoeSizeGuideSheet> {
  bool _inches = false;

  /// This product's sizes the chart can place, once each, smallest first. A
  /// label can carry a colour too ("Black / 36"), so sizes are matched by
  /// number and repeats across colours collapse.
  late final List<({String label, ShoeSize row})> _rows = () {
    final byEu = <double, ({String label, ShoeSize row})>{};
    for (final label in widget.sizes) {
      final eu = ShoeSizing.euOf(label);
      if (eu == null || byEu.containsKey(eu)) continue;
      final row = ShoeSizing.rowFor(eu);
      if (row != null) byEu[eu] = (label: label, row: row);
    }
    return byEu.values.toList()..sort((a, b) => a.row.eu.compareTo(b.row.eu));
  }();

  late int _selected = () {
    final eu = widget.initialSize == null
        ? null
        : ShoeSizing.euOf(widget.initialSize!);
    final i = _rows.indexWhere((r) => r.row.eu == eu);
    return i >= 0 ? i : 0;
  }();

  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String _foot(double cm) =>
      _inches ? (cm / 2.54).toStringAsFixed(1) : _num(cm);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = _inches ? 'in' : 'cm';

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 60,
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('size-guide-close'),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Size guide',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 24,
                          height: 3,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        "This product's sizes don't follow the standard shoe "
                        'numbering, so there is no chart for them. Check the '
                        "seller's size chart in the product photos.",
                        key: const ValueKey('shoe-guide-empty'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    key: const ValueKey('shoe-guide-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Switch to',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          _UnitSwitch(
                            inches: _inches,
                            onChanged: (v) => setState(() => _inches = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sizes of this product (EU)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < _rows.length; i++)
                            _ShoeChip(
                              label: _num(_rows[i].row.eu),
                              selected: i == _selected,
                              onTap: () => setState(() => _selected = i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _Summary(
                        row: _rows[_selected].row,
                        foot: '${_foot(_rows[_selected].row.footCm)} $unit',
                        num: _num,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.info_outline,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "The sizes are this product's. UK, US and foot "
                              'lengths are a standard conversion, not the '
                              "seller's own measurements -- brands can differ "
                              'by half a size. Check the size chart in the '
                              'product photos too.',
                              key: const ValueKey('shoe-guide-notice'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            key: const ValueKey('shoe-size-table'),
                            headingRowColor: WidgetStatePropertyAll(
                              theme.colorScheme.surfaceContainerHighest,
                            ),
                            columnSpacing: 22,
                            horizontalMargin: 16,
                            columns: [
                              for (final h in [
                                'EU',
                                'UK',
                                'US Men',
                                'US Women',
                                'Foot length ($unit)',
                              ])
                                DataColumn(
                                  label: Text(
                                    h,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                            rows: [
                              for (var i = 0; i < _rows.length; i++)
                                DataRow(
                                  color: i == _selected
                                      ? WidgetStatePropertyAll(
                                          theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                        )
                                      : null,
                                  onSelectChanged: (_) =>
                                      setState(() => _selected = i),
                                  cells: [
                                    DataCell(Text(_num(_rows[i].row.eu))),
                                    DataCell(Text(_num(_rows[i].row.uk))),
                                    DataCell(Text(_num(_rows[i].row.usMen))),
                                    DataCell(Text(_num(_rows[i].row.usWomen))),
                                    DataCell(Text(_foot(_rows[i].row.footCm))),
                                  ],
                                ),
                            ],
                            showCheckboxColumn: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'How to measure your foot',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final (i, step) in const [
                        'Stand on a sheet of paper with your heel against a '
                            'wall.',
                        'Mark the tip of your longest toe.',
                        'Measure from the wall to the mark.',
                        'Pick the size whose foot length is the same or just '
                            'longer. Between two sizes, take the larger.',
                      ].indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: ShoeSizeGuideSheet.accent,
                                  ),
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: ShoeSizeGuideSheet.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  step,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
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

/// The chosen size, at a glance.
class _Summary extends StatelessWidget {
  const _Summary({required this.row, required this.foot, required this.num});

  final ShoeSize row;
  final String foot;
  final String Function(double) num;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, String value, {Key? key}) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            key: key,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: ShoeSizeGuideSheet.accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Container(
      key: const ValueKey('shoe-guide-summary'),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ShoeSizeGuideSheet.accent.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          cell('Foot length', foot, key: const ValueKey('shoe-guide-foot')),
          cell('UK', num(row.uk)),
          cell('US Men', num(row.usMen)),
          cell('US Women', num(row.usWomen)),
        ],
      ),
    );
  }
}

class _ShoeChip extends StatelessWidget {
  const _ShoeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('shoe-size-$label'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: const BoxConstraints(minWidth: 60),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
      ),
    );
  }
}

class _UnitSwitch extends StatelessWidget {
  const _UnitSwitch({required this.inches, required this.onChanged});

  final bool inches;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget half(String text, bool value) {
      final on = inches == value;
      return InkWell(
        key: ValueKey('shoe-unit-${value ? 'in' : 'cm'}'),
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: on ? theme.colorScheme.onSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              color: on
                  ? theme.colorScheme.surface
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [half('IN', true), half('CM', false)],
      ),
    );
  }
}

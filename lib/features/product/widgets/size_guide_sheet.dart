import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

import 'shoe_size_guide_sheet.dart';
import 'size_recommendation.dart';

/// One size in the general chart: body measurements to fit, and the garment's
/// own measurements, both in centimetres.
@immutable
class StandardSize {
  const StandardSize({
    required this.label,
    required this.chest,
    required this.waist,
    required this.hips,
    required this.height,
    required this.shoulder,
    required this.garmentChest,
    required this.length,
    required this.sleeve,
  });

  final String label;

  /// Body ranges, in centimetres: `(from, to)`.
  final (double, double) chest;
  final (double, double) waist;
  final (double, double) hips;
  final (double, double) height;

  /// A regular-fit top of this size, flat measurements in centimetres.
  final double shoulder;
  final double garmentChest;
  final double length;
  final double sleeve;
}

/// A general international size chart for regular-fit tops.
///
/// **Not any product's own measurements.** The catalogue publishes sizes as
/// labels only -- "S", "M", sometimes a weight range in brackets -- and no
/// chest, length or sleeve figures; sellers who have a chart put it in their
/// product photos. So the guide shows these standard figures, and says on its
/// face that they are a general guide and the seller's sizes may differ.
const List<StandardSize> kStandardSizes = [
  StandardSize(
    label: 'XS',
    chest: (82, 87),
    waist: (68, 73),
    hips: (84, 89),
    height: (160, 165),
    shoulder: 42,
    garmentChest: 92,
    length: 66,
    sleeve: 19,
  ),
  StandardSize(
    label: 'S',
    chest: (88, 93),
    waist: (74, 79),
    hips: (90, 95),
    height: (165, 170),
    shoulder: 44,
    garmentChest: 98,
    length: 68,
    sleeve: 20,
  ),
  StandardSize(
    label: 'M',
    chest: (94, 99),
    waist: (80, 85),
    hips: (96, 101),
    height: (170, 175),
    shoulder: 46,
    garmentChest: 104,
    length: 70,
    sleeve: 21,
  ),
  StandardSize(
    label: 'L',
    chest: (100, 105),
    waist: (86, 91),
    hips: (102, 107),
    height: (175, 180),
    shoulder: 48,
    garmentChest: 110,
    length: 72,
    sleeve: 22,
  ),
  StandardSize(
    label: 'XL',
    chest: (106, 111),
    waist: (92, 97),
    hips: (108, 113),
    height: (180, 185),
    shoulder: 50,
    garmentChest: 116,
    length: 74,
    sleeve: 23,
  ),
  StandardSize(
    label: 'XXL',
    chest: (112, 117),
    waist: (98, 103),
    hips: (114, 119),
    height: (185, 190),
    shoulder: 52,
    garmentChest: 122,
    length: 76,
    sleeve: 24,
  ),
  StandardSize(
    label: '3XL',
    chest: (118, 123),
    waist: (104, 109),
    hips: (120, 125),
    height: (188, 193),
    shoulder: 54,
    garmentChest: 128,
    length: 78,
    sleeve: 25,
  ),
];

/// The "Size guide" control shown beside a product's sizes.
///
/// Opens the size guide. For footwear, by the product's category, that is
/// [ShoeSizeGuideSheet] on the product's own sizes; otherwise
/// [SizeGuideSheet]. It changes nothing: the size picked stays picked.
class SizeGuideButton extends StatelessWidget {
  const SizeGuideButton({
    super.key,
    this.initialSize,
    this.category,
    this.sizes = const [],
  });

  /// A size label to open the guide on, when the shopper has one chosen.
  final String? initialSize;

  /// The product's category name, which decides whether this is a shoe.
  final String? category;

  /// The product's own size labels.
  final List<String> sizes;

  void _open(BuildContext context) {
    if (ShoeSizing.isFootwear(category)) {
      ShoeSizeGuideSheet.show(context, sizes: sizes, initialSize: initialSize);
    } else {
      SizeGuideSheet.show(context, initialSize: initialSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: 'Size guide',
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const ValueKey('size-guide-button'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.straighten,
                  size: 14,
                  color: SizeGuideSheet.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Size guide',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: SizeGuideSheet.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The size guide: units, a standard size to look at, the body and garment
/// figures with that size's measurements on them, and the full chart below.
class SizeGuideSheet extends StatefulWidget {
  const SizeGuideSheet({super.key, this.initialSize});

  final String? initialSize;

  /// The app's Commerce Orange, for marks, text, lines and edges -- never
  /// as a fill behind anything.
  static const accent = AppColors.commerceOrange;

  /// Opens the guide as a tall sheet -- phone width on a tablet or desktop --
  /// that closes on the back arrow, a swipe down, or a tap outside.
  static Future<void> show(BuildContext context, {String? initialSize}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.94,
        child: SizeGuideSheet(initialSize: initialSize),
      ),
    );
  }

  /// The standard size a seller's label best corresponds to, or M. Seller
  /// labels carry notes -- "M [45-50 kg]", "XL recommendation" -- so the
  /// first word is what is matched.
  static int indexFor(String? label) {
    final word = (label ?? '').trim().split(RegExp(r'[\s\[(【]')).first;
    final upper = word.toUpperCase().replaceAll('XXXL', '3XL');
    final i = kStandardSizes.indexWhere((s) => s.label == upper);
    return i >= 0 ? i : 2;
  }

  @override
  State<SizeGuideSheet> createState() => _SizeGuideSheetState();
}

enum _Unit { inches, cm }

enum _Chart { body, product }

class _SizeGuideSheetState extends State<SizeGuideSheet> {
  _Unit _unit = _Unit.cm;
  _Chart _chart = _Chart.product;
  late int _size = SizeGuideSheet.indexFor(widget.initialSize);

  /// 0 for the size guide, 1 for the size recommendation.
  int _tab = 0;

  String _n(double cm) {
    if (_unit == _Unit.cm) {
      return cm == cm.roundToDouble() ? cm.toStringAsFixed(0) : '$cm';
    }
    return (cm / 2.54).toStringAsFixed(1);
  }

  String _range((double, double) r) => '${_n(r.$1)}-${_n(r.$2)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = kStandardSizes[_size];

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          _Header(
            onClose: () => Navigator.of(context).maybePop(),
            tab: _tab,
            onTab: (t) => setState(() => _tab = t),
          ),
          const Divider(height: 1),
          if (_tab == 1)
            Expanded(
              child: SizeRecommendationTab(
                // From the suggestion to the guide, on that size.
                onViewSize: (i) => setState(() {
                  _size = i;
                  _tab = 0;
                }),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _Band(
                    child: Row(
                      children: [
                        Text('Switch to', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        _UnitToggle(
                          unit: _unit,
                          onChanged: (u) => setState(() => _unit = u),
                        ),
                      ],
                    ),
                  ),
                  const _Gap(),
                  _Band(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Size displayed: Standard size',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (var i = 0; i < kStandardSizes.length; i++)
                              _SizeChip(
                                label: kStandardSizes[i].label,
                                selected: i == _size,
                                onTap: () => setState(() => _size = i),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _Figures(
                          chest: _range(size.chest),
                          waist: _range(size.waist),
                          height: _range(size.height),
                          shoulder: _n(size.shoulder),
                          garmentChest: _n(size.garmentChest),
                          length: _n(size.length),
                          sleeve: _n(size.sleeve),
                        ),
                        const SizedBox(height: 12),
                        _Notice(),
                      ],
                    ),
                  ),
                  const _Gap(),
                  _Band(
                    child: Column(
                      children: [
                        _ChartTabs(
                          chart: _chart,
                          onChanged: (c) => setState(() => _chart = c),
                        ),
                        const SizedBox(height: 12),
                        _Table(
                          chart: _chart,
                          selected: _size,
                          cell: _n,
                          range: _range,
                          unit: _unit == _Unit.cm ? 'cm' : 'in',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onClose,
    required this.tab,
    required this.onTab,
  });

  final VoidCallback onClose;
  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget label(String text, int index) {
      final on = tab == index;
      return InkWell(
        key: ValueKey('size-tab-$index'),
        onTap: () => onTab(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shrinks a little rather than cut "Size recommendation" short
              // on a phone.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 24,
                height: 3,
                decoration: BoxDecoration(
                  color: on ? theme.colorScheme.onSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 60,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('size-guide-close'),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            tooltip: 'Close',
            onPressed: onClose,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Flexible(child: label('Size guide', 0)),
                Flexible(child: label('Size recommendation', 1)),
              ],
            ),
          ),
          // Balances the back arrow, so the tabs sit in the middle.
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// A white band of the page, separated from the next by a grey gap.
class _Band extends StatelessWidget {
  const _Band({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), child: child);
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => Container(
    height: 8,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
  );
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.unit, required this.onChanged});

  final _Unit unit;
  final ValueChanged<_Unit> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget half(String text, _Unit value) {
      final on = unit == value;
      return InkWell(
        key: ValueKey('unit-${value.name}'),
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
        children: [half('IN', _Unit.inches), half('CM', _Unit.cm)],
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({
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
      key: ValueKey('guide-size-$label'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: const BoxConstraints(minWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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

/// The body and garment drawings with the chosen size's figures on them.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.chest,
    required this.waist,
    required this.height,
    required this.shoulder,
    required this.garmentChest,
    required this.length,
    required this.sleeve,
  });

  final String chest;
  final String waist;
  final String height;
  final String shoulder;
  final String garmentChest;
  final String length;
  final String sleeve;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = w * 1.02;
        Offset at(double x, double y) => Offset(w * x, h * y);

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _FiguresPainter())),
              _pill(at(0.215, 0.33), chest, 'body-chest'),
              _pill(at(0.215, 0.46), waist, 'body-waist'),
              _pill(at(0.42, 0.8), height, 'body-height'),
              _pill(at(0.72, 0.39), shoulder, 'garment-shoulder'),
              _pill(at(0.72, 0.58), garmentChest, 'garment-chest'),
              _pill(at(0.9, 0.525), length, 'garment-length'),
              _pill(at(0.585, 0.49), sleeve, 'garment-sleeve'),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(Offset centre, String text, String key) {
    return Positioned(
      left: centre.dx,
      top: centre.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Container(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SizeGuideSheet.accent, width: 2),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF222222),
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Line drawings in the reference's manner: a grey outline figure with orange
/// measurement rings and a height rule, and a flat long-sleeve top with orange
/// measurement lines.
class _FiguresPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final orange = Paint()
      ..color = SizeGuideSheet.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final dashed = Paint()
      ..color = SizeGuideSheet.accent
      ..strokeWidth = 1.2;

    // --- The body, on the left third. -------------------------------------
    paintBodyFigure(canvas, w: w, h: h, cx: w * 0.215, ruleX: w * 0.42);

    // --- The garment, on the right. ----------------------------------------
    // Drawn a little under full size and with its sleeves hanging close, so
    // its measurement pills and the length rule all sit inside the sheet.
    final gx = w * 0.72;
    const s = 0.78;
    double g(double dx) => gx + w * dx * s;
    final top = h * 0.36;
    final shirt = Path()
      ..moveTo(g(-0.07), top)
      ..quadraticBezierTo(gx, top + h * 0.03, g(0.07), top)
      ..lineTo(g(0.15), top + h * 0.03)
      ..lineTo(g(0.21), top + h * 0.31)
      ..lineTo(g(0.16), top + h * 0.33)
      ..lineTo(g(0.13), top + h * 0.13)
      ..lineTo(g(0.13), top + h * 0.33)
      ..lineTo(g(-0.13), top + h * 0.33)
      ..lineTo(g(-0.13), top + h * 0.13)
      ..lineTo(g(-0.16), top + h * 0.33)
      ..lineTo(g(-0.21), top + h * 0.31)
      ..lineTo(g(-0.15), top + h * 0.03)
      ..close();
    canvas.drawPath(shirt, outline);

    // Shoulder, chest, sleeve and length.
    canvas.drawLine(
      Offset(g(-0.15), top + h * 0.03),
      Offset(g(0.15), top + h * 0.03),
      orange,
    );
    canvas.drawLine(
      Offset(g(-0.13), top + h * 0.22),
      Offset(g(0.13), top + h * 0.22),
      orange,
    );
    canvas.drawLine(
      Offset(g(-0.15), top + h * 0.03),
      Offset(g(-0.21), top + h * 0.31),
      orange,
    );
    canvas.drawLine(
      Offset(w * lengthRuleX, top),
      Offset(w * lengthRuleX, top + h * 0.33),
      orange,
    );
    dashLine(
      canvas,
      Offset(g(0.07), top),
      Offset(w * lengthRuleX, top),
      dashed,
    );
  }

  /// Where the garment's length rule stands, clear of its right sleeve.
  static const lengthRuleX = 0.94;

  @override
  bool shouldRepaint(_FiguresPainter old) => false;
}

/// Where the numbers come from, said where they are read.
class _Notice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
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
            'General guide. These are standard measurements, not this '
            "product's -- this seller's sizes may differ. Many sellers show "
            'their own size chart in the product photos.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartTabs extends StatelessWidget {
  const _ChartTabs({required this.chart, required this.onChanged});

  final _Chart chart;
  final ValueChanged<_Chart> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tab(String text, _Chart value) {
      final on = chart == value;
      return Expanded(
        child: InkWell(
          key: ValueKey('chart-${value.name}'),
          onTap: () => onChanged(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: on
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 24,
                  height: 3,
                  decoration: BoxDecoration(
                    color: on
                        ? theme.colorScheme.onSurface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('Body chart', _Chart.body),
        tab('Product chart', _Chart.product),
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.chart,
    required this.selected,
    required this.cell,
    required this.range,
    required this.unit,
  });

  final _Chart chart;
  final int selected;
  final String Function(double) cell;
  final String Function((double, double)) range;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = chart == _Chart.body;
    final headers = body
        ? ['Label size', 'Chest', 'Waist', 'Hips', 'Height']
        : ['Label size', 'Shoulder', 'Chest', 'Length', 'Sleeve'];

    List<String> rowFor(StandardSize s) => body
        ? [
            s.label,
            range(s.chest),
            range(s.waist),
            range(s.hips),
            range(s.height),
          ]
        : [
            s.label,
            cell(s.shoulder),
            cell(s.garmentChest),
            cell(s.length),
            cell(s.sleeve),
          ];

    TextStyle? style(bool head) => theme.textTheme.bodyMedium?.copyWith(
      fontWeight: head ? FontWeight.w500 : FontWeight.w400,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: ValueKey('size-table-${chart.name}'),
          headingRowColor: WidgetStatePropertyAll(
            theme.colorScheme.surfaceContainerHighest,
          ),
          columnSpacing: 24,
          horizontalMargin: 16,
          columns: [
            for (final h in headers)
              DataColumn(
                label: Text(
                  h == 'Label size' ? h : '$h ($unit)',
                  style: style(true),
                ),
              ),
          ],
          rows: [
            for (var i = 0; i < kStandardSizes.length; i++)
              DataRow(
                color: i == selected
                    // A neutral tint: orange stays off backgrounds.
                    ? WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                      )
                    : null,
                cells: [
                  for (final v in rowFor(kStandardSizes[i]))
                    DataCell(Text(v, style: style(false))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The outline figure with its chest, waist and hip rings and a height rule.
///
/// Shared by the size guide's figure and the recommendation tab's
/// "How to measure" drawing, so the two are the same person. [w] scales the
/// figure's width -- it spans about 0.35 of it -- and [cx] and [ruleX] place
/// the figure's centre line and the height rule.
void paintBodyFigure(
  Canvas canvas, {
  required double w,
  required double h,
  required double cx,
  required double ruleX,
}) {
  final outline = Paint()
    ..color = const Color(0xFF9E9E9E)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;
  final orange = Paint()
    ..color = SizeGuideSheet.accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  final dashed = Paint()
    ..color = SizeGuideSheet.accent
    ..strokeWidth = 1.2;

  final head = Rect.fromCenter(
    center: Offset(cx, h * 0.07),
    width: w * 0.075,
    height: h * 0.1,
  );
  canvas.drawOval(head, outline);

  final body = Path()
    // Neck and shoulders.
    ..moveTo(cx - w * 0.02, h * 0.12)
    ..lineTo(cx - w * 0.025, h * 0.155)
    ..quadraticBezierTo(cx - w * 0.13, h * 0.17, cx - w * 0.14, h * 0.24)
    // Left arm.
    ..lineTo(cx - w * 0.165, h * 0.47)
    ..lineTo(cx - w * 0.17, h * 0.56)
    ..lineTo(cx - w * 0.145, h * 0.56)
    ..lineTo(cx - w * 0.12, h * 0.34)
    // Left side down to the hip and leg.
    ..lineTo(cx - w * 0.09, h * 0.47)
    ..lineTo(cx - w * 0.105, h * 0.62)
    ..lineTo(cx - w * 0.085, h * 0.97)
    ..lineTo(cx - w * 0.035, h * 0.97)
    ..lineTo(cx, h * 0.66)
    // Right leg and side, mirrored.
    ..lineTo(cx + w * 0.035, h * 0.97)
    ..lineTo(cx + w * 0.085, h * 0.97)
    ..lineTo(cx + w * 0.105, h * 0.62)
    ..lineTo(cx + w * 0.09, h * 0.47)
    ..lineTo(cx + w * 0.12, h * 0.34)
    ..lineTo(cx + w * 0.145, h * 0.56)
    ..lineTo(cx + w * 0.17, h * 0.56)
    ..lineTo(cx + w * 0.165, h * 0.47)
    ..lineTo(cx + w * 0.14, h * 0.24)
    ..quadraticBezierTo(cx + w * 0.13, h * 0.17, cx + w * 0.025, h * 0.155)
    ..lineTo(cx + w * 0.02, h * 0.12);
  canvas.drawPath(body, outline);

  // Chest, waist and hip rings.
  for (final (y, half) in [(0.33, 0.115), (0.46, 0.095), (0.58, 0.108)]) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * y),
        width: w * half * 2,
        height: h * 0.035,
      ),
      orange,
    );
  }

  // The height rule, with dashed ties to the crown and the floor.
  canvas.drawLine(Offset(ruleX, h * 0.02), Offset(ruleX, h * 0.97), orange);
  dashLine(canvas, Offset(cx, h * 0.02), Offset(ruleX, h * 0.02), dashed);
  dashLine(canvas, Offset(cx, h * 0.97), Offset(ruleX, h * 0.97), dashed);
}

/// A dashed line, for the ties from a figure to its measurement rule.
void dashLine(Canvas canvas, Offset from, Offset to, Paint paint) {
  const dash = 4.0;
  const gap = 3.0;
  final length = (to - from).distance;
  if (length == 0) return;
  final dir = (to - from) / length;
  for (var d = 0.0; d < length; d += dash + gap) {
    final end = (d + dash).clamp(0.0, length);
    canvas.drawLine(from + dir * d, from + dir * end, paint);
  }
}

/// The "How to measure" figure: the same person, with numbered marks for
/// bust (1), waist (2), hips (3) and height (4).
class MeasureFigure extends StatelessWidget {
  const MeasureFigure({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.62,
      child: CustomPaint(painter: _MeasurePainter()),
    );
  }
}

class _MeasurePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wide = size.width;
    final h = size.height;
    // The shared figure spans about 0.35 of its w; this fills the box.
    final w = wide * 2.6;
    final cx = wide * 0.56;
    paintBodyFigure(canvas, w: w, h: h, cx: cx, ruleX: wide * 0.06);

    void mark(Offset at, String n) {
      canvas.drawCircle(at, 9, Paint()..color = const Color(0xFF222222));
      final text = TextPainter(
        text: TextSpan(
          text: n,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, at - Offset(text.width / 2, text.height / 2));
    }

    mark(Offset(cx - w * 0.13, h * 0.33), '1');
    mark(Offset(cx + w * 0.115, h * 0.46), '2');
    mark(Offset(cx + w * 0.125, h * 0.58), '3');
    mark(Offset(wide * 0.06, h * 0.5), '4');
  }

  @override
  bool shouldRepaint(_MeasurePainter old) => false;
}

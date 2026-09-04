import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../../core/images/app_images.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;

import '../data/product_detail_content.dart';
import 'swipe_hint.dart';
import 'variant_tooltip.dart';

/// A wholesale order grid: colourways down the side, sizes across the top, a
/// quantity typed into every cell.
///
/// This is how the listings are actually sold. A two-axis offer is 21 colours
/// by 4 sizes -- 84 SKUs -- and the horizontal strip the page used before asked
/// a buyer to find each combination in a scrolling row and add it to the cart
/// on its own. Here the whole range is one table and an order is typed across
/// it in a single pass.
///
/// Only the grid is drawn from the feed: rows, columns, photographs, stock and
/// per-SKU prices all come from the record. Nothing is filled in. Where the
/// seller does not stock a combination the cell is drawn empty rather than
/// completed, because an order against a SKU that does not exist fails at the
/// supplier rather than here.
class VariantMatrixTable extends StatefulWidget {
  const VariantMatrixTable({
    super.key,
    required this.matrix,
    required this.quantities,
    required this.total,
    required this.onChanged,
    this.onImageTap,
    this.minOrder = 1,
    this.collapsedRows = 6,
  });

  final VariantMatrix matrix;

  /// What the selection costs. Worked out by the page rather than here, so the
  /// figure under the grid and the figure on the buy bar are the same figure --
  /// they were computed once, from the same wholesale price bands.
  final num total;

  /// How many of each SKU is on the order, keyed by SKU id. Held by the page
  /// rather than here so the buy bar, the cart lines and this grid cannot
  /// disagree about what is being bought.
  final Map<String, int> quantities;

  final void Function(String skuId, int quantity) onChanged;

  /// Opens the colourway's own photograph. Sellers shoot the colour rather than
  /// the colour-and-size, and at 56pt a buyer cannot tell wine red from crab
  /// green -- which is the whole decision this table is asking them to make.
  final void Function(VariantRow row)? onImageTap;

  /// The seller's minimum, counted across the whole grid. A wholesale minimum
  /// is on the order, not on each square of it.
  final int minOrder;

  /// Rows shown before "show all". A 39-colour listing is a real thing in this
  /// catalogue, and 39 rows is 39 photographs fetched and a very long page for
  /// a buyer who wanted two of them.
  final int collapsedRows;

  @override
  State<VariantMatrixTable> createState() => _VariantMatrixTableState();
}

class _VariantMatrixTableState extends State<VariantMatrixTable> {
  final _horizontal = ScrollController();

  /// How much of the right-hand fade to paint, as a 0-1 amount.
  ///
  /// A ValueNotifier rather than setState: this changes on every frame of a
  /// horizontal drag, and rebuilding a table of text fields at that rate would
  /// drop the frames the fade exists to make legible.
  final _endFade = ValueNotifier<double>(0);

  bool _expanded = false;

  /// Whether the columns run past the edge, which is the only case worth
  /// hinting at.
  bool _overflows = false;

  /// Set the first time the grid is moved sideways. The hint has done its job
  /// then, and a standing instruction to do the thing you are already doing is
  /// noise.
  bool _used = false;

  @override
  void initState() {
    super.initState();
    _horizontal.addListener(_updateFade);
    // The listener only fires on a scroll, so the first state -- does this
    // grid overflow at all -- has to be read once the columns have been laid
    // out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void didUpdateWidget(VariantMatrixTable old) {
    super.didUpdateWidget(old);
    // A different listing, or "show all" adding rows: the grid may no longer
    // run past the edge, and a hint left over would point at nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void dispose() {
    _horizontal
      ..removeListener(_updateFade)
      ..dispose();
    _endFade.dispose();
    super.dispose();
  }

  void _updateFade() {
    if (!mounted || !_horizontal.hasClients) return;
    final max = _horizontal.position.maxScrollExtent;

    final overflows = max > 0;
    final used = _used || _horizontal.offset > 4;
    if (overflows != _overflows || used != _used) {
      setState(() {
        _overflows = overflows;
        _used = used;
      });
    }

    if (max <= 0) {
      _endFade.value = 0;
      return;
    }
    // Fades out over the last 32pt, so the hint disappears as the last column
    // arrives instead of sitting over it.
    final left = max - _horizontal.offset;
    _endFade.value = (left / 32).clamp(0.0, 1.0);
  }

  int get _totalPieces =>
      widget.quantities.values.fold(0, (sum, qty) => sum + qty);

  int get _linesChosen =>
      widget.quantities.values.where((qty) => qty > 0).length;

  void _clear() {
    for (final skuId in widget.quantities.keys.toList(growable: false)) {
      widget.onChanged(skuId, 0);
    }
    // The cells hold their own text, so they are told to drop it rather than
    // left showing a number the order no longer contains.
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matrix = widget.matrix;
    if (matrix.isEmpty) return const SizedBox.shrink();

    final rows = _expanded || matrix.rows.length <= widget.collapsedRows
        ? matrix.rows
        : matrix.rows.take(widget.collapsedRows).toList(growable: false);
    final hidden = matrix.rows.length - rows.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        // Wide enough for a two-line colour name at a readable size, narrow
        // enough to leave room for two columns of boxes on a 360pt phone.
        final labelWidth = (available * 0.42).clamp(132.0, 196.0);

        // Cells share whatever is left when they fit, so three sizes fill the
        // width instead of huddling against the names with a gap after them.
        final naturalCell = (available - labelWidth) / matrix.columns.length;
        final cellWidth = naturalCell < _minCellWidth
            ? _minCellWidth
            : naturalCell;

        final rowHeight = _rowHeightFor(
          context,
          rows: rows,
          labelWidth: labelWidth,
          showPrice: matrix.pricesVary,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Heading(matrix: matrix),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant),
                color: theme.colorScheme.surface,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  children: [
                    // The colour column is fixed and the sizes scroll beside
                    // it. Scrolling the whole table sideways meant the names
                    // left with it, and a box in the fifteenth size had
                    // nothing to say which colourway it belonged to.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SweepToScroll(
                          horizontal: _horizontal,
                          child: SizedBox(
                            width: labelWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _HeaderRow(
                                  part: _Part.label,
                                  matrix: matrix,
                                  labelWidth: labelWidth,
                                  cellWidth: cellWidth,
                                ),
                                for (final row in rows)
                                  _MatrixRow(
                                    key: ValueKey(
                                      '${variantRowKey(row.value)}-label',
                                    ),
                                    part: _Part.label,
                                    matrix: matrix,
                                    row: row,
                                    height: rowHeight,
                                    labelWidth: labelWidth,
                                    cellWidth: cellWidth,
                                    showPrice: matrix.pricesVary,
                                    horizontal: _horizontal,
                                    quantities: widget.quantities,
                                    onChanged: widget.onChanged,
                                    onImageTap: widget.onImageTap,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _horizontal,
                            scrollDirection: Axis.horizontal,
                            // Never narrower than its columns need, never
                            // leaving a gap when they need less.
                            child: SizedBox(
                              width: cellWidth * matrix.columns.length,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _HeaderRow(
                                    part: _Part.cells,
                                    matrix: matrix,
                                    labelWidth: labelWidth,
                                    cellWidth: cellWidth,
                                  ),
                                  for (final row in rows)
                                    _MatrixRow(
                                      // Keyed by the colourway, so expanding
                                      // "show all" adds rows rather than
                                      // reshuffling the state of the ones
                                      // already on screen -- and so a test can
                                      // address one row of the grid.
                                      key: ValueKey(variantRowKey(row.value)),
                                      part: _Part.cells,
                                      matrix: matrix,
                                      row: row,
                                      height: rowHeight,
                                      labelWidth: labelWidth,
                                      cellWidth: cellWidth,
                                      showPrice: matrix.pricesVary,
                                      horizontal: _horizontal,
                                      quantities: widget.quantities,
                                      onChanged: widget.onChanged,
                                      onImageTap: widget.onImageTap,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // "There is more to the right." Without it the last column
                    // is cut off at the edge and reads as the last column.
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _endFade,
                          builder: (context, amount, _) => Opacity(
                            opacity: amount,
                            child: Container(
                              width: 28,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    theme.colorScheme.surface.withValues(
                                      alpha: 0,
                                    ),
                                    theme.colorScheme.surface,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Only where there are columns past the edge, and only until
            // the shopper has moved the grid once. The same hint the chip
            // rows carry, worded the same way.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: _overflows && !_used
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: SwipeHint(
                          noun: '${matrix.columnLabel.toLowerCase()}s',
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (hidden > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = true),
                  child: Text(
                    'Show all ${matrix.rows.length} '
                    '${matrix.rowLabel.toLowerCase()} options',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _OrderSummary(
              pieces: _totalPieces,
              lines: _linesChosen,
              total: widget.total,
              minOrder: widget.minOrder,
              onClear: _totalPieces > 0 ? _clear : null,
            ),
          ],
        );
      },
    );
  }

  /// Cells wide enough to hit and to hold four digits. Wholesale orders are not
  /// typed in ones.
  static const _minCellWidth = 92.0;

  /// The tallest row, measured rather than guessed.
  ///
  /// Colour names are seller-written and run from "Pink" to "Retro blue
  /// [regular style]". A fixed height either clips the long ones or leaves the
  /// short ones swimming, and every row in a table has to share one number.
  static double _rowHeightFor(
    BuildContext context, {
    required List<VariantRow> rows,
    required double labelWidth,
    required bool showPrice,
  }) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final nameWidth = labelWidth - _labelPadding - _thumbSize - _thumbGap - 8;

    var tallest = 0.0;
    for (final row in rows) {
      final painter = TextPainter(
        text: TextSpan(text: row.value, style: theme.textTheme.bodyMedium),
        textDirection: Directionality.of(context),
        maxLines: _nameLines,
        textScaler: scaler,
      )..layout(maxWidth: nameWidth > 0 ? nameWidth : 1);
      if (painter.height > tallest) tallest = painter.height;
    }

    if (showPrice) {
      final painter = TextPainter(
        text: TextSpan(text: 'Rs.0', style: theme.textTheme.labelSmall),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      tallest += painter.height + 2;
    }

    // The photograph sets the floor; the text raises it when it is taller.
    //
    // The boxes are deliberately not in this maximum. A scarce cell is a 40pt
    // field over a 9pt "5 left", which comes to about 63pt even at the largest
    // system font -- inside the 76pt the 56pt photograph already reserves. A
    // term for them was measured and never once bound, so it is not here.
    final text = tallest + _rowPadding * 2;
    final image = _thumbSize + _rowPadding * 2;
    return text > image ? text : image;
  }

  static const _thumbSize = 56.0;
  static const _thumbGap = 10.0;
  static const _labelPadding = 12.0;
  static const _rowPadding = 10.0;
  static const _nameLines = 2;
}

/// The title above the table and what it is asking for.
class _Heading extends StatelessWidget {
  const _Heading({required this.matrix});

  final VariantMatrix matrix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buyable = matrix.buyable.length;
    final total = matrix.cells.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose ${matrix.rowLabel.toLowerCase()} '
          'and ${matrix.columnLabel.toLowerCase()}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          // The seller's own numbers. "84 combinations" is the size of the
          // decision, and it is the reason this is a table at all.
          buyable == total
              ? '$total combinations · enter how many of each you want'
              : '$buyable of $total combinations in stock',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.part,
    required this.matrix,
    required this.labelWidth,
    required this.cellWidth,
  });

  final _Part part;
  final VariantMatrix matrix;
  final double labelWidth;
  final double cellWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      height: _headerHeight,
      alignment: Alignment.centerLeft,
      child: part == _Part.label
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                matrix.rowLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Row(
              children: [
                for (final column in matrix.columns)
                  SizedBox(
                    width: cellWidth,
                    child: VariantTooltip(
                      // The part the header had to drop -- the fitting guide the
                      // seller wrote into the size -- is one press away rather than
                      // gone.
                      message: column,
                      child: Text(
                        shortVariantLabel(column),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: withTooltipHint(
                          theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          theme,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Turns a sideways sweep anywhere on its child into grid movement.
///
/// The colour column is fixed, so it has no scroll of its own for a finger to
/// grab -- but somebody swiping to see more sizes does not aim carefully, and
/// a swipe that starts on a colour name should move the sizes rather than do
/// nothing.
///
/// Pointer events rather than a drag gesture, for the same reason [_QtyField]
/// needs them: whatever is under the finger may have claimed the arena
/// already. A [Listener] sits outside it.
class _SweepToScroll extends StatefulWidget {
  const _SweepToScroll({required this.horizontal, required this.child});

  final ScrollController horizontal;
  final Widget child;

  @override
  State<_SweepToScroll> createState() => _SweepToScrollState();
}

class _SweepToScrollState extends State<_SweepToScroll> {
  Offset? _down;
  bool _sweeping = false;
  double _lastX = 0;

  void _onDown(PointerDownEvent event) {
    _down = event.position;
    _lastX = event.position.dx;
    _sweeping = false;
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null) return;

    if (!_sweeping) {
      final travelled = event.position - down;
      if (travelled.dx.abs() < kTouchSlop) return;
      // Only once it is clearly sideways, so a finger going down the page
      // still scrolls the page.
      if (travelled.dx.abs() <= travelled.dy.abs()) return;
      _sweeping = true;
      _lastX = event.position.dx;
      return;
    }

    final controller = widget.horizontal;
    if (!controller.hasClients) return;
    final position = controller.position;
    controller.jumpTo(
      (controller.offset - (event.position.dx - _lastX)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _lastX = event.position.dx;
  }

  void _clear(PointerEvent event) {
    _down = null;
    _sweeping = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _clear,
    onPointerCancel: _clear,
    child: widget.child,
  );
}

/// Which half of a row to draw.
///
/// The table is split down the colour column: that half is fixed, the sizes
/// scroll beside it. Both halves draw the same heights and the same rules, so
/// they read as one table -- and a box in the fifteenth size still has its
/// colourway named beside it instead of scrolling away with everything else.
enum _Part { label, cells }

/// The header's height, fixed so the two halves line up. It was intrinsic
/// when the header was a single row.
const double _headerHeight = 46;

/// Identifies one row of the grid. Public so a test can address a colourway by
/// name instead of counting text fields down the page.
String variantRowKey(String rowValue) => 'variant-row-$rowValue';

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({
    required this.part,
    required this.horizontal,
    super.key,
    required this.matrix,
    required this.row,
    required this.height,
    required this.labelWidth,
    required this.cellWidth,
    required this.showPrice,
    required this.quantities,
    required this.onChanged,
    required this.onImageTap,
  });

  final _Part part;
  final VariantMatrix matrix;
  final VariantRow row;

  /// The grid's own sideways scroll, handed down so a cell can drive it --
  /// see [_QtyField] for why a cell has to.
  final ScrollController horizontal;

  final double height;
  final double labelWidth;
  final double cellWidth;
  final bool showPrice;
  final Map<String, int> quantities;
  final void Function(String skuId, int quantity) onChanged;
  final void Function(VariantRow row)? onImageTap;

  /// What this colourway costs, when the grid has to say. A range where the
  /// sizes are priced apart, one figure where they are not.
  String? get _priceLabel {
    if (!showPrice) return null;
    final prices = <num>[];
    for (final column in matrix.columns) {
      final price = matrix.at(row.value, column)?.price;
      if (price != null) prices.add(price);
    }
    if (prices.isEmpty) return null;
    prices.sort();
    return prices.first == prices.last
        ? formatRupees(prices.first)
        : '${formatRupees(prices.first)} – ${formatRupees(prices.last)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A row with something on the order is marked, so a buyer scrolling back up
    // a 21-row table can see what they have already filled in.
    final chosen = matrix.columns.any((column) {
      final skuId = matrix.at(row.value, column)?.skuId;
      return skuId != null && (quantities[skuId] ?? 0) > 0;
    });
    final price = _priceLabel;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: chosen
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : null,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: part == _Part.label
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _Thumbnail(
                    row: row,
                    onTap: onImageTap == null ? null : () => onImageTap!(row),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VariantTooltip(
                          // The colourway in full. The cell gives it two
                          // lines, and sellers write names that outrun them --
                          // the same reason the size header carries one.
                          message: row.value,
                          child: Text(
                            row.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: withTooltipHint(
                              theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: chosen
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              theme,
                            ),
                          ),
                        ),
                        if (price != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            price,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                for (final column in matrix.columns)
                  SizedBox(
                    width: cellWidth,
                    child: Center(
                      child: _Cell(
                        horizontal: horizontal,
                        variant: matrix.at(row.value, column),
                        label: '${row.value}, ${shortVariantLabel(column)}',
                        quantities: quantities,
                        onChanged: onChanged,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.row, required this.onTap});

  final VariantRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 56,
      height: 56,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: row.imageUrl.isEmpty
                      ? ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Image(
                          // 56pt, so the provider is asked for a thumbnail
                          // rather than the seller's full-resolution shot --
                          // there can be 21 of these on one screen.
                          image: AppImages.of(
                            row.imageUrl,
                            width: 56,
                            devicePixelRatio: MediaQuery.devicePixelRatioOf(
                              context,
                            ),
                          ),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                ),
              ),
            ),
            if (onTap != null && row.imageUrl.isNotEmpty)
              Positioned(
                right: 2,
                bottom: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: Icon(
                      Icons.zoom_in,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One square of the grid.
///
/// Three states, and the difference between the last two matters: a
/// combination the seller does not stock at all, and one they stock but have
/// run out of. Both are unbuyable; only the second is worth coming back for.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.horizontal,
    required this.variant,
    required this.label,
    required this.quantities,
    required this.onChanged,
  });

  final ScrollController horizontal;
  final ProductVariant? variant;
  final String label;
  final Map<String, int> quantities;
  final void Function(String skuId, int quantity) onChanged;

  @override
  Widget build(BuildContext context) {
    final variant = this.variant;
    if (variant == null) {
      return _Blank(label: '$label is not made', mark: '–');
    }
    if (!variant.inStock) {
      return _Blank(label: '$label is sold out', mark: '0');
    }

    final skuId = variant.skuId;
    if (skuId == null || skuId.isEmpty) {
      return _Blank(label: '$label cannot be ordered', mark: '–');
    }

    return _QtyField(
      key: ValueKey(skuId),
      horizontal: horizontal,
      label: label,
      quantity: quantities[skuId] ?? 0,
      stock: variant.stock,
      onChanged: (value) => onChanged(skuId, value),
    );
  }
}

class _Blank extends StatelessWidget {
  const _Blank({required this.label, required this.mark});

  final String label;
  final String mark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          width: _QtyField.width,
          height: _QtyField.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            mark,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quantity box.
///
/// Owns its own controller so that typing in one cell does not rebuild the text
/// of the other eighty-three, and so a rebuilt table cannot move the caret out
/// from under a buyer mid-number.
class _QtyField extends StatefulWidget {
  const _QtyField({
    super.key,
    required this.horizontal,
    required this.label,
    required this.quantity,
    required this.stock,
    required this.onChanged,
  });

  /// The grid's sideways scroll.
  ///
  /// A text field wins the gesture arena for a horizontal drag that starts on
  /// it -- for drag-to-select, and it keeps winning even with selection off
  /// and its own scroll physics disabled. On a phone the grid is mostly these
  /// boxes, so almost anywhere a finger landed to swipe, nothing moved, and
  /// the sizes off to the right read as unreachable. Rather than fight the
  /// arena, the box drives the grid itself.
  final ScrollController horizontal;

  final String label;
  final int quantity;
  final int? stock;
  final ValueChanged<int> onChanged;

  static const width = 72.0;
  static const height = 40.0;

  @override
  State<_QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<_QtyField> {
  late final _controller = TextEditingController(
    text: _textFor(widget.quantity),
  );
  final _focus = FocusNode();

  static String _textFor(int quantity) => quantity > 0 ? '$quantity' : '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_QtyField old) {
    super.didUpdateWidget(old);
    // Only when the page's number and the box's disagree -- otherwise every
    // keystroke would rewrite the field it came from.
    final shown = int.tryParse(_controller.text) ?? 0;
    if (shown != widget.quantity) {
      _controller.text = _textFor(widget.quantity);
    }
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) return;
    // Clamped on the way out rather than on each keystroke. Rewriting "12" to
    // "9" as somebody types the second digit of "120" is a field that fights
    // back; letting it stand until they leave and then correcting it is not.
    final stock = widget.stock;
    if (stock != null && widget.quantity > stock) {
      widget.onChanged(stock);
      _controller.text = _textFor(stock);
    }
    // Tidies "007" and "0" to an empty box.
    _controller.text = _textFor(int.tryParse(_controller.text) ?? 0);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Where the finger went down, and whether it has committed to a sideways
  /// swipe rather than a tap or a scroll down the page.
  Offset? _down;
  bool _sweeping = false;
  double _lastX = 0;

  void _onDown(PointerDownEvent event) {
    _down = event.position;
    _lastX = event.position.dx;
    _sweeping = false;
  }

  /// Drives the grid sideways from a finger that started on this box.
  ///
  /// Pointer events rather than a drag gesture: the field wins the arena for
  /// a horizontal drag and keeps winning with selection off and its own
  /// scroll physics disabled, so no [GestureDetector] wrapped around it ever
  /// sees the drag. A [Listener] is outside the arena and always does.
  ///
  /// It waits for the swipe to prove itself horizontal before moving
  /// anything, so a finger travelling down the page still scrolls the page.
  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null) return;

    if (!_sweeping) {
      final travelled = event.position - down;
      if (travelled.dx.abs() < kTouchSlop) return;
      if (travelled.dx.abs() <= travelled.dy.abs()) return;
      _sweeping = true;
      _lastX = event.position.dx;
      // The keyboard has no business opening because somebody swiped across
      // a box on the way to a size.
      _focus.unfocus();
      return;
    }

    final controller = widget.horizontal;
    if (!controller.hasClients) return;
    final position = controller.position;
    controller.jumpTo(
      (controller.offset - (event.position.dx - _lastX)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _lastX = event.position.dx;
  }

  void _onUp(PointerEvent event) {
    _down = null;
    _sweeping = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = widget.quantity > 0;
    final stock = widget.stock;

    // Only where it is a constraint. These listings publish five figures of
    // stock as a matter of course and "12123 left" is not information.
    final scarce = stock != null && stock <= 20;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _QtyField.width,
          height: _QtyField.height,
          child: Listener(
            // Taps are untouched -- the field below still focuses and types;
            // only a sideways sweep is turned into grid movement.
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                // Five digits is more than any of these sellers stock, and it
                // stops a stray key turning into an order nobody meant.
                LengthLimitingTextInputFormatter(5),
              ],
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.next,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: chosen ? theme.colorScheme.primary : null,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: chosen
                    ? theme.colorScheme.primary.withValues(alpha: 0.08)
                    : theme.colorScheme.surface,
                hintText: '0',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: chosen
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: chosen ? 1.6 : 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.6,
                  ),
                ),
              ),
              onChanged: (value) => widget.onChanged(int.tryParse(value) ?? 0),
            ),
          ),
        ),
        if (scarce) ...[
          const SizedBox(height: 2),
          Text(
            '$stock left',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// What the grid adds up to, under the grid.
class _OrderSummary extends StatelessWidget {
  const _OrderSummary({
    required this.pieces,
    required this.lines,
    required this.total,
    required this.minOrder,
    required this.onClear,
  });

  final int pieces;
  final int lines;
  final num total;
  final int minOrder;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = pieces > 0 && pieces < minOrder;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pieces == 0
                          ? 'Nothing selected yet'
                          : '$pieces ${pieces == 1 ? 'piece' : 'pieces'} '
                                'across $lines ${lines == 1 ? 'option' : 'options'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (pieces > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        formatRupees(total),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onClear != null)
                TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
          if (short) ...[
            const SizedBox(height: 6),
            Text(
              // The seller's minimum, said before the buy bar refuses rather
              // than after.
              'This seller takes orders of $minOrder or more.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

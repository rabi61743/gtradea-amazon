import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../cart/data/cart_store.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/reorder_validation.dart';

/// What reordering produced: the lines that went in the cart, and whether the
/// shopper asked to go straight on to pay.
class ReorderOutcome {
  const ReorderOutcome({required this.added, required this.checkout});

  final List<CartLine> added;

  /// True when they pressed the button that continues to checkout, false when
  /// they only wanted the goods in the basket.
  final bool checkout;
}

/// The review a reorder goes through before anything is bought.
///
/// Between placing an order and reordering it, a price moves, a colourway is
/// withdrawn, a seller raises their minimum, a listing disappears. The old
/// reorder added the order's own lines to the cart and found all of that out at
/// checkout, at the worst possible moment and with the old price already shown.
///
/// So this asks the catalogue first -- see [ReorderValidator] -- and shows what
/// it said, line by line, before anything reaches the cart. Every figure and
/// every status here comes off that answer. Nothing is assumed available and
/// nothing is assumed unchanged.
class ReorderSheet extends StatefulWidget {
  const ReorderSheet({super.key, required this.lines, this.title = 'Reorder'});

  /// The lines as the order records them. Checked, never added directly.
  final List<CartLine> lines;

  final String title;

  /// Opens the sheet and returns what happened, or null if it was dismissed.
  static Future<ReorderOutcome?> show(
    BuildContext context, {
    required List<CartLine> lines,
    String title = 'Reorder',
  }) {
    if (lines.isEmpty) return Future.value(null);
    return showModalBottomSheet<ReorderOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ReorderSheet(lines: lines, title: title),
    );
  }

  @override
  State<ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<ReorderSheet> {
  List<ReorderItem>? _items;
  Object? _error;

  /// Lines the shopper has taken out of this reorder. Keyed the way the cart
  /// keys a line, so a product in two colourways can be dropped one at a time.
  final _removed = <String>{};

  /// True while the cart is being written, so the button cannot be pressed
  /// twice and buy everything twice.
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _validate();
  }

  Future<void> _validate() async {
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final items = await ReorderValidator.instance.validate(widget.lines);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  /// The lines that would actually go in the cart.
  List<ReorderItem> get _buyable => [
    for (final item in _items ?? const <ReorderItem>[])
      if (item.isBuyable && !_removed.contains(item.ordered.key)) item,
  ];

  void _setQuantity(ReorderItem item, int quantity) {
    final items = _items;
    if (items == null) return;
    final index = items.indexOf(item);
    if (index == -1) return;
    setState(() => items[index] = item.copyWith(quantity: quantity));
  }

  /// Puts the reviewed lines in the cart, through the cart's own rules.
  ///
  /// [CartStore.add] is what merges a line that is already there and what
  /// clamps to the seller's minimum -- so a reorder of something already in
  /// the basket raises that line rather than making a second one.
  void _addToCart({required bool checkout}) {
    if (_adding) return;
    final items = _buyable;
    if (items.isEmpty) return;

    setState(() => _adding = true);
    final added = <CartLine>[];
    for (final item in items) {
      CartStore.instance.add(item.line!);
      added.add(item.line!);
    }
    Navigator.of(context).pop(
      ReorderOutcome(added: added, checkout: checkout),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          _Grip(title: widget.title),
          Expanded(
            child: switch ((items, _error)) {
              (_, final error?) => _Failed(error: error, onRetry: _validate),
              (null, _) => const _Checking(),
              (final items?, _) when items.isEmpty => const _Nothing(),
              (final items?, _) => ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                children: [
                  _Summary(items: items, removed: _removed),
                  const SizedBox(height: 10),
                  for (final item in items)
                    _ItemTile(
                      item: item,
                      removed: _removed.contains(item.ordered.key),
                      onRemove: () => setState(
                        () => _removed.contains(item.ordered.key)
                            ? _removed.remove(item.ordered.key)
                            : _removed.add(item.ordered.key),
                      ),
                      onQuantity: (q) => _setQuantity(item, q),
                    ),
                ],
              ),
            },
          ),
          if (items != null && items.isNotEmpty)
            _Actions(
              count: _buyable.length,
              total: _buyable.fold<num>(
                0,
                (sum, item) => sum + item.line!.lineTotal,
              ),
              busy: _adding,
              onCart: () => _addToCart(checkout: false),
              onCheckout: () => _addToCart(checkout: true),
              theme: theme,
            ),
        ],
      ),
    );
  }
}

/// The sheet's handle and title.
class _Grip extends StatelessWidget {
  const _Grip({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// While the catalogue is being asked.
class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          Text(
            'Checking prices and stock...',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nothing is added until you confirm.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// When the check itself could not be run.
class _Failed extends StatelessWidget {
  const _Failed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 34,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Prices could not be checked',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // Nothing is added on a failed check. Reordering at prices this
              // app could not confirm is exactly what this screen exists to
              // stop.
              'Your order was not changed. Try again once you are back online.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('There is nothing here to reorder'));
}

/// The one-line verdict above the items.
class _Summary extends StatelessWidget {
  const _Summary({required this.items, required this.removed});

  final List<ReorderItem> items;
  final Set<String> removed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final ready = items.where((i) => i.isBuyable).length;
    final flagged = items.where((i) => i.needsAttention).length;
    final unknown = items
        .where((i) => i.status == ReorderStatus.unknown)
        .length;

    // Said plainly, and only about what was actually established. An item the
    // catalogue could not be asked about is counted apart from one it refused.
    final parts = <String>[
      '$ready of ${items.length} ready',
      if (flagged > 0) '$flagged need${flagged == 1 ? 's' : ''} a look',
      if (unknown > 0) '$unknown could not be checked',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Text(
        parts.join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// How one status looks, and what it is called.
///
/// The words are this app's, because these are the app's own comparisons --
/// only the app has seen both the old order and the current record. The
/// *facts* underneath every one of them come from the catalogue.
({String label, Color tint, IconData icon}) _style(
  ReorderItem item,
  ThemeData theme,
) => switch (item.status) {
  ReorderStatus.available => (
    label: 'Available',
    tint: AppColors.trustBlue,
    icon: Icons.check_circle_outline,
  ),
  ReorderStatus.priceChanged => (
    label: (item.priceDelta ?? 0) > 0 ? 'Price went up' : 'Price went down',
    tint: AppColors.commerceOrange,
    icon: Icons.trending_up,
  ),
  ReorderStatus.outOfStock => (
    label: item.isBuyable ? 'Limited stock' : 'Out of stock',
    tint: theme.colorScheme.error,
    icon: Icons.inventory_2_outlined,
  ),
  ReorderStatus.variantGone => (
    label: 'Option no longer offered',
    tint: theme.colorScheme.error,
    icon: Icons.swap_horiz,
  ),
  ReorderStatus.unavailable => (
    label: 'No longer available',
    tint: theme.colorScheme.error,
    icon: Icons.remove_shopping_cart_outlined,
  ),
  ReorderStatus.unknown => (
    label: 'Could not be checked',
    tint: theme.colorScheme.onSurfaceVariant,
    icon: Icons.help_outline,
  ),
};

/// One line of the reorder, with what the catalogue said about it.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.removed,
    required this.onRemove,
    required this.onQuantity,
  });

  final ReorderItem item;
  final bool removed;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _style(item, theme);
    final line = item.line;
    final dimmed = removed || !item.isBuyable;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: item.ordered.imageUrl == null
                          ? Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                            )
                          : Image.network(
                              item.ordered.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.ordered.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        if (item.ordered.variantLabel case final variant?) ...[
                          const SizedBox(height: 2),
                          Text(
                            variant,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: removed ? 'Put back' : 'Remove from this reorder',
                    onPressed: item.isBuyable ? onRemove : null,
                    icon: Icon(removed ? Icons.undo : Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _StatusTag(style: style),
                  const Spacer(),
                  if (line != null) _Price(item: item),
                ],
              ),
              // What the seller actually has left, when that is the constraint.
              if (item.available case final left?
                  when item.status == ReorderStatus.outOfStock) ...[
                const SizedBox(height: 6),
                Text(
                  left == 0 ? 'None left' : 'Only $left left',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              // The server's own words, where it gave any.
              if (item.message case final message?
                  when item.status == ReorderStatus.unknown) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (line != null && !removed) ...[
                const SizedBox(height: 8),
                _Stepper(
                  quantity: line.quantity,
                  minimum: line.minOrder,
                  maximum: item.available,
                  onChanged: onQuantity,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.style});

  final ({String label, Color tint, IconData icon}) style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: style.tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.tint),
          const SizedBox(width: 4),
          Text(
            style.label,
            key: const ValueKey('reorder-status'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: style.tint,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's price, with what it was beside it when the two differ.
class _Price extends StatelessWidget {
  const _Price({required this.item});

  final ReorderItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = item.status == ReorderStatus.priceChanged;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (changed) ...[
          Text(
            formatRupees(item.orderedPrice),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
              decorationColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          formatRupees(item.currentPrice),
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The quantity control, held between the seller's floor and what is left.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
  });

  final int quantity;
  final int minimum;

  /// What the seller has, when they said. Null is no ceiling.
  final int? maximum;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canLower = quantity > minimum;
    final canRaise = maximum == null || quantity < maximum!;

    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Fewer',
                onPressed: canLower ? () => onChanged(quantity - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              Text(
                '$quantity',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'More',
                onPressed: canRaise ? () => onChanged(quantity + 1) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        if (minimum > 1) ...[
          const SizedBox(width: 8),
          Text(
            'Seller\'s minimum is $minimum',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The two ways out, pinned to the bottom.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.count,
    required this.total,
    required this.busy,
    required this.onCart,
    required this.onCheckout,
    required this.theme,
  });

  final int count;
  final num total;
  final bool busy;
  final VoidCallback onCart;
  final VoidCallback onCheckout;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 && !busy;

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    count == 0
                        ? 'Nothing available to reorder'
                        : '$count item${count == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (count > 0)
                    Text(
                      formatRupees(total),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: enabled ? onCart : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Add to cart', maxLines: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: enabled ? onCheckout : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Checkout', maxLines: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

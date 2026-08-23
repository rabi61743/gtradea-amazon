import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../checkout/presentation/checkout_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/cart_store.dart';

/// The cart: every line, its quantity, and what the order comes to.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
  }

  /// Removal is undoable rather than confirmed, matching the saved list: one
  /// line is cheap to put back and expensive to interrupt for.
  void _removeWithUndo(CartLine line) {
    final store = CartStore.instance;
    final index = store.indexOf(line.key);
    store.remove(line.key);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${line.title}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restore(line, index),
          ),
        ),
      );
  }

  /// Emptying the whole cart IS confirmed: undo alone is too easy to miss when
  /// the tap discards everything at once.
  Future<void> _confirmClear() async {
    final store = CartStore.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty your cart?'),
        content: Text(
          'This removes all ${store.lineCount} '
          '${store.lineCount == 1 ? 'line' : 'lines'}. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Empty cart'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) store.clear();
  }

  void _checkout() {
    final store = CartStore.instance;
    if (store.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        // The order is passed by value, not read back off the singleton: what
        // is being paid for is what was on screen at the moment of the tap.
        builder: (_) => CheckoutScreen(
          lines: store.lines,
          totals: store.totals,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartStore.instance,
      builder: (context, _) {
        final store = CartStore.instance;
        final lines = store.lines;
        final totals = store.totals;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              lines.isEmpty
                  ? 'Cart'
                  : 'Cart (${totals.itemCount} '
                        '${totals.itemCount == 1 ? 'item' : 'items'})',
            ),
            actions: [
              if (lines.isNotEmpty)
                TextButton(
                  onPressed: _confirmClear,
                  child: const Text('Empty'),
                ),
            ],
          ),
          body: lines.isEmpty
              ? const _EmptyCart()
              : ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  children: [
                    for (final line in lines)
                      _CartTile(
                        line: line,
                        onIncrement: () => store.increment(line.key),
                        onDecrement: () => store.decrement(line.key),
                        onRemove: () => _removeWithUndo(line),
                      ),
                    const SizedBox(height: 8),
                    _SummaryCard(totals: totals),
                  ],
                ),
          bottomNavigationBar:
              lines.isEmpty ? null : _CheckoutBar(totals: totals, onCheckout: _checkout),
        );
      },
    );
  }
}

/// One line: photo, title, chosen variant, price, stepper.
class _CartTile extends StatelessWidget {
  const _CartTile({
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final CartLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = line.listPrice;
    final struck = (list != null && list > line.unitPrice) ? list : null;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: ArtworkPanel(
                    icon: Icons.checkroom,
                    tint: theme.colorScheme.primary,
                    imageUrl: line.imageUrl,
                    iconScale: 0.4,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (line.variantLabel != null) ...[
                        const SizedBox(height: 3),
                        // The chosen option is spelled out: two lines of the
                        // same product are otherwise indistinguishable.
                        Text(
                          line.variantLabel!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            formatRupees(line.unitPrice),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          if (struck != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                formatRupees(struck),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _Stepper(
                  quantity: line.quantity,
                  canDecrease: line.quantity > line.minOrder,
                  canIncrease: line.quantity < CartStore.maxPerLine,
                  onIncrement: onIncrement,
                  onDecrement: onDecrement,
                ),
                const Spacer(),
                // The line total, because unit price times quantity is
                // arithmetic the shopper should not have to do.
                Text(
                  formatRupees(line.lineTotal),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Quantity stepper, shaped like the one on the detail page.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.canDecrease,
    required this.canIncrease,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            tooltip: 'Fewer',
            visualDensity: VisualDensity.compact,
            onPressed: canDecrease ? onDecrement : null,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'More',
            visualDensity: VisualDensity.compact,
            onPressed: canIncrease ? onIncrement : null,
          ),
        ],
      ),
    );
  }
}

/// Subtotal, savings, delivery and total.
///
/// Takes a [CartTotals] rather than a list of lines: the arithmetic happens in
/// the store, and this only renders it.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals});

  final CartTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _SummaryRow(
              label: 'Subtotal (${totals.itemCount} '
                  '${totals.itemCount == 1 ? 'item' : 'items'})',
              value: formatRupees(totals.subtotal),
            ),
            if (totals.savings > 0) ...[
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'You save',
                value: '-${formatRupees(totals.savings)}',
                valueColor: AppColors.success,
              ),
            ],
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Delivery',
              value: totals.delivery == 0
                  ? 'Free'
                  : formatRupees(totals.delivery),
              valueColor: totals.delivery == 0 ? AppColors.success : null,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            _SummaryRow(
              label: 'Total',
              value: formatRupees(totals.total),
              emphasised: true,
            ),
            if (totals.vatIncluded >= 1) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                // Included, not added: the prices above already carry it, and
                // adding it again at the bottom would double-charge.
                child: Text(
                  'Includes ${formatRupees(totals.vatIncluded)} VAT',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = emphasised
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final valueStyle = emphasised
        ? theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          )
        : theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          );

    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        Text(value, style: valueStyle),
      ],
    );
  }
}

/// Pinned checkout action carrying the total, so the number does not change
/// between the tap and the next screen.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.totals, required this.onCheckout});

  final CartTotals totals;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatRupees(totals.total),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: onCheckout,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text('Checkout'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

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
              Icons.shopping_cart_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Your cart is empty',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Add something from a product page and it will wait for you here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Start shopping'),
            ),
          ],
        ),
      ),
    );
  }
}

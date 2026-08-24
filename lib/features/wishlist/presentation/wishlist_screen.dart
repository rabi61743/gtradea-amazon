import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/browse_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../product/presentation/product_detail_screen.dart';
import '../data/wishlist_store.dart';

/// Everything the shopper kept for later.
///
/// Two slots a design of this shape usually fills are left out: a star rating
/// and an "In Stock" badge. This catalogue publishes neither, so a rating would
/// have to be invented and a stock promise the server never made would send
/// someone to a checkout that fails. What sits there instead -- the seller's
/// badge and units sold -- is what the feed actually returns.
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  @override
  void initState() {
    super.initState();
    WishlistStore.instance.load();
    CartStore.instance.load();
  }

  void _say(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void _openCart() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CartScreen()),
    );
  }

  /// Opens the product. The saved entry paints the page immediately and the
  /// full record is fetched behind it.
  void _open(SavedProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: productStub(
            numIid: product.id,
            title: product.title,
            imageUrl: product.imageUrl,
            displayPrice: product.price,
          ),
        ),
      ),
    );
  }

  CartLine _lineFor(SavedProduct product) => CartLine(
        productId: product.id,
        title: product.title,
        unitPrice: product.price,
        listPrice: product.listPrice,
        imageUrl: product.imageUrl,
        // The seller's floor, not one. Adding a single unit of a listing that
        // sells in tens is a refusal waiting to happen.
        quantity: product.minOrder,
        minOrder: product.minOrder,
        category: product.category,
        source: '1688',
      );

  void _addToCart(SavedProduct product) {
    final inCart = CartStore.instance.add(_lineFor(product));
    _say(
      'Added to your cart. $inCart in cart.',
      action: SnackBarAction(label: 'View cart', onPressed: _openCart),
    );
  }

  /// Adds every saved item to the cart at once.
  ///
  /// They stay saved. "Move all" reads like a transfer, but emptying the list
  /// on one tap would throw away a shortlist the shopper built, and that is not
  /// undoable from the cart.
  void _addAll(List<SavedProduct> products) {
    final buyable = products.where((p) => p.price > 0).toList();
    if (buyable.isEmpty) {
      _say('None of these have a price yet.');
      return;
    }
    for (final product in buyable) {
      CartStore.instance.add(_lineFor(product));
    }

    final skipped = products.length - buyable.length;
    _say(
      '${buyable.length} ${buyable.length == 1 ? 'item' : 'items'} added to '
      'your cart.'
      '${skipped > 0 ? ' $skipped had no price and was left here.' : ''}',
      action: SnackBarAction(label: 'View cart', onPressed: _openCart),
    );
  }

  /// Removal is undoable rather than confirmed: one row is cheap to put back
  /// and expensive to interrupt for.
  void _remove(SavedProduct product) {
    final index = WishlistStore.instance.items.indexOf(product);
    WishlistStore.instance.remove(product.id);
    _say(
      'Removed ${product.title}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => WishlistStore.instance.restore(product, index),
      ),
    );
  }

  /// Emptying the whole list IS confirmed: undo is too easy to miss when one
  /// tap discards everything.
  Future<void> _confirmClear(WishlistStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear your saved items?'),
        content: Text(
          'This removes all ${store.count} '
          '${store.count == 1 ? 'item' : 'items'}. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) store.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable:
          Listenable.merge([WishlistStore.instance, CartStore.instance]),
      builder: (context, _) {
        final store = WishlistStore.instance;
        final items = store.items;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Saved items'),
            actions: [
              if (items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear all',
                  onPressed: () => _confirmClear(store),
                ),
              IconButton(
                icon: Badge.count(
                  count: CartStore.instance.count,
                  isLabelVisible: CartStore.instance.count > 0,
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                tooltip: 'Cart',
                onPressed: _openCart,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: items.isEmpty
              ? const _EmptyWishlist()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                        'Your favourite items, saved for later',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _SummaryCard(
                      count: items.length,
                      onAddAll: () => _addAll(items),
                    ),
                    const SizedBox(height: 12),
                    for (final product in items) ...[
                      _SavedCard(
                        product: product,
                        onOpen: () => _open(product),
                        onRemove: () => _remove(product),
                        onAddToCart: () => _addToCart(product),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _KeepShoppingCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BrowseScreen()),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// How many are saved, and the one action that applies to all of them.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.onAddAll});

  final int count;
  final VoidCallback onAddAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.dividerColor),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          _RoundIcon(icon: Icons.favorite_border),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count ${count == 1 ? 'item' : 'items'} saved',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  // Says what the button actually does. "Move" would imply the
                  // list is emptied, and it is not.
                  'Adding to the cart keeps them here',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onAddAll,
            icon: const Icon(Icons.add_shopping_cart, size: 17),
            label: const Text('Add all'),
          ),
        ],
      ),
    );
  }
}

/// One saved product: what it is, what it costs, and the two things that can
/// be done with it.
class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.product,
    required this.onOpen,
    required this.onRemove,
    required this.onAddToCart,
  });

  final SavedProduct product;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = product.listPrice;
    final struck = (list != null && list > product.price) ? list : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.dividerColor),
        color: theme.colorScheme.surface,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: ArtworkPanel(
                  icon: Icons.checkroom,
                  tint: theme.colorScheme.primary,
                  imageUrl: product.imageUrl,
                  iconScale: 0.42,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The seller's own badge, when the listing carries one.
                        if (product.sellerBadge != null)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _Badge(label: product.sellerBadge!),
                            ),
                          )
                        else
                          const Spacer(),
                        // Filled, because everything on this screen is saved.
                        // Tapping it is how one gets unsaved.
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.favorite,
                            color: AppColors.wishlist,
                            size: 22,
                          ),
                          tooltip: 'Remove from saved',
                          onPressed: onRemove,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // No stars. Nothing in this catalogue is rated,
                              // and five empty ones read as a bad product
                              // rather than an unrated one. Units sold is the
                              // popularity signal that actually exists.
                              if (product.salesLabel != null)
                                Text(
                                  product.salesLabel!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              // Only when it is a surprise: wholesale listings
                              // sell in tens, and the cart is a bad place to
                              // find that out.
                              if (product.minOrder > 1)
                                Text(
                                  'Minimum ${product.minOrder}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (struck != null)
                              Text(
                                formatRupees(struck),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            Text(
                              product.price > 0
                                  ? formatRupees(product.price)
                                  : 'Price on request',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: onRemove,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                          ),
                          child: const Icon(Icons.delete_outline, size: 19),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            // A row with no price cannot be bought: the pricing
                            // engine has not worked one out, and the cart would
                            // show Rs. 0 for something real.
                            onPressed: product.price > 0 ? onAddToCart : null,
                            icon: const Icon(Icons.add_shopping_cart, size: 18),
                            label: const Text('Add to cart'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(40),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.primary.withValues(alpha: 0.09),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
      ),
      child: Icon(icon, size: 20, color: theme.colorScheme.primary),
    );
  }
}

/// The way back to the catalogue, at the end of the list.
class _KeepShoppingCard extends StatelessWidget {
  const _KeepShoppingCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          _RoundIcon(icon: Icons.shopping_bag_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Looking for more?',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Browse the departments for more like these.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onTap,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward, size: 17),
            label: const Text('Browse'),
          ),
        ],
      ),
    );
  }
}

class _EmptyWishlist extends StatelessWidget {
  const _EmptyWishlist();

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
              Icons.favorite_border,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing saved yet',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the heart on anything you want to come back to.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

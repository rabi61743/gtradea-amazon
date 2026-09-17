import 'package:flutter/material.dart';

import '../../../core/ui/action_status.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../../core/network/api_error.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/browse_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../product/data/product_detail_content.dart';
import '../../product/data/product_repository.dart';
import '../../product/presentation/product_detail_screen.dart';
import '../data/wishlist_store.dart';
import 'saved_add_to_cart_button.dart';

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

  bool _movingAll = false;

  void _say(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void _openCart() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CartScreen()));
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

  CartLine _lineFor(SavedProduct product, num price) => CartLine(
    productId: product.id,
    title: product.title,
    unitPrice: price,
    listPrice: product.listPrice,
    imageUrl: product.imageUrl,
    // The seller's floor, not one. Adding a single unit of a listing that
    // sells in tens is a refusal waiting to happen.
    quantity: product.minOrder,
    minOrder: product.minOrder,
    category: product.category,
    source: '1688',
  );

  /// What this product costs, asking the catalogue if the saved copy does not
  /// know.
  ///
  /// A row can be saved before the pricing engine has worked one out, and its
  /// snapshot then carries zero. Putting that in the cart would show Rs. 0 for
  /// something real, so the price is fetched rather than assumed -- which is
  /// also what lets every saved item move rather than most of them.
  Future<num?> _resolvePrice(SavedProduct product) async {
    if (product.price > 0) return product.price;
    try {
      final body = await ProductRepository.instance.detail(product.id);
      final price = ProductDetail.fromApi(body).price;
      return price > 0 ? price : null;
    } on ApiError {
      return null;
    }
  }

  /// The price one product would go into the cart at, or null -- with the
  /// shopper told why -- when there is none. The card's button animates while
  /// this runs, and puts itself back if it comes back null.
  Future<num?> _priceForCart(SavedProduct product) async {
    final price = await _resolvePrice(product);
    if (!mounted) return null;
    if (price == null) {
      // Left as it was rather than added at nothing, so it can be tried again
      // once the seller has priced it.
      _say('${product.title} has no price yet, so it stays saved.');
    }
    return price;
  }

  /// Adds one product to the cart. Called when the button's animation lands,
  /// so "Added to Cart" never shows ahead of the add itself.
  ///
  /// The saved card stays: on this page adding is not unsaving.
  bool _addToCart(SavedProduct product, num price) {
    final index = WishlistStore.instance.items.indexOf(product);
    final line = _lineFor(product, price);
    final inCart = CartStore.instance.add(line);
    if (!CartStore.instance.contains(product.id)) return false;

    // "Added to Cart" shows first; the card then animates away and only
    // leaves the list once that has finished (see [_LeavingCard]).
    setState(() => _leaving.add(product.id));

    _say(
      '${ActionStatus.addedToCartLabel} · $inCart in cart',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          CartStore.instance.remove(line.key, announce: false);
          if (!mounted) return;
          if (_leaving.remove(product.id)) {
            // Still on its way out: it simply stays.
            setState(() {});
          } else if (!WishlistStore.instance.contains(product.id)) {
            WishlistStore.instance.restore(product, index);
          }
        },
      ),
    );
    return true;
  }

  /// Cards animating away after being added to the cart.
  final _leaving = <String>{};

  /// The card's leaving animation has finished: now it comes off the list.
  void _gone(SavedProduct product) {
    if (!_leaving.remove(product.id)) return;
    // Silent: the add already sounded, and this is not a delete.
    WishlistStore.instance.remove(product.id, announce: false);
  }

  /// Moves every saved product into the cart at once.
  Future<void> _moveAll() async {
    if (_movingAll) return;
    // A copy: the list being iterated is the one this removes from.
    final products = List<SavedProduct>.from(WishlistStore.instance.items);
    if (products.isEmpty) return;

    setState(() => _movingAll = true);

    final moved = <({SavedProduct product, int index, String key})>[];
    final unpriced = <SavedProduct>[];

    for (final product in products) {
      final price = await _resolvePrice(product);
      if (!mounted) return;
      if (price == null) {
        unpriced.add(product);
        continue;
      }
      final index = WishlistStore.instance.items.indexOf(product);
      final line = _lineFor(product, price);
      CartStore.instance.add(line);
      WishlistStore.instance.remove(product.id, announce: false);
      moved.add((product: product, index: index, key: line.key));
    }

    if (!mounted) return;
    setState(() => _movingAll = false);

    if (moved.isEmpty) {
      _say('None of these have a price yet, so they stay saved.');
      return;
    }

    _say(
      '${moved.length} ${moved.length == 1 ? 'item' : 'items'} moved to your '
      'cart.'
      '${unpriced.isEmpty ? '' : ' ${unpriced.length} had no price and stayed '
                'here.'}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          for (final entry in moved) {
            CartStore.instance.remove(entry.key, announce: false);
            WishlistStore.instance.restore(entry.product, entry.index);
          }
        },
      ),
    );
  }

  /// Removal is undoable rather than confirmed: one row is cheap to put back
  /// and expensive to interrupt for.
  void _remove(SavedProduct product) {
    final index = WishlistStore.instance.items.indexOf(product);
    WishlistStore.instance.remove(product.id);
    _say(
      ActionStatus.removedFromWishlist,
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
      listenable: Listenable.merge([
        WishlistStore.instance,
        CartStore.instance,
      ]),
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
                  // Clear of the system gesture bar, which sat on the last card.
                  padding: EdgeInsets.fromLTRB(
                    12,
                    4,
                    12,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
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
                      busy: _movingAll,
                      onMoveAll: _moveAll,
                    ),
                    const SizedBox(height: 12),
                    for (final product in items)
                      _LeavingCard(
                        key: ValueKey('saved-card-${product.id}'),
                        leaving: _leaving.contains(product.id),
                        onGone: () => _gone(product),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SavedCard(
                            product: product,
                            busy: _movingAll,
                            onOpen: () => _open(product),
                            onRemove: () => _remove(product),
                            prepareAdd: () => _priceForCart(product),
                            commitAdd: (price) => _addToCart(product, price),
                            onOpenCart: _openCart,
                          ),
                        ),
                      ),
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
  const _SummaryCard({
    required this.count,
    required this.busy,
    required this.onMoveAll,
  });

  final int count;
  final bool busy;
  final VoidCallback onMoveAll;

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
          // The same red as the hearts on the saved items below.
          const _RoundIcon(
            key: ValueKey('wishlist-summary-heart'),
            icon: Icons.favorite,
            color: AppColors.wishlist,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count ${count == 1 ? 'item' : 'items'} saved',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // Says what the button does, because it empties this list.
                  'Moving them to the cart clears this list',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : onMoveAll,
            icon: busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_shopping_cart, size: 17),
            label: const Text('Move all'),
          ),
        ],
      ),
    );
  }
}

/// A saved card that, once [leaving], lets "Added to Cart" be seen, then fades,
/// shrinks and closes its gap, and calls [onGone] when it has.
///
/// The hold and the exit are one controller, so nothing waits on a timer and
/// the card cannot be removed before the "Added" state has had its moment.
class _LeavingCard extends StatefulWidget {
  const _LeavingCard({
    super.key,
    required this.leaving,
    required this.onGone,
    required this.child,
  });

  final bool leaving;
  final VoidCallback onGone;
  final Widget child;

  /// How long "Added to Cart" stays before the card starts to go.
  static const hold = Duration(milliseconds: 700);

  /// How long the card takes to go.
  static const exit = Duration(milliseconds: 350);

  @override
  State<_LeavingCard> createState() => _LeavingCardState();
}

class _LeavingCardState extends State<_LeavingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: _LeavingCard.hold + _LeavingCard.exit,
  )..addStatusListener(_status);

  late final Animation<double> _t = CurvedAnimation(
    parent: _out,
    curve: Interval(
      _LeavingCard.hold.inMilliseconds /
          (_LeavingCard.hold + _LeavingCard.exit).inMilliseconds,
      1,
      curve: Curves.easeInCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.leaving) _out.forward();
  }

  @override
  void didUpdateWidget(_LeavingCard old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) {
      _out.forward(from: 0);
    } else if (!widget.leaving && old.leaving) {
      // Undone while still leaving: back as it was.
      _out.value = 0;
    }
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && widget.leaving) widget.onGone();
  }

  @override
  void dispose() {
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final t = _t.value;
        if (t == 0) return child!;
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            // The gap closes behind the card, so the list slides up to meet it.
            heightFactor: 1 - Curves.easeInOut.transform(t),
            child: Opacity(
              opacity: (1 - t * 1.4).clamp(0.0, 1.0),
              child: Transform.scale(scale: 1 - 0.08 * t, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// One saved product: what it is, what it costs, and the two things that can
/// be done with it.
class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.product,
    required this.busy,
    required this.onOpen,
    required this.onRemove,
    required this.prepareAdd,
    required this.commitAdd,
    required this.onOpenCart,
  });

  final SavedProduct product;

  /// True while everything is being moved.
  final bool busy;

  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final Future<num?> Function() prepareAdd;
  final bool Function(num price) commitAdd;
  final VoidCallback onOpenCart;

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
            // Centred, not top-aligned. The text column is the tall child --
            // two lines of title, the facts under it and a row of buttons --
            // so a top-aligned photograph sat against the top edge with a
            // block of empty space beneath it.
            crossAxisAlignment: CrossAxisAlignment.center,
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
                          onPressed: busy ? null : onRemove,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                          ),
                          child: const Icon(Icons.delete_outline, size: 19),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SavedAddToCartButton(
                            productId: product.id,
                            enabled: !busy,
                            prepare: prepareAdd,
                            commit: commitAdd,
                            onOpenCart: onOpenCart,
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
  const _RoundIcon({super.key, required this.icon, this.color});

  final IconData icon;

  /// The icon and its tinted circle. Defaults to the theme primary.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ink.withValues(alpha: 0.12),
      ),
      child: Icon(icon, size: 20, color: ink),
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
      key: const ValueKey('wishlist-keep-shopping'),
      padding: const EdgeInsets.all(14),
      // A card like the saved items above it. It was a half-strength grey wash
      // on the grey page, and all but vanished.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
          // Filled, like "Add to cart": the outlined button's edge was the same
          // grey as the card behind it, so it read as loose text.
          FilledButton.icon(
            key: const ValueKey('wishlist-browse'),
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
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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

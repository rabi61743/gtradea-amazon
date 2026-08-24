import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../catalog/data/product.dart';
import '../../product/presentation/product_detail_screen.dart';
import '../data/wishlist_store.dart';

/// Everything the shopper has saved, newest first.
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
  }

  @override
  Widget build(BuildContext context) {
    final store = WishlistStore.instance;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = store.items;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Saved'),
            actions: [
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClear(context, store),
                  child: const Text('Clear all'),
                ),
            ],
          ),
          body: items.isEmpty
              ? const _EmptyWishlist()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _SavedTile(
                    product: items[i],
                    onRemove: () => _removeWithUndo(context, store, items[i]),
                  ),
                ),
        );
      },
    );
  }

  /// Removal is undoable rather than confirmed. A single saved item is cheap
  /// to restore and expensive to interrupt for.
  void _removeWithUndo(
    BuildContext context,
    WishlistStore store,
    SavedProduct product,
  ) {
    store.remove(product.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${product.title}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.toggle(product),
          ),
        ),
      );
  }

  /// Clearing everything IS confirmed: it is one tap that discards work the
  /// shopper did across many sessions, and undo alone is too easy to miss.
  Future<void> _confirmClear(BuildContext context, WishlistStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear your saved list?'),
        content: Text(
          'This removes all ${store.count} saved products. It cannot be '
          'undone.',
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
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.product, required this.onRemove});

  final SavedProduct product;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = product.listPrice;
    final struck = (list != null && list > product.price) ? list : null;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: () => Navigator.of(context).push(
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
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: ArtworkPanel(
                  icon: Icons.checkroom,
                  tint: theme.colorScheme.primary,
                  imageUrl: product.imageUrl,
                  iconScale: 0.4,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(height: 1.25, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          formatRupees(product.price),
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
        ),
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
            Icon(Icons.favorite_border,
                size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Nothing saved yet',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the heart on a product to keep it here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

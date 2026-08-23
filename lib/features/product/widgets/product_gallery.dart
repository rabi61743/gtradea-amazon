import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Swipeable product photography with a page counter and the two actions a
/// shopper reaches for on this screen.
///
/// A counter chip rather than dots: dots stop being countable past four or
/// five, and a gallery is exactly where a shopper wants to know how much is
/// left to look at.
class ProductGallery extends StatefulWidget {
  const ProductGallery({
    super.key,
    required this.images,
    required this.rating,
    required this.soldLabel,
    this.saved = false,
    this.onToggleSaved,
    this.onShare,
  });

  final List<String> images;
  final double rating;

  /// Short social proof, e.g. "2.0k sold".
  final String? soldLabel;

  final bool saved;
  final VoidCallback? onToggleSaved;
  final VoidCallback? onShare;

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AspectRatio(
      // Taller than square: clothing and appliances are both portrait
      // subjects, and cropping them to a square loses the thing being sold.
      aspectRatio: 0.88,
      child: Stack(
        children: [
          ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => Image.network(
                widget.images[i],
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 40,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Column(
              children: [
                _RoundAction(
                  icon: widget.saved ? Icons.favorite : Icons.favorite_border,
                  tooltip: widget.saved ? 'Saved' : 'Save',
                  color: widget.saved ? AppColors.wishlist : null,
                  onTap: widget.onToggleSaved,
                ),
                const SizedBox(height: 8),
                _RoundAction(
                  icon: Icons.share_outlined,
                  tooltip: 'Share',
                  onTap: widget.onShare,
                ),
              ],
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              right: 10,
              bottom: 10,
              child: _Pill(
                child: Text(
                  '${_index + 1}/${widget.images.length}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          Positioned(
            left: 10,
            bottom: 10,
            child: _Pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.rating.toStringAsFixed(1),
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.star, size: 13, color: AppColors.success),
                  if (widget.soldLabel != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 1,
                      height: 12,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.soldLabel!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            icon,
            size: 20,
            color: color ?? theme.colorScheme.onSurface,
          ),

        ),
      ),
    );
  }
}

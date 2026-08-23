import 'package:flutter/material.dart';

/// Swipeable product photography.
///
/// Deliberately carries no product chrome: no save, no share, no rating badge.
/// Those are facts and actions about the product, not about the picture, and
/// putting controls on photography is what made them invisible against a
/// white-background product shot. They live in the pinned app bar and beside
/// the title instead.
///
/// The one overlay that stays is the image counter, which is genuinely about
/// the gallery. A counter rather than dots: dots stop being countable past four
/// or five, and a gallery is exactly where a shopper wants to know how much is
/// left to look at.
class ProductGallery extends StatefulWidget {
  const ProductGallery({
    super.key,
    required this.images,
    this.onImageTap,
  });

  final List<String> images;

  /// Opens the full-screen viewer at the tapped page.
  final ValueChanged<int>? onImageTap;

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
              itemBuilder: (context, i) => GestureDetector(
                onTap: widget.onImageTap == null
                    ? null
                    : () => widget.onImageTap!(i),
                child: Image.network(
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
          ),
          if (widget.images.length > 1)
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  // Still a scrim: this one does sit on unpredictable
                  // photography, so it cannot inherit a theme surface colour.
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_index + 1}/${widget.images.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

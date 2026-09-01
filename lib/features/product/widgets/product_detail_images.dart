import 'package:flutter/material.dart';

import '../../../core/images/app_images.dart';

/// The seller's long-form photography, stacked full width.
///
/// These are the close-ups, size charts and fabric shots a wholesale listing
/// carries below the fold: the pictures that answer what the five gallery shots
/// cannot. They arrive inside the description markup, which this page has until
/// now rendered as text and thrown the pictures away -- one live listing had
/// twenty-one of them in it.
///
/// Full width and stacked rather than a grid of squares, because that is what
/// they are: page-width panels, often with writing on them, that a square crop
/// would cut the words off. Built lazily, so a listing with fifty of them costs
/// the page nothing until they are scrolled to.
class ProductDetailImages extends StatelessWidget {
  const ProductDetailImages({super.key, required this.images, this.onImageTap});

  final List<String> images;

  /// Opens the full-screen viewer at the tapped image.
  final ValueChanged<int>? onImageTap;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < images.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: onImageTap == null ? null : () => onImageTap!(i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image(
                  image: AppImages.of(
                    images[i],
                    // Page width, so a 1000px panel is not decoded at seven
                    // times the pixels it is drawn at.
                    width: MediaQuery.sizeOf(context).width.round().toDouble(),
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  ),
                  fit: BoxFit.fitWidth,
                  // Height is whatever the picture is. These are not a
                  // consistent shape and forcing one would crop the size chart
                  // that is the whole reason to look at them.
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : Container(
                          height: 160,
                          alignment: Alignment.center,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/images/app_images.dart';
import '../../core/theme/app_theme.dart';

/// Artwork for a tile: a photograph when one is available, and a tinted panel
/// with an icon when it is not.
///
/// One implementation shared by category tiles, department tiles, deal cards
/// and product cards so they cannot drift apart.
///
/// The tinted panel is not a placeholder that got left in -- it is the loading
/// and failure state. A shopper on a slow Nepali connection sees a coloured
/// panel rather than a grey hole, and a dead image URL degrades to the same
/// thing instead of a broken-image glyph.
class ArtworkPanel extends StatelessWidget {
  const ArtworkPanel({
    super.key,
    required this.icon,
    required this.tint,
    this.imageUrl,
    this.aspectRatio,
    this.iconScale = 0.42,
    this.knownWidth,
  });

  final IconData icon;
  final Color tint;

  /// Photograph to show in place of the icon. Null falls back to the panel.
  final String? imageUrl;

  /// Null fills whatever space the parent gives, which is what keeps a tile
  /// from overflowing when the device's text scale makes the label taller
  /// than the layout assumed. Pass a ratio only where the panel drives the
  /// size rather than the other way round.
  final double? aspectRatio;

  /// Icon size as a fraction of the panel's shorter side.
  final double iconScale;

  /// The panel's width, when the caller already knows it.
  ///
  /// Supplying it skips the [LayoutBuilder] this widget otherwise needs to
  /// size the decode. That matters in bulk: the browse grid puts one of these
  /// in each of about eleven hundred tiles, and a LayoutBuilder per tile is a
  /// layout callback per tile.
  final double? knownWidth;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;

    final content = url == null || url.isEmpty ? _fallback() : _image(url);

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(alpha: 0.28),
              tint.withValues(alpha: 0.10),
            ],
          ),
        ),
        child: SizedBox.expand(child: content),
      ),
    );

    final ratio = aspectRatio;
    return ratio == null
        ? panel
        : AspectRatio(aspectRatio: ratio, child: panel);
  }

  /// The photograph, requested and decoded at the size it will actually be
  /// drawn.
  ///
  /// The browse tree holds well over a thousand of these at once. Decoding each
  /// at full resolution -- a 1000px catalogue photo in a 116px tile is roughly
  /// seventy times the pixels it needs -- fills the image cache with bitmaps
  /// nobody can see; downloading each at full resolution costs about 260 KB
  /// where 15 would do. [AppImages.of] handles both from the one width, and
  /// caches the result to disk so it is fetched once rather than once a
  /// launch.
  Widget _image(String url) {
    final known = knownWidth;
    if (known != null && known > 0) {
      // No LayoutBuilder needed: the caller measured once for the whole grid
      // rather than making every tile measure itself.
      return Builder(builder: (context) => _photo(context, url, known));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return _photo(context, url, width.isFinite && width > 0 ? width : null);
      },
    );
  }

  Widget _photo(BuildContext context, String url, double? width) =>
      _ArtworkImage(
        url: url,
        width: width,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        fallback: _fallback,
      );

  Widget _fallback() {
    final known = knownWidth;
    if (known != null && known > 0) {
      return Center(
        child: Icon(icon, size: known * iconScale, color: tint),
      );
    }

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shorter = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight;
          return Icon(icon, size: shorter * iconScale, color: tint);
        },
      ),
    );
  }
}

/// The photograph itself, with one retry at full size.
///
/// The sized variant is a suffix on a CDN URL that is not ours. If that host
/// ever changes its format, every product picture in the app would quietly
/// become a coloured panel -- and the panel is a good enough placeholder that
/// nobody would notice it had happened. So a failure falls back to the original
/// URL once before giving up, which turns a silent app-wide quality regression
/// into a slower load.
class _ArtworkImage extends StatefulWidget {
  const _ArtworkImage({
    required this.url,
    required this.width,
    required this.devicePixelRatio,
    required this.fallback,
  });

  final String url;

  /// Logical width the picture is drawn at, or null where it is not known.
  final double? width;
  final double devicePixelRatio;

  /// The tinted panel: this widget's loading state and its last resort.
  final Widget Function() fallback;

  @override
  State<_ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends State<_ArtworkImage> {
  /// Set once the sized request has failed, so the original is asked for.
  bool _unsized = false;

  @override
  void didUpdateWidget(_ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new picture in the same slot deserves its own attempt at the small
    // one, rather than inheriting the last one's failure.
    if (oldWidget.url != widget.url) _unsized = false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = AppImages.of(
      widget.url,
      width: widget.width,
      devicePixelRatio: widget.devicePixelRatio,
      // The retry asks for the original file but still decodes it down to this
      // tile. Dropping the width instead would fix the picture and blow up the
      // memory, which is trading one bug for a worse one.
      sized: !_unsized,
    );

    return Image(
      image: provider,
      fit: BoxFit.cover,
      // Fade in so a late-arriving image does not snap into place.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : widget.fallback(),
      errorBuilder: (context, error, stack) {
        if (!_unsized && widget.width != null) {
          // After the frame: this fires during build, and setState from inside
          // one is an assertion rather than a warning.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _unsized = true);
          });
        }
        return widget.fallback();
      },
    );
  }
}

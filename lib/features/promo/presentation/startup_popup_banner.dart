import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/images/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../data/popup_banner.dart';

/// What the popup reports back when it closes.
enum PopupResult { closed, followed }

/// The campaign artwork over a dimmed storefront, with a close button on its
/// corner -- shown once after startup.
///
/// A phone-sized card on every screen: a tablet or a desktop window gets the
/// same portrait artwork, centred, rather than a poster stretched across it.
class StartupPopupBanner extends StatelessWidget {
  const StartupPopupBanner({
    super.key,
    required this.banner,
    required this.image,
    required this.onClose,
    required this.onTap,
  });

  final PopupBanner banner;
  final ImageProvider image;
  final VoidCallback onClose;
  final VoidCallback onTap;

  /// Portrait, like the campaign designs.
  static const double aspect = 9 / 16;
  static const double maxWidth = 420;

  /// The provider for [banner]'s artwork at the size the card draws it.
  static ImageProvider imageFor(BuildContext context, PopupBanner banner) {
    final media = MediaQuery.of(context);
    return AppImages.of(
      banner.imageUrl,
      width: cardSize(media.size).width,
      devicePixelRatio: media.devicePixelRatio,
    );
  }

  /// Swaps the decode step out, for tests. A decode begun inside a widget
  /// test's fake clock never finishes, so without this the popup could not be
  /// opened from the home screen in a test at all.
  @visibleForTesting
  static Future<bool> Function(ImageProvider image)? decodeOverride;

  /// Decodes [image] ahead of showing it. False if it cannot be loaded.
  static Future<bool> decode(BuildContext context, ImageProvider image) async {
    final override = decodeOverride;
    if (override != null) return override(image);
    var loaded = true;
    await precacheImage(image, context, onError: (_, _) => loaded = false);
    return loaded;
  }

  /// 84% of the width, capped at [maxWidth] and at 78% of the height, keeping
  /// the portrait shape whichever limit wins.
  static Size cardSize(Size screen) {
    var width = math.min(screen.width * 0.84, maxWidth);
    final maxHeight = screen.height * 0.78;
    if (width / aspect > maxHeight) width = maxHeight * aspect;
    return Size(width, width / aspect);
  }

  /// Opens the popup. The artwork must already be decoded -- see the caller in
  /// the home screen -- so the card never appears as an empty box.
  static Future<PopupResult?> show(
    BuildContext context, {
    required PopupBanner banner,
    required ImageProvider image,
  }) {
    return showGeneralDialog<PopupResult>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Promotion',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) => StartupPopupBanner(
        banner: banner,
        image: image,
        onClose: () => Navigator.of(dialogContext).pop(PopupResult.closed),
        onTap: () => Navigator.of(dialogContext).pop(PopupResult.followed),
      ),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = cardSize(MediaQuery.sizeOf(context));
    // Half the button hangs outside the card's corner, as in the design, so
    // the frame is that much larger than the card itself.
    const button = 36.0;
    const overhang = button / 2;

    return SafeArea(
      child: Center(
        child: SizedBox(
          width: size.width + overhang,
          height: size.height + overhang,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: overhang,
                width: size.width,
                height: size.height,
                child: Semantics(
                  button: true,
                  image: true,
                  label: banner.altText ?? 'Promotion',
                  child: Material(
                    color: Colors.transparent,
                    elevation: 8,
                    shadowColor: Colors.black54,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const ValueKey('popup-artwork'),
                      onTap: onTap,
                      child: Ink.image(image: image, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
              // A 44 point target around a 36 point circle.
              Positioned(
                right: -4,
                top: -4,
                width: button + 8,
                height: button + 8,
                child: Semantics(
                  button: true,
                  label: 'Close',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('popup-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: Center(
                      child: Container(
                        width: button,
                        height: button,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 22,
                          color: Color(0xFF1A1A1A),
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
    );
  }
}

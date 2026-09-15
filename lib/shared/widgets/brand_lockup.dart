import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import 'brand_wordmark.dart';

/// The brand as the header shows it: the mark, the name, and the line under it.
///
/// **The mark is the supplied artwork**, unmodified -- [BrandWordmark] draws
/// the official SVG, in the on-dark version made for the band it sits on.
///
/// The name beside it is set in type rather than drawn from the lockup file,
/// and the reason is worth writing down: the supplied lockup
/// ([AppBrand.lockupAsset]) is artwork for a *light* ground. Its name is Trust
/// Blue and its tagline is black -- the first is the colour of the band itself
/// and the second is invisible on it, so putting that file on the header would
/// hide two thirds of the logo. The type here follows the lockup's own
/// arrangement: the name, then `.com` in Commerce Orange, with the tagline
/// beneath in letter-spaced caps.
///
/// [AppBrand.lockupOnDarkAsset] is the way out of that. Drop an on-dark lockup
/// at that path and this draws it instead, with no code change -- the asset
/// folder is declared wholesale in the pubspec, and the fallback below is what
/// runs until the file is there.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.height = 30, this.behind});

  /// How tall the mark is drawn.
  ///
  /// The name is sized from it -- they are one lockup and have to stay in
  /// proportion -- but the tagline is not: that has its own specified size,
  /// small enough to read as a line under a logo rather than as a slogan.
  ///
  /// 30 puts the whole block at about 130pt wide, which is the width the
  /// design asks for. A smaller screen gets a smaller mark; see the header.
  final double height;

  /// The tagline's size, which the specification fixes rather than derives.
  static const double taglineSize = 10.5;

  /// What the lockup is being drawn on, which decides which mark is used.
  final Color? behind;

  @override
  Widget build(BuildContext context) {
    final ground = behind ?? AppColors.brandBandTop;

    return Semantics(
      label: AppBrand.name,
      image: true,
      excludeSemantics: true,
      child: Image.asset(
        AppBrand.lockupOnDarkAsset,
        height: height * 1.5,
        fit: BoxFit.contain,
        // Until that file exists -- and it does not yet -- the mark and the
        // type below stand in for it.
        errorBuilder: (context, _, _) => _typeset(context, ground),
      ),
    );
  }

  Widget _typeset(BuildContext context, Color ground) {
    final theme = Theme.of(context);

    // A logo is drawn at a size, not set at one. The mark beside this type is
    // an SVG at a fixed height, and type that grew with the device's text
    // setting would leave the two out of proportion -- and at 2x it simply ran
    // off the end of the row.
    return MediaQuery.withNoTextScaling(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BrandWordmark(height: height, background: ground),
          SizedBox(width: height * 0.26),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The name, with the suffix in the orange the supplied lockup puts
              // it in. Sized from the mark so the two stay in proportion.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'gtradea',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: height * 0.63,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                    TextSpan(
                      text: '.com',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: height * 0.4,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: AppColors.commerceOrange,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: height * 0.13),
              // The tagline, quiet and spaced out under the name -- the lockup's
              // own arrangement. Small enough that the header reads as a brand
              // rather than as a slogan.
              Text(
                'Beyond Borders.',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: taglineSize,
                  height: 1,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w400,
                  color: AppColors.onPrimary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

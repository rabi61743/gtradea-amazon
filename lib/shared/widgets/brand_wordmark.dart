import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The shop's own name, in one place.
///
/// Still needed now that the header shows the mark rather than the name: the
/// name is what prose says -- "New to GtradeA?", "About GtradeA" -- and a logo
/// cannot sit inside a sentence.
abstract final class AppBrand {
  /// As written everywhere it is spoken about rather than shown as a mark.
  static const name = 'GtradeA';

  /// The mark for a light surface: orange and Trust Blue.
  static const logoAsset = 'assets/brand/logo.svg';

  /// The mark for a dark surface: orange and the palette near-white.
  ///
  /// Same geometry, one fill changed. It exists because the light mark's blue
  /// quarter is Trust Blue and so is the header band, so on the band that
  /// quarter is not low-contrast -- it is *the same colour*, and half the logo
  /// disappears.
  static const logoOnDarkAsset = 'assets/brand/logo_on_dark.svg';

  /// The full lockup: the mark, the name and the line under it, as supplied.
  ///
  /// For the places that introduce the shop rather than label it -- the
  /// sign-in page is the one that does. Everywhere else keeps the mark on its
  /// own, which is what fits a header bar.
  static const lockupAsset = 'assets/brand/logo_lockup.png';

  /// The same lockup drawn for a dark ground, when there is one.
  ///
  /// There is not yet: [lockupAsset] is light-ground artwork -- Trust Blue
  /// name, black tagline -- so on the header's band its name would be the
  /// colour of the band and its tagline would be invisible. [BrandLockup]
  /// looks for this file and falls back to the mark plus type until it is
  /// supplied. The asset folder is declared wholesale in the pubspec, so
  /// dropping the artwork in at this path is the whole of the change.
  static const lockupOnDarkAsset = 'assets/brand/logo_lockup_on_dark.png';

  /// The lockup's aspect ratio, from the artwork: 8073 by 1686.
  static const lockupAspectRatio = 8073 / 1686;

  /// The mark's aspect ratio, from the artwork's viewBox: 173.6 by 158.7.
  ///
  /// Named so callers reserve the right shape rather than guessing a box and
  /// letting the logo letterbox inside it. Both files share it.
  static const logoAspectRatio = 173.6 / 158.7;

  /// Which mark belongs on [background].
  ///
  /// The decision is made from the colour actually behind the logo rather than
  /// from the app's theme brightness, because those are not the same question:
  /// this app is pinned to the light theme and its header is a dark teal band.
  /// A brightness check would put the light-surface mark on the band, which is
  /// the bug this exists to prevent.
  static String logoFor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? logoOnDarkAsset
      : logoAsset;
}

/// The brand mark, in whichever version suits what is behind it.
///
/// Drawn from vector, at whatever size the caller gives it -- no bitmap, so no
/// density at which it softens.
///
/// Deliberately not tinted. The mark is two specific colours and stays that
/// way; what changes between the two files is which second colour, not whether
/// there is one. Flattening it to a single ink would throw away half the
/// identity, which is what tinting a two-colour logo always does.
///
/// The class name is unchanged from when this was type. Renaming it would touch
/// every screen that positions it for no gain, and what it means -- "the brand,
/// here" -- is exactly what it meant before.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.height = _headerHeight,
    this.background,
    this.alignment = AlignmentDirectional.centerStart,
  });

  /// How tall to draw the mark. The width follows from the artwork's own
  /// proportions, so there is no way for a caller to squash it.
  final double height;

  /// What the logo is being drawn on top of.
  ///
  /// Null reads the theme's surface colour, which is right for a card or a
  /// page. A caller painting its own band -- the header does -- passes that
  /// band's colour, because the theme cannot know about it.
  final Color? background;

  /// Where the mark sits in whatever box it is given.
  ///
  /// Start by default, which is what a header row wants. It matters because the
  /// Align inside expands to fill a loose box -- so a caller that centres this
  /// widget and leaves the default gets the mark pinned to the left edge of it,
  /// which is exactly what the loader's ring did.
  final AlignmentGeometry alignment;

  /// Sized to the row it lives in: the header reserves 48pt for the bell's tap
  /// target, and a mark filling that would crowd the icons beside it.
  static const _headerHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    final behind = background ?? Theme.of(context).colorScheme.surface;

    return Semantics(
      // The mark carries the company's identity, so it has to say the company's
      // name to anyone who cannot see it. Without this the header opens with an
      // unlabelled graphic.
      label: AppBrand.name,
      image: true,
      child: Align(
        alignment: alignment,
        child: SvgPicture.asset(
          AppBrand.logoFor(behind),
          height: height,
          // Fits rather than fills, so the mark keeps its proportions whatever
          // box it is handed.
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

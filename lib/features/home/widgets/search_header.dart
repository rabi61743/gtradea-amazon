import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/animated_search_hint.dart';
import '../../../shared/widgets/brand_wordmark.dart';
import '../../auth/data/auth_store.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../profile/data/profile_store.dart';
import '../../address/presentation/delivery_location_button.dart';
import '../../orders/presentation/order_tracker_button.dart';
import '../../support/presentation/support_button.dart';
import '../../search/widgets/voice_search_sheet.dart';

/// The brand band at the top of home: the mark, the icons, and search.
///
/// Two rows rather than one. The mark and the icons are chrome and share a row;
/// the search pill gets the full width below them. Putting the bell beside the
/// pill, as it was, left the pill short and gave the mark nowhere to sit.
///
/// **One band, painted once.** This widget draws no background of its own. The
/// shell puts a single top-to-bottom gradient behind it and the department
/// strip together -- [AppColors.brandBand], dark teal at the status bar easing
/// into the brand teal by the time it reaches the products.
///
/// One decoration for both, deliberately. Giving each its own gradient would
/// run the ramp twice and snap back to the dark end at the join, which is the
/// seam this header has already had removed once.
///
/// Everything lines up on a single [_edge] inset -- see [_bellEdge] for the one
/// number that looks wrong and is not. The pill is deliberately white in both
/// brightnesses because it sits on the teal rather than on the page
/// background, so every child pins its own colour or inherits one that would
/// vanish against it.
class SearchHeader extends StatelessWidget {
  const SearchHeader({
    super.key,
    // The fixed lead of the placeholder. The example after it is animated --
    // see [AnimatedSearchHint] -- so this is the half that stays put.
    this.hintText = 'Search ',
    this.onTap,
    this.onImageSearch,
    this.onVoiceResult,
  });

  final String hintText;
  final VoidCallback? onTap;
  final VoidCallback? onImageSearch;

  /// Called with what the shopper dictated, once, only when something was
  /// heard.
  final ValueChanged<String>? onVoiceResult;

  /// The one inset everything in this header resolves to.
  static const double _edge = 16;

  /// The search pill, so a test can measure the edges this header is about.
  static const pillKey = ValueKey('home-search-pill');

  /// The glyph size the three header icons share.
  ///
  /// Smaller than Material's 24 so the row reads as chrome rather than as
  /// three buttons, and smaller again since -- 21 to 19. The box around each
  /// stays 48, which is what a finger has to find, so this changes what is
  /// drawn and not what can be pressed.
  ///
  /// [_bellEdge] is derived from this, so shrinking it here keeps the bell on
  /// the margin instead of walking it off. That derivation exists because a
  /// hardcoded inset did exactly that the last time these icons were resized.
  static const double _headerIconSize = 19;

  /// A Material [IconButton] centres its glyph in a 48pt box, so the leftover
  /// is invisible padding. Aligning the box would leave the bell looking short
  /// of the pill below it; this aligns the *glyph* instead, and the tap target
  /// stays a full 48.
  ///
  /// Derived rather than the constant 12 it used to be. That 12 was half of
  /// (48 - 24) and silently assumed a 24pt glyph, so shrinking the icons pushed
  /// the bell 1.5pt past its margin -- a drift nobody would have looked for.
  static const double _iconBox = 48;
  static const double _bellEdge = _edge - (_iconBox - _headerIconSize) / 2;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The band already fills the status bar area. Without this the icons in
      // it are drawn dark on dark teal.
      value: AppTheme.brandBandOverlay,
      // No background of its own -- see the class doc. The shell paints the
      // band behind this and the department strip together.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            // Horizontal insets live here rather than on the container, so
            // the colour still reaches both edges.
            padding: EdgeInsets.fromLTRB(
              _edge,
              // The status bar inset is absorbed here rather than by a
              // SafeArea so the teal runs behind it instead of stopping at a
              // white strip.
              MediaQuery.of(context).padding.top + 6,
              _bellEdge,
              6,
            ),
            child: SizedBox(
              // Fixed to the bell's own tap target, so the row does not grow
              // or shrink when the wordmark is scaled by a text size setting.
              height: 48,
              child: Row(
                children: [
                  // Fixed rather than Expanded now that the delivery line has
                  // the flexible slot. The mark is the same size and still
                  // starts at the same 16pt inset, so nothing about it moved.
                  //
                  // Told what it is sitting on. The theme's surface colour
                  // would have the mark pick its light-surface version, whose
                  // blue quarter is Trust Blue -- which this band is a shade
                  // of, so half the logo would vanish into it.
                  //
                  // The band's *top* colour, since that is where the mark
                  // sits now that the band is a ramp. It is darker than the
                  // flat teal was, so the on-dark mark is still the right one.
                  const BrandWordmark(background: AppColors.brandBandTop),
                  const SizedBox(width: 6),
                  // Takes the space the wordmark's Expanded used to hold, which
                  // is why adding it moves neither the logo to its left nor the
                  // icons to its right.
                  const Expanded(child: DeliveryLocationButton()),
                  // Four, not twelve, and ahead of the group rather than
                  // between them: adjacent IconButtons already carry 12pt of
                  // invisible padding each, so a 12pt gap between them would
                  // read as twice the space of the one to the delivery line.
                  const SizedBox(width: 4),
                  const SupportButton(
                    color: AppColors.onPrimary,
                    size: _headerIconSize,
                  ),
                  const OrderTrackerButton(
                    color: AppColors.onPrimary,
                    size: _headerIconSize,
                  ),
                  const NotificationBell(
                    color: AppColors.onPrimary,
                    size: _headerIconSize,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            // Its own insets now that the deeper strip above carries the
            // bell's asymmetric one. The pill sits on _edge at both sides,
            // which is what it always measured out to -- it just used to get
            // there by cancelling the container's right inset back out.
            padding: const EdgeInsets.fromLTRB(_edge, 4, _edge, 8),
            child: Row(
              children: [
                // Sizes to its words and takes nothing when there is nobody to
                // greet, so the pill keeps the full width it had for a signed
                // out shopper.
                const _Greeting(),
                Expanded(
                  child: _SearchPill(
                    key: pillKey,
                    hintText: hintText,
                    onTap: onTap,
                    onImageSearch: onImageSearch,
                    onVoiceResult: onVoiceResult,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Hi, Pravakar" beside the search pill.
///
/// The name is the account's own -- [ProfileStore.displayName], which prefers
/// the gateway's profile row over the session's copy and falls back to the
/// part of the email before the @. Nothing here is written down.
///
/// **The first word only.** A greeting uses a first name, and the header has
/// one row to share with the search pill: a full name would push the pill
/// narrow on the phones this ships to.
///
/// Nothing at all when signed out. There is no name to use, and "Hi, Guest"
/// is a greeting to nobody.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AuthStore.instance, ProfileStore.instance]),
      builder: (context, _) {
        if (!AuthStore.instance.isSignedIn) return const SizedBox.shrink();

        final full = ProfileStore.instance.displayName?.trim() ?? '';
        if (full.isEmpty) return const SizedBox.shrink();
        final first = full.split(RegExp(r'\s+')).first;

        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ConstrainedBox(
            // A long name gives way to the pill rather than squeezing it.
            constraints: const BoxConstraints(maxWidth: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The greeting leads and the name follows it, smaller: the
                // word is the same every time, and the name is the part worth
                // reading.
                Text(
                  'Hi,',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                Text(
                  first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.onPrimary.withValues(alpha: 0.85),
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({
    super.key,
    required this.hintText,
    required this.onTap,
    required this.onImageSearch,
    required this.onVoiceResult,
  });

  final String hintText;
  final VoidCallback? onTap;
  final VoidCallback? onImageSearch;
  final ValueChanged<String>? onVoiceResult;

  @override
  Widget build(BuildContext context) {
    final onPill = Colors.black.withValues(alpha: 0.55);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: SizedBox(
          // Trimmed from 44 by request. Short for a tap target, which this
          // pill gets away with because it is the full width of the header --
          // the height is the only tight dimension, and the whole bar answers
          // the tap.
          height: 38,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.search, size: 18, color: onPill),
              const SizedBox(width: 8),
              Expanded(
                // The pill is a button, not a field -- nothing is typed here,
                // so the hint cycles freely until the shopper taps through to
                // the search screen, where it stops the moment they type.
                child: AnimatedSearchHint(
                  prefix: hintText,
                  style: TextStyle(fontSize: 13.5, color: onPill),
                ),
              ),
              // Voice first, then image: they read as a pair of ways to search
              // without typing, and the cheaper one leads.
              if (onVoiceResult != null)
                VoiceSearchButton(
                  color: onPill,
                  // 18 gives it the same 32pt box the image button now has.
                  size: 18,
                  onResult: onVoiceResult!,
                ),
              IconButton(
                icon: Icon(Icons.center_focus_weak, size: 18, color: onPill),
                tooltip: 'Search by image',
                // Matched to the voice button so the two sit level rather than
                // one carrying a 48pt box and the other a 32pt one.
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                onPressed: onImageSearch,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

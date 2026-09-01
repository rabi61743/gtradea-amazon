import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Names the option under the pointer.
///
/// One widget for every place a colourway or a size is shown short: the
/// swatch row, the grid's row labels and its size headers all cut names the
/// seller wrote long, and all three now say the whole thing the same way
/// rather than each inventing a bubble.
///
/// **Above, not below.** A finger held on an option covers what is under it,
/// so a tooltip below the thing being named is a tooltip behind a thumb.
///
/// **Hover raises it, and so does a tap.** A long press does nothing, and a
/// tap on a swatch still selects it -- the tooltip shares the tap rather than
/// taking it, which is the one thing this must not break.
class VariantTooltip extends StatelessWidget {
  const VariantTooltip({super.key, required this.message, required this.child});

  /// The seller's own name for the option, off the variant record.
  final String message;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: message,
      // Above the option, and clear of it.
      preferBelow: false,
      verticalOffset: 22,
      // Hover wherever there is a pointer; a tap where there is not.
      //
      // Hover is what was asked for, and [Tooltip] serves it from its own
      // mouse region no matter what `triggerMode` says -- so a pointer
      // resting on an option names it immediately on desktop and web.
      //
      // `triggerMode` only decides which *gesture* also raises it, and a
      // touch screen cannot hover: leaving it on `manual` meant the names
      // were unreachable on a phone, which is most of this shop's traffic.
      // `tap` is the one gesture that costs nothing -- the long press is off,
      // and a tap on a swatch still selects it, because [Tooltip] shares the
      // tap rather than consuming it.
      triggerMode: TooltipTriggerMode.tap,
      // Immediate, because the point of the thing is to answer a question the
      // pointer is asking now.
      waitDuration: Duration.zero,
      // How long a tapped one stays up. The 1.5s default is not long enough
      // to read "Polo (black and white)" before it goes, and on touch this is
      // the only way the name can be had.
      showDuration: const Duration(seconds: 3),
      // How long it lingers once a pointer leaves.
      exitDuration: const Duration(milliseconds: 100),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        // The app's own dark surface rather than Flutter's translucent grey:
        // a name read against a product photograph needs to be opaque.
        color: AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
      // The callers wrap this in Semantics carrying the same name; a second
      // from the tooltip would have a screen reader say it twice.
      excludeFromSemantics: true,
      child: child,
    );
  }
}

/// Marks a label as having more behind it.
///
/// The dotted rule under a clipped name is what says the rest can be had --
/// without it the tooltip is a secret, because nothing on a truncated label
/// suggests hovering or holding it would do anything.
TextStyle? withTooltipHint(TextStyle? style, ThemeData theme) =>
    style?.copyWith(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: theme.colorScheme.onSurfaceVariant.withValues(
        alpha: 0.6,
      ),
    );

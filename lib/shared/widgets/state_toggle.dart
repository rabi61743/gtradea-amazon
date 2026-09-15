import 'package:flutter/material.dart';

/// A switch with its state in words beside it.
///
/// The one toggle this app uses for a setting that is simply on or off, so the
/// notification groups and the sound switch cannot drift into looking like two
/// different controls for the same kind of decision.
///
/// The framework's switch shrinks its thumb to a dot when off and grows it when
/// on, which reads as the control jumping; a thumb carrying an icon stays one
/// size in both states. Off gets a real edge and a real thumb, so it reads as
/// "off" rather than as missing.
///
/// It was private to the notification settings screen. It is here now because
/// the sound row wanted the same control, and the alternative -- a second copy
/// of the same forty lines of switch styling -- is how two toggles end up
/// almost matching.
class StateToggle extends StatelessWidget {
  const StateToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;

  /// Null disables the control, which is what a row uses while a save is in
  /// flight: the switch stays where it is rather than accepting a second tap.
  final ValueChanged<bool>? onChanged;

  /// How long the word beside the switch takes to change colour. Matches the
  /// card fade on the notification screen, which is where this came from.
  static const fade = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offInk = scheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fixed width, so "On" and "Off" do not nudge the switch sideways.
        SizedBox(
          width: 28,
          child: AnimatedDefaultTextStyle(
            duration: fade,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: enabled ? scheme.primary : offInk,
            ),
            child: Text(enabled ? 'On' : 'Off'),
          ),
        ),
        const SizedBox(width: 6),
        Switch(
          value: enabled,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          thumbIcon: WidgetStateProperty.resolveWith(
            (states) => Icon(
              states.contains(WidgetState.selected) ? Icons.check : Icons.close,
              size: 14,
              color: states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.surface,
            ),
          ),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : offInk,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surface,
          ),
          trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.transparent
                : offInk,
          ),
        ),
      ],
    );
  }
}

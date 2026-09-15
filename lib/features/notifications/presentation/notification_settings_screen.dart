import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/state_toggle.dart';
import '../data/notification_store.dart';

/// What the shopper wants to be told about.
///
/// Four switches, not eleven. Nobody wants "Order packed" but not "Order
/// shipped", and a page of eleven toggles is a page nobody reads. Each switch
/// lists the categories it covers, so the grouping is visible rather than
/// something to be guessed at.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    NotificationSettings.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: NotificationSettings.instance,
      builder: (context, _) {
        final settings = NotificationSettings.instance;

        return Scaffold(
          appBar: AppBar(title: const Text('Notification settings')),
          body: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              for (final group in NotificationGroup.values)
                _GroupSwitch(
                  group: group,
                  enabled: settings.isEnabled(group),
                  onChanged: (value) => settings.setEnabled(group, value),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  // Said plainly rather than discovered: a shopper who turns
                  // order updates back on and finds no history of what they
                  // missed would reasonably think it was broken.
                  'Switching a group off stops new notifications of that kind. '
                  'Anything sent while it was off is not kept, so turning it '
                  'back on will not fill in what you missed.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupSwitch extends StatelessWidget {
  const _GroupSwitch({
    required this.group,
    required this.enabled,
    required this.onChanged,
  });

  final NotificationGroup group;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final covered = NotificationCategory.values
        .where((category) => category.group == group)
        .toList();

    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppTheme.radiusCard);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      // One control, not a card with a control in its corner: the whole card
      // answers a tap, and a screen reader hears one toggle with its label.
      child: MergeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () => onChanged(!enabled),
            // The state is said by the card as well as by the switch -- a
            // breath of the brand colour on, the plain card off -- and it
            // fades between the two rather than cutting.
            child: AnimatedContainer(
              duration: _fade,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: radius,
                color: enabled
                    ? Color.alphaBlend(
                        scheme.primary.withValues(alpha: 0.05),
                        scheme.surface,
                      )
                    : scheme.surface,
                border: Border.all(
                  color: enabled
                      ? scheme.primary.withValues(alpha: 0.35)
                      : scheme.outlineVariant,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.label,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              group.detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StateToggle(enabled: enabled, onChanged: onChanged),
                    ],
                  ),
                  if (covered.length > 1) ...[
                    const SizedBox(height: 10),
                    // The categories this switch actually governs, so the
                    // grouping is something the shopper can see rather than
                    // infer. Always laid out, on or off, so the card never
                    // grows or shrinks under the thumb that just tapped it.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final category in covered)
                          _CategoryChip(category: category, enabled: enabled),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's own fade between its on and off grounds.
///
/// The switch beside it fades on the same timing -- see [StateToggle.fade],
/// which is where this control's styling now lives, shared with the sound row
/// on the account page.
const _fade = StateToggle.fade;

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.enabled});

  final NotificationCategory category;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: _fade,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: base,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

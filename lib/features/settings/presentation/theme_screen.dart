import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_settings.dart';

/// Pick how the app looks. The same shape as the language picker: one card
/// per choice, the chosen one marked, and the change applied on tap.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  /// The label the account page shows beside the row.
  static String labelFor(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };

  static const _options = [
    (
      ThemeMode.light,
      Icons.light_mode_outlined,
      'Bright background with dark text. Good for daytime.',
    ),
    (
      ThemeMode.dark,
      Icons.dark_mode_outlined,
      'Dark background with light text. Easier on the eyes in low light.',
    ),
    (
      ThemeMode.system,
      Icons.brightness_auto_outlined,
      'Follows your device. Switches when your device changes between '
          'light and dark.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: ThemeSettings.instance,
      builder: (context, _) {
        final current = ThemeSettings.instance.mode;
        return Scaffold(
          appBar: AppBar(title: const Text('Theme')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Choose how the app looks.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final (mode, icon, detail) in _options)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ThemeOption(
                            icon: icon,
                            title: labelFor(mode),
                            detail: detail,
                            isSelected: mode == current,
                            onTap: () => ThemeSettings.instance.setMode(mode),
                          ),
                        ),
                    ],
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

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.title,
    required this.detail,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            // The tint laid over the card colour, not the page: over the dark
            // page the chosen card read darker than the others.
            color: isSelected
                ? Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.1),
                    scheme.surface,
                  )
                : scheme.surface,
            border: Border.all(
              color: isSelected
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The mark is always laid out, so choosing a row does not shift
              // its text sideways.
              AnimatedOpacity(
                opacity: isSelected ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(Icons.check_circle, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

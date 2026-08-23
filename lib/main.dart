import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';

void main() {
  runApp(const GtradeaAmazonApp());
}

class GtradeaAmazonApp extends StatelessWidget {
  const GtradeaAmazonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GtradeA Amazon',
      debugShowCheckedModeBanner: false,
      // The GtradeA palette, white version: light is pinned rather than left on
      // ThemeMode.system so the app does not follow a phone set to dark. The
      // dark ThemeData is still built and ready if that ever changes.
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      home: const HomePage(),
    );
  }
}

/// Placeholder home. Here to show the brand theme applied to real widgets, not
/// to be the eventual shape of the app.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GtradeA Amazon'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GtradeA Amazon',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Brand theme, white version',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('Primary action'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Secondary action'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text('Teal primary')),
                  Chip(label: Text('Warm cream')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

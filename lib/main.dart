import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';

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
      home: const HomeScreen(),
    );
  }
}

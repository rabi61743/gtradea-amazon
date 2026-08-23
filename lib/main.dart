import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';

void main() {
  runApp(const GtradeaAmazonApp());
}

class GtradeaAmazonApp extends StatelessWidget {
  const GtradeaAmazonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Rebuilt from the root when the language changes, so a screen already
      // open picks up the new wording rather than only the next one pushed.
      listenable: LanguageStore.instance,
      builder: (context, _) => MaterialApp(
        title: 'GtradeA Amazon',
        debugShowCheckedModeBanner: false,
        // The GtradeA palette, white version: light is pinned rather than left
        // on ThemeMode.system so the app does not follow a phone set to dark.
        // The dark ThemeData is still built and ready if that ever changes.
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        // Declared so the framework's own widgets follow the choice, not only
        // the strings this app writes. The delegates are not optional once a
        // non-English locale is set: without them Material widgets have no
        // localizations to read and throw on the first tooltip or nav bar.
        locale: Locale(LanguageStore.instance.language.code),
        supportedLocales: [
          for (final language in AppLanguage.values) Locale(language.code),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeScreen(),
      ),
    );
  }
}

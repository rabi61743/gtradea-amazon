import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/dev/frame_probe.dart';
import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';

void main() {
  // Needed before the image cache can be touched, and cheap: runApp would call
  // it a moment later anyway.
  WidgetsFlutterBinding.ensureInitialized();

  // A stated budget rather than the framework's unexamined default of 1000
  // objects and 100 MB.
  //
  // The object count is what matters here. The browse tree holds about eleven
  // hundred subcategory tiles and the home page a few hundred product
  // pictures, so the default count is reached long before the byte budget is
  // -- and once it is, the cache evicts pictures that are still on screen and
  // immediately decodes them again. Every one of them is bounded by a
  // ResizeImage now, so 1500 small bitmaps is a smaller working set than the
  // 100 MB ceiling implies.
  PaintingBinding.instance.imageCache
    ..maximumSize = 1500
    ..maximumSizeBytes = 120 << 20;

  // Profile builds only, and a no-op in debug and release. See the file for why
  // Android's own frame tooling cannot measure a Flutter app.
  FrameProbe.start();
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

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/audio/sound_settings.dart';
import 'core/dev/frame_probe.dart';
import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_settings.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  // Needed before the image cache can be touched, and cheap: runApp would call
  // it a moment later anyway.
  WidgetsFlutterBinding.ensureInitialized();

  // Awaited, unlike the others: the first frame is painted in whatever theme
  // is known by then, and a saved Dark that arrived a frame late would open
  // on a white flash. It is one small read from local storage.
  await ThemeSettings.instance.load();

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

  // Read before the first screen can play anything. It defaults to on, so a
  // slow read is never wrongly silent -- but a shopper who turned sound off
  // should not get one last chime while the preference is still loading.
  SoundSettings.instance.load();

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
      // The theme choice too, so it repaints every open screen.
      listenable: Listenable.merge([
        LanguageStore.instance,
        ThemeSettings.instance,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'GtradeA Amazon',
        debugShowCheckedModeBanner: false,
        // Light, Dark or System, as chosen under Account settings → Theme.
        // System follows the device and switches when it does.
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeSettings.instance.mode,
        // The framework interpolates the whole ThemeData -- backgrounds,
        // cards, text, borders, buttons, icons, inputs, the app bar -- so a
        // switch is a short fade rather than a flash. Short enough that the
        // tap still feels answered.
        themeAnimationDuration: const Duration(milliseconds: 250),
        themeAnimationCurve: Curves.easeInOut,
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

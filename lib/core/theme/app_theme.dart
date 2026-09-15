import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';

/// Builds the light/dark [ThemeData] for the app, mapping the web storefront's
/// shadcn/ui tokens (see [AppColors]) onto Material 3.
///
/// Ported verbatim from `gtradea-flutter` so both apps stay visually identical
/// and a brand change can be copied across without reconciling a diff. Both
/// brightnesses are kept for that reason, but `main.dart` pins ThemeMode.light
/// - this app ships the white version.
class AppTheme {
  AppTheme._();

  // Radii from the web app: cards 12, controls 8, chips full.
  static const double radiusCard = 12;
  static const double radiusControl = 8;

  /// The corner every full-width section card on a page takes.
  ///
  /// Named because these cards are drawn by five widgets that cannot see each
  /// other: the product card, the delivery options, the guarantees, Highlights
  /// and Description, and the two collapsing panels. They were separate literal
  /// 16s that agreed only by luck -- editing any one of them would have set
  /// that card a corner apart from the rest of the stack.
  static const double radiusSection = 16;

  /// Status bar styling for a screen whose top band is the brand teal.
  ///
  /// Nothing set this before, so the platform default applied: dark icons on a
  /// dark band, all but invisible. Both brightness fields are set because they
  /// mean opposite things -- on Android it names the icon colour, on iOS it
  /// names the background the icons are drawn against.
  static const SystemUiOverlayStyle brandBandOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final primary = isLight ? AppColors.primaryLight : AppColors.primaryDark;
    final background = isLight
        ? AppColors.backgroundLight
        : AppColors.backgroundDark;
    final foreground = isLight
        ? AppColors.foregroundLight
        : AppColors.foregroundDark;
    final muted = isLight ? AppColors.mutedLight : AppColors.mutedDark;
    final mutedFg = isLight
        ? AppColors.mutedForegroundLight
        : AppColors.mutedForegroundDark;
    final border = isLight ? AppColors.borderLight : AppColors.borderDark;
    final destructive = isLight
        ? AppColors.destructiveLight
        : AppColors.destructiveDark;
    final card = isLight ? AppColors.cardLight : AppColors.cardDark;

    // Inputs. The field is drawn in the card colour, not the page's: filled
    // with the page ground it had nothing to separate it from the page, and
    // inside a white card it read as a grey hole. Its edge is the body ink
    // held back rather than the hairline -- Mountain Grey on white is 1.2:1,
    // a border nobody can find -- and focus adds a breath of the brand blue
    // to the fill as well as to the edge, so the field being typed into is
    // obvious at a glance without shouting.
    final inputEdge = foreground.withValues(alpha: 0.34);
    final inputFocusFill = Color.alphaBlend(
      primary.withValues(alpha: 0.05),
      card,
    );
    Color inputAccent(Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return mutedFg.withValues(alpha: 0.6);
      }
      if (states.contains(WidgetState.error)) return destructive;
      if (states.contains(WidgetState.focused)) return primary;
      return mutedFg;
    }

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: AppColors.onPrimary,
      secondary: muted,
      onSecondary: foreground,
      tertiary: AppColors.accent,
      onTertiary: AppColors.onAccent,
      error: destructive,
      onError: AppColors.onDestructive,
      surface: card,
      onSurface: foreground,
      surfaceContainerHighest: muted,
      onSurfaceVariant: mutedFg,
      outline: border,
      outlineVariant: border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      dividerColor: border,
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      cardTheme: CardThemeData(
        color: card,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(0, 44),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return muted;
          if (states.contains(WidgetState.focused)) return inputFocusFill;
          return card;
        }),
        hoverColor: primary.withValues(alpha: 0.03),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        // Readable in its own right -- 5.7:1 on the white field -- but a clear
        // step under the typed text, which is the body slate at about 10:1.
        hintStyle: TextStyle(color: mutedFg, fontWeight: FontWeight.w400),
        labelStyle: TextStyle(color: mutedFg),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            color: inputAccent(states),
            fontWeight: FontWeight.w600,
          ),
        ),
        prefixIconColor: WidgetStateColor.resolveWith(inputAccent),
        suffixIconColor: WidgetStateColor.resolveWith(inputAccent),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: inputEdge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: inputEdge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: destructive),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: destructive, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: border),
        ),
      ),
      // The caret and the selection in the brand blue, so what is being edited
      // reads as the same colour as the edge around it.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.25),
        selectionHandleColor: primary,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: muted,
        shape: const StadiumBorder(),
        side: BorderSide(color: border),
        labelStyle: TextStyle(color: foreground, fontSize: 12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(int v) {
    final s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final argb = c.toARGB32();
  return 0.2126 * channel((argb >> 16) & 0xFF) +
      0.7152 * channel((argb >> 8) & 0xFF) +
      0.0722 * channel(argb & 0xFF);
}

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

const _white = Color(0xFFFFFFFF);

void main() {
  group('the four brand colours', () {
    test('are the exact hexes the brand system specifies', () {
      // Byte-for-byte, so a well-meaning tweak somewhere else in the app cannot
      // quietly become the brand.
      expect(_hex(AppColors.trustBlue), '#267488');
      expect(_hex(AppColors.commerceOrange), '#E94724');
      expect(_hex(AppColors.himalayanSlate), '#36454F');
      expect(_hex(AppColors.successGreen), '#22C55E');
    });

    test('are what the theme names are made of', () {
      // Every widget asks for these names, so this is what makes the brand
      // block the only place a colour is decided.
      expect(AppColors.primaryLight, AppColors.trustBlue);
      expect(AppColors.accent, AppColors.commerceOrange);
      // The page is the one neutral that is no longer derived from the slate:
      // it is plain white. The other three washes still are.
      expect(AppColors.backgroundLight, const Color(0xFFFFFFFF));
      expect(AppColors.foregroundLight, AppColors.himalayanSlate);
      expect(AppColors.borderLight, AppColors.hairline);
      expect(AppColors.mutedLight, AppColors.surfaceWash);
      expect(AppColors.success, AppColors.successGreen);
    });
  });

  group('60-30-10', () {
    final theme = AppTheme.light;

    test('the 60 is the page itself, and it is white', () {
      // Was the 6% slate wash, so that a white card read as a card rather than
      // as an edge. White now, by request. The consequence is recorded here
      // rather than left to be discovered: page and card are the same colour,
      // so a card is told apart by its hairline border alone.
      expect(theme.scaffoldBackgroundColor, _white);
      expect(theme.colorScheme.surface, _white);
      expect(
        theme.colorScheme.outlineVariant,
        AppColors.hairline,
        reason: 'the only thing separating a card from the page now',
      );
    });

    test('the 30 is the structure', () {
      expect(theme.colorScheme.primary, AppColors.trustBlue);
      expect(
        theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
        AppColors.trustBlue,
      );
    });

    test('the 10 is tertiary, never secondary', () {
      // The budget lives here. Material reaches for secondary constantly and
      // for tertiary almost never, so mapping the orange to secondary would
      // spend the 10% everywhere the framework felt like it.
      expect(theme.colorScheme.tertiary, AppColors.commerceOrange);
      expect(theme.colorScheme.secondary, isNot(AppColors.commerceOrange));
    });

    test('every neutral is Himalayan Slate over white, at a stated alpha', () {
      // Premium Ivory and Mountain Grey were the fifth and sixth brand colours
      // and are gone. The roles they filled are not: these three carry them,
      // and each is a blend of a colour that is still in the system rather than
      // a hex of its own. They are written as literals because they are used
      // in const contexts, so this is what stops the literal and the intent
      // drifting apart.
      // Compared as eight-bit hexes, not as Colors. alphaBlend keeps its
      // channels as floats, and a literal can only be written to the byte --
      // comparing the objects fails on a rounding difference of half a
      // 255th, which is not a colour anybody can see.
      String slateOverWhite(double alpha) => _hex(
        Color.alphaBlend(
          AppColors.himalayanSlate.withValues(alpha: alpha),
          _white,
        ),
      );

      expect(_hex(AppColors.pageWash), slateOverWhite(0.06));
      expect(_hex(AppColors.surfaceWash), slateOverWhite(0.08));
      expect(_hex(AppColors.hairline), slateOverWhite(0.14));
    });

    test('the neutrals are ordered: page, fill, line', () {
      // A muted fill has to sit on the page and a border has to sit on both.
      // Equal or inverted luminance is how a chip disappears into the page it
      // is drawn on.
      expect(
        _luminance(AppColors.pageWash),
        greaterThan(_luminance(AppColors.surfaceWash)),
      );
      expect(
        _luminance(AppColors.surfaceWash),
        greaterThan(_luminance(AppColors.hairline)),
      );
    });

    test('the two dropped colours are gone, not renamed', () {
      // The point of the removal. If either hex shows up again under any name,
      // the palette quietly went back to six.
      final palette = [
        AppColors.trustBlue,
        AppColors.commerceOrange,
        AppColors.himalayanSlate,
        AppColors.successGreen,
        AppColors.pageWash,
        AppColors.surfaceWash,
        AppColors.hairline,
        AppColors.backgroundLight,
        AppColors.foregroundLight,
        AppColors.cardLight,
        AppColors.mutedLight,
        AppColors.borderLight,
        AppColors.foregroundDark,
      ];

      expect(palette, isNot(contains(const Color(0xFFF2ECE6))));
      expect(palette, isNot(contains(const Color(0xFFE5E7EB))));
    });

    test('the neutrals do the quiet work', () {
      expect(theme.colorScheme.outline, AppColors.hairline);
      expect(theme.dividerColor, AppColors.hairline);
      expect(theme.colorScheme.onSurface, AppColors.himalayanSlate);
    });
  });

  group('what the brand values measure', () {
    test('body text on the page is comfortably readable', () {
      // Himalayan Slate on the page wash, which is most of the words in the
      // app. AA wants 4.5.
      expect(
        _contrast(AppColors.himalayanSlate, AppColors.pageWash),
        greaterThan(4.5),
      );
      expect(_contrast(AppColors.himalayanSlate, _white), greaterThan(4.5));
    });

    test('white on Trust Blue clears AA', () {
      // The header band, and every filled button.
      expect(_contrast(_white, AppColors.trustBlue), greaterThan(4.5));
    });

    test('Commerce Orange carries large text only', () {
      // 3.9:1 measured. That clears AA for large or bold text and for UI
      // components, and does not clear it for small body copy -- which is why
      // the orange is a button and a badge rather than a paragraph.
      final ratio = _contrast(_white, AppColors.commerceOrange);
      expect(ratio, greaterThan(3.0));
      expect(ratio, lessThan(4.5));
    });

    test('Success Green cannot be used as an ink, in either direction', () {
      // The finding that made successInk necessary. All three fail, including
      // white-on-green, which is how a badge is normally built.
      expect(_contrast(AppColors.success, AppColors.pageWash), lessThan(3));
      expect(_contrast(AppColors.success, _white), lessThan(3));
      expect(_contrast(_white, AppColors.success), lessThan(3));
    });

    test('successInk clears AA on both surfaces', () {
      expect(
        _contrast(AppColors.successInk, AppColors.pageWash),
        greaterThan(4.5),
      );
      expect(_contrast(AppColors.successInk, _white), greaterThan(4.5));
    });

    test('and successInk is still the brand green, not a new colour', () {
      // Same hue family: derived from Success Green by lowering its lightness,
      // so "positive" reads as one colour whether it is a badge or a sentence.
      final brandHue = HSLColor.fromColor(AppColors.successGreen).hue;
      final inkHue = HSLColor.fromColor(AppColors.successInk).hue;

      expect((brandHue - inkHue).abs(), lessThan(10));
      expect(
        HSLColor.fromColor(AppColors.successInk).lightness,
        lessThan(HSLColor.fromColor(AppColors.successGreen).lightness),
      );
    });
  });

  group('the header colour', () {
    test('is Trust Blue, not a colour of its own', () {
      // Derived rather than picked: hue and saturation untouched, lightness
      // down 0.06. If the brand blue ever moves, this follows it.
      final brand = HSLColor.fromColor(AppColors.trustBlue);
      final deep = HSLColor.fromColor(AppColors.trustBlueDeep);

      expect(deep.hue, closeTo(brand.hue, 1.0));
      expect(deep.saturation, closeTo(brand.saturation, 0.02));
      expect(deep.lightness, closeTo(brand.lightness - 0.06, 0.005));
    });

    test('the band top is the same blue with the light turned down', () {
      // The gradient's dark end. Given as a hex rather than derived, so this is
      // what says it belongs to the palette instead of being a fifth colour --
      // 192.4 degrees against the brand blue's 192.2 is the same hue.
      final brand = HSLColor.fromColor(AppColors.trustBlue);
      final top = HSLColor.fromColor(AppColors.brandBandTop);

      expect(top.hue, closeTo(brand.hue, 1.0));
      expect(top.lightness, lessThan(brand.lightness));
    });

    test('the band runs from that dark end to the brand blue itself', () {
      // Top to bottom, and nothing in between. Two stops is what makes the
      // transition a ramp rather than a set of steps.
      expect(AppColors.brandBand.begin, Alignment.topCenter);
      expect(AppColors.brandBand.end, Alignment.bottomCenter);
      expect(AppColors.brandBand.colors, [
        AppColors.brandBandTop,
        AppColors.trustBlue,
      ]);
    });

    test('white clears AA at both ends of the band', () {
      // Everything drawn on it is white: the mark, the three icons, the
      // delivery line, the department labels. A ramp has to hold that at the
      // light end as well as the dark one, and the light end is the brand blue.
      expect(_contrast(_white, AppColors.brandBandTop), greaterThan(4.5));
      expect(_contrast(_white, AppColors.trustBlue), greaterThan(4.5));
    });

    test('and the ramp is subtle rather than a two-tone split', () {
      // The header has already had a visible seam removed from it once. A
      // gradient whose ends are far apart would put that seam back as a
      // gradient instead of as an edge.
      expect(
        _contrast(AppColors.brandBandTop, AppColors.trustBlue),
        lessThan(2.2),
      );
    });

    test('is darker than the brand blue, but only just', () {
      // It was briefly used for the top strip alone, over the brand teal, and
      // the join read as a seam rather than as depth -- so the whole header is
      // this one colour now. The relationship still matters: far enough from
      // Trust Blue to be its own tone, close enough to still be it.
      final brand = _luminance(AppColors.trustBlue);
      final deep = _luminance(AppColors.trustBlueDeep);

      expect(deep, lessThan(brand));
      expect(
        _contrast(AppColors.trustBlueDeep, AppColors.trustBlue),
        lessThan(1.4),
      );
    });

    test('costs the icons on it no contrast', () {
      // Everything in that row is white. Moving it onto a darker ground can
      // only help, and this is the assertion that says so rather than assuming.
      final onBrand = _contrast(_white, AppColors.trustBlue);
      final onDeep = _contrast(_white, AppColors.trustBlueDeep);

      expect(onDeep, greaterThan(onBrand));
      expect(onDeep, greaterThan(4.5));
    });

    test('still counts as dark, so the ivory mark is chosen', () {
      // The logo variant is picked from the colour actually behind it. A strip
      // that crossed into "light" would put the blue-quartered mark on a blue
      // band again.
      expect(
        ThemeData.estimateBrightnessForColor(AppColors.trustBlueDeep),
        Brightness.dark,
      );
    });
  });
}

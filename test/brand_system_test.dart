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
  group('the six brand colours', () {
    test('are the exact hexes the brand system specifies', () {
      // Byte-for-byte, so a well-meaning tweak somewhere else in the app cannot
      // quietly become the brand.
      expect(_hex(AppColors.trustBlue), '#267488');
      expect(_hex(AppColors.commerceOrange), '#E94724');
      expect(_hex(AppColors.premiumIvory), '#F2ECE6');
      expect(_hex(AppColors.himalayanSlate), '#36454F');
      expect(_hex(AppColors.mountainGrey), '#E5E7EB');
      expect(_hex(AppColors.successGreen), '#22C55E');
    });

    test('are what the theme names are made of', () {
      // Every widget asks for these names, so this is what makes the brand
      // block the only place a colour is decided.
      expect(AppColors.primaryLight, AppColors.trustBlue);
      expect(AppColors.accent, AppColors.commerceOrange);
      // The page is Premium Ivory, by request: its own stated role. Cards
      // stay white on it, and Mountain Grey does the two things the brand
      // names it for -- every line, and the quiet fill under a chip.
      expect(AppColors.backgroundLight, AppColors.premiumIvory);
      expect(AppColors.cardLight, const Color(0xFFFFFFFF));
      expect(AppColors.mutedLight, AppColors.mountainGrey);
      expect(AppColors.foregroundLight, AppColors.himalayanSlate);
      expect(AppColors.borderLight, AppColors.mountainGrey);
      expect(AppColors.success, AppColors.successGreen);
    });
  });

  group('60-30-10', () {
    final theme = AppTheme.light;

    test('the 60 is the page, and it is Premium Ivory', () {
      expect(theme.scaffoldBackgroundColor, AppColors.premiumIvory);
      expect(theme.colorScheme.surface, _white);
      expect(theme.colorScheme.outlineVariant, AppColors.hairline);
      // A white card has to read on it, and the line round the card has to
      // read on the card. Both are what stops a page of cards becoming one
      // flat sheet.
      expect(_contrast(_white, AppColors.premiumIvory), greaterThan(1.1));
      expect(_contrast(AppColors.hairline, _white), greaterThan(1.1));
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

    test('every neutral is one of the two the brand names', () {
      // The washes derived from Himalayan Slate are gone: the brand has its
      // own two neutrals again, and these names point straight at them. A
      // neutral that is neither is a seventh colour by another name.
      expect(AppColors.pageWash, AppColors.premiumIvory);
      expect(AppColors.surfaceWash, AppColors.premiumIvory);
      expect(AppColors.hairline, AppColors.mountainGrey);
    });

    test('the neutrals are ordered: page, fill, line', () {
      // A fill has to read on the white page, and a line has to read on both
      // the page and the fill. Equal or inverted luminance is how a chip
      // disappears into what it is drawn on.
      expect(
        _luminance(_white),
        greaterThan(_luminance(AppColors.surfaceWash)),
      );
      expect(
        _luminance(AppColors.surfaceWash),
        greaterThan(_luminance(AppColors.hairline)),
      );
    });

    test('and nothing outside the six has crept in', () {
      // Every neutral in the light theme is one of the six or white. A hex
      // that is none of those is a seventh brand colour by another name.
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

      const brand = [
        AppColors.trustBlue,
        AppColors.commerceOrange,
        AppColors.premiumIvory,
        AppColors.himalayanSlate,
        AppColors.mountainGrey,
        AppColors.successGreen,
        _white,
      ];
      for (final colour in palette) {
        expect(brand, contains(colour), reason: _hex(colour));
      }
    });

    test('the neutrals do the quiet work', () {
      expect(theme.colorScheme.outline, AppColors.hairline);
      expect(theme.dividerColor, AppColors.hairline);
      expect(theme.colorScheme.onSurface, AppColors.himalayanSlate);
    });
  });

  group('what the brand values measure', () {
    test('body text on the page is comfortably readable', () {
      // Himalayan Slate on white and on the ivory panels, which between them
      // carry every word in the app. AA wants 4.5.
      expect(
        _contrast(AppColors.himalayanSlate, AppColors.pageWash),
        greaterThan(4.5),
      );
      expect(_contrast(AppColors.himalayanSlate, _white), greaterThan(4.5));
      expect(
        _contrast(AppColors.himalayanSlate, AppColors.mountainGrey),
        greaterThan(4.5),
      );
    });

    test('secondary text clears AA on white and on the ivory', () {
      // The ivory is warmer and darker than white, so a caption that was
      // comfortable on one had to be checked against the other. This is why
      // the muted foreground was darkened when the ivory came back.
      expect(
        _contrast(AppColors.mutedForegroundLight, _white),
        greaterThan(4.5),
      );
      expect(
        _contrast(AppColors.mutedForegroundLight, AppColors.premiumIvory),
        greaterThan(4.5),
      );
      // And on the grey a chip is filled with, which secondary text also
      // sits on.
      expect(
        _contrast(AppColors.mutedForegroundLight, AppColors.mountainGrey),
        greaterThan(4.5),
      );
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
      // The gradient's ends. Given as hexes rather than derived, so this is
      // what says they belong to the palette instead of being fifth and sixth
      // colours -- both are the brand blue's hue, one darker and one lighter.
      final brand = HSLColor.fromColor(AppColors.trustBlue);
      final top = HSLColor.fromColor(AppColors.brandBandTop);
      final foot = HSLColor.fromColor(AppColors.brandBandFoot);

      expect(top.hue, closeTo(brand.hue, 4.0));
      expect(top.lightness, lessThan(brand.lightness));
      expect(foot.hue, closeTo(brand.hue, 4.0));
      expect(foot.lightness, greaterThan(brand.lightness));
    });

    test('the band runs from its head to a deeper foot, in two stops', () {
      // Top to bottom, and given as exact hexes by the design rather than
      // derived from the palette: #1A4A5E to #0D2B3E.
      //
      // It was three stops, with Trust Blue held through the middle and a foot
      // *lighter* than the brand blue, so the band lifted off the page. It
      // sinks into the page now -- which is what lets the arched foot read as
      // the header sitting on the storefront rather than hovering over it.
      expect(AppColors.brandBand.begin, Alignment.topCenter);
      expect(AppColors.brandBand.end, Alignment.bottomCenter);
      expect(AppColors.brandBand.colors, [
        AppColors.brandBandHead,
        AppColors.brandBandDeep,
      ]);
      // And it runs that way round: the direction is the half of this a pair of
      // hexes alone would not catch if the two were ever swapped.
      expect(
        _luminance(AppColors.brandBandDeep),
        lessThan(_luminance(AppColors.brandBandHead)),
      );
    });

    test('white clears AA at both ends of the band', () {
      // Everything drawn on it is white: the mark, the three icons, the
      // delivery line, the coin figure, the greeting. Both ends of the header's
      // own ramp have to hold that.
      expect(_contrast(_white, AppColors.brandBandHead), greaterThan(4.5));
      expect(_contrast(_white, AppColors.brandBandDeep), greaterThan(4.5));

      // The older pair is still in use -- the scrim over the artwork and the
      // brand lockup -- so white still has to clear those too. The foot is the
      // lightest of them, which makes it the one that decides it.
      expect(_contrast(_white, AppColors.brandBandTop), greaterThan(4.5));
      expect(_contrast(_white, AppColors.trustBlue), greaterThan(4.5));
      expect(_contrast(_white, AppColors.brandBandFoot), greaterThan(4.5));
    });

    test('and the ramp is subtle rather than a two-tone split', () {
      // The header has already had a visible seam removed from it once. A
      // gradient whose ends are far apart would put that seam back as a
      // gradient instead of as an edge.
      expect(
        _contrast(AppColors.brandBandTop, AppColors.trustBlue),
        lessThan(2.2),
      );
      expect(
        _contrast(AppColors.trustBlue, AppColors.brandBandFoot),
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

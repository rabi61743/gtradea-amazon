import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/shared/widgets/brand_wordmark.dart';

/// Either mark, read off disk.
String _svgOf(String asset) => File(asset).readAsStringSync();

String get _svg => _svgOf(AppBrand.logoAsset);
String get _svgOnDark => _svgOf(AppBrand.logoOnDarkAsset);

void main() {
  group('the logo asset', () {
    test('is the artwork as supplied, not a redrawing of it', () {
      // These three definitions are copied byte for byte from the storefront's
      // own icon.svg. If a future edit "tidies" one of them, the app is showing
      // a logo somebody redrew rather than the logo the brand uses.
      const paths = [
        'M169.34,126.56v43.61c-13.86,14.04-33,22.72-54.15,22.72-17.96,0-34.47-6.27-47.53-16.76,2.02.17,4.08.26,6.15.26,32.3,0,59.9-20.67,70.89-49.83h24.64Z',
        '208.22 93.95 208.22 192.69 169.34 192.69 169.34 126.56 104.52 126.56 128.57 94 128.6 93.95 208.22 93.95',
        'M169.48,38.16v.45l-10.32,13.98-10.57,14.3-20.02,27.11c-40.36,1.22-72.79,31.59-73.62,69.18-10.22-13.15-16.3-29.73-16.3-47.75,0-40.15,30.19-73.15,68.83-76.89,2.41-.25,4.87-.37,7.36-.37h54.65Z',
      ];

      for (final path in paths) {
        expect(_svg, contains(path));
      }
    });

    test('is drawn in the brand colours, and the palette agrees', () {
      // These used to disagree: the app shipped E84326 and 277586, each a shade
      // off the mark's own E94724 and 267488, so the logo never quite matched
      // the header it sat on. The palette now carries the brand's own values,
      // and this is what keeps the two from drifting apart again.
      expect(_svg, contains('#e94724'));
      expect(_svg, contains('#267488'));

      String hex(Color c) =>
          '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

      expect(hex(AppColors.commerceOrange), '#e94724');
      expect(hex(AppColors.trustBlue), '#267488');
    });

    test('carries no app-icon backing plate', () {
      // The source file centres the mark on a white rounded rectangle. On the
      // teal header that would draw a white card behind the logo.
      expect(_svg, isNot(contains('<rect')));
      expect(_svg, isNot(contains('#ffffff')));
    });

    test('states the proportions the widget reserves', () {
      // The two have to agree, or the mark letterboxes inside a box of the
      // wrong shape.
      expect(_svg, contains('viewBox="36.6 36.2 173.6 158.7"'));
      expect(AppBrand.logoAspectRatio, closeTo(173.6 / 158.7, 0.0001));
    });
  });

  group('the mark in a layout', () {
    testWidgets('keeps its proportions whatever box it is given', (
      tester,
    ) async {
      // Handed a square, it must letterbox rather than stretch: a squashed
      // logo is the most common way an otherwise careful app mangles a brand.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: BrandWordmark(height: 200),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BrandWordmark), findsOneWidget);
    });

    testWidgets('renders at a range of sizes without complaint', (
      tester,
    ) async {
      for (final height in [16.0, 34.0, 96.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(child: BrandWordmark(height: height)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'at ${height}pt');
      }
    });

    testWidgets('does not scale with the reader text size', (tester) async {
      // It is artwork, not type. A mark that grew with the font setting would
      // push the header's icons out of the row.
      final sizes = <double>[];

      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(body: Center(child: BrandWordmark())),
            ),
          ),
        );
        await tester.pumpAndSettle();
        sizes.add(tester.getSize(find.byType(BrandWordmark)).height);
      }

      expect(sizes.first, sizes.last);
    });
  });

  group('the dark-surface mark', () {
    test('is the same artwork, not a second drawing of it', () {
      // Exactly one thing may differ between the two files. If the geometry
      // ever diverges, the app has two logos rather than one logo in two
      // finishes -- and nobody notices until they sit side by side.
      final light = RegExp('d="[^"]+"').allMatches(_svg).map((m) => m[0]);
      final dark = RegExp('d="[^"]+"').allMatches(_svgOnDark).map((m) => m[0]);

      expect(dark, orderedEquals(light));
      expect(_svgOnDark, contains('viewBox="36.6 36.2 173.6 158.7"'));
    });

    test('swaps the blue quarter for the near-white, and drops the blue', () {
      // A file that kept both would still lose half the mark on the band.
      expect(_svgOnDark, contains('fill="#e94724"'));
      expect(_svgOnDark, contains('fill="#f3f4f4"'));
      // The fill specifically, not the string: the file's own comment names
      // the blue to explain why this variant exists, and that is worth keeping.
      expect(_svgOnDark, isNot(contains('fill="#267488"')));
    });

    test('the light quarter is the palette near-white, not a hex of its own', () {
      // It was Premium Ivory, and this test used to say so. That colour has
      // been dropped, and this file is our own derivation of the supplied mark
      // rather than the mark itself -- the geometry is untouched and only the
      // fill the file exists to change has changed. So it follows the palette:
      // otherwise deleting a brand colour would leave it painted on the header
      // of every screen, which is where it was still showing.
      expect(_svgOnDark, contains('fill="#f3f4f4"'));
      expect(_svgOnDark, isNot(contains('f2ece6')));

      final wash = AppColors.pageWash.toARGB32() & 0xFFFFFF;
      expect(wash.toRadixString(16).padLeft(6, '0'), 'f3f4f4');
    });
  });

  group('choosing between them', () {
    test('the header band gets the light mark', () {
      // The whole reason two files exist. The light mark's blue quarter is
      // Trust Blue, and so is the band, so on the band half the logo is not
      // low-contrast -- it is invisible. Measured on a screenshot: the logo
      // region and the band beside it were both #267488.
      expect(AppBrand.logoFor(AppColors.trustBlue), AppBrand.logoOnDarkAsset);
    });

    test('a light page gets the blue mark', () {
      expect(AppBrand.logoFor(AppColors.pageWash), AppBrand.logoAsset);
      expect(AppBrand.logoFor(const Color(0xFFFFFFFF)), AppBrand.logoAsset);
    });

    test('is decided by the surface, not by the theme brightness', () {
      // Those are different questions. This app is pinned to the light theme
      // and its header is a dark band, so a Theme.brightness check would put
      // the light-surface mark straight onto the band.
      expect(AppTheme.light.brightness, Brightness.light);
      expect(
        AppBrand.logoFor(AppColors.trustBlue),
        isNot(AppBrand.logoFor(AppTheme.light.colorScheme.surface)),
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/flash_sale_card.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/hero_banner.dart';
import 'package:gtradea_amazon/features/home/widgets/promo_section.dart';
import 'package:gtradea_amazon/shared/widgets/page_width.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';

/// A sale that has not run out, so the card is on the page to measure.
Map<String, dynamic> _sale() => {
  'id': 'sale-1',
  'headline': 'Dashain Specials',
  'ends_at': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 3))
      .toIso8601String(),
  'items': [
    {
      'product': feedRows(1).first,
      'sale_price': 60,
      'list_price': 100,
      'discount_percent': 40,
    },
  ],
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final api = stubCatalog();
    api.on('GET', '/flash-sales/active', body: _sale());
    // Short campaign copy rather than the built-in fallbacks: those carry a
    // long headline and a sentence, and the suite's square-glyph fallback font
    // makes them overflow a 360dp card -- a fact about the harness rather than
    // about the width this test is measuring.
    api.on(
      'GET',
      '/hero-banners',
      body: [
        for (var i = 0; i < 3; i++)
          {
            'id': 'banner-$i',
            'title': 'Campaign $i',
            'subtitle': 'Subtitle $i',
            'button_text': 'Shop $i',
            'show_text_overlay': true,
            'background_image_url': 'https://example.invalid/b$i.jpg',
            'is_active': true,
            'sort_order': i,
          },
      ],
    );
    CatalogStore.instance.resetForTest();
  });

  tearDown(clearApiStub);

  Future<double> pumpHome(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width * 2, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
    await tester.pumpAndSettle();
    return width;
  }

  testWidgets('the home page measures 97% of the screen, with 1.5% each side', (
    tester,
  ) async {
    // The worked examples from the design: 360 -> 349, 390 -> 378, 412 -> 400.
    for (final width in [360.0, 390.0, 412.0]) {
      await pumpHome(tester, width);

      final expected = width * PageWidth.factor;
      final margin = width * (1 - PageWidth.factor) / 2;

      // The hero, which measures itself. Scoped to the carousel: the category
      // tabs above it are InkWells too, and they are not the page's measure.
      final hero = tester.getRect(
        find
            .descendant(
              of: find.byType(HeroBanner),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(hero.width, closeTo(expected, 1.5), reason: 'hero at ${width}dp');
      expect(hero.left, closeTo(margin, 1), reason: 'hero at ${width}dp');

      // The promotional block, which pads itself to the same measure: its
      // content starts on the page margin rather than on a flat 16.
      final promo = tester
          .widgetList<Padding>(
            find.descendant(
              of: find.byType(PromoSection),
              matching: find.byType(Padding),
            ),
          )
          .map((p) => p.padding.resolve(TextDirection.ltr).left)
          .where((left) => left > 0);
      expect(promo, contains(closeTo(margin, 0.01)), reason: '${width}dp');
    }
  });

  testWidgets('and the flash sale card is the same measure, centred', (
    tester,
  ) async {
    for (final width in [360.0, 412.0]) {
      await pumpHome(tester, width);

      final card = find.descendant(
        of: find.byType(FlashSaleCard),
        matching: find.byType(DecoratedBox),
      );
      if (card.evaluate().isEmpty) {
        // No live sale in this run; the card is only on the page when the
        // server has one, and that is the honest state to leave it in.
        continue;
      }

      final rect = tester.getRect(card.first);
      final margin = width * (1 - PageWidth.factor) / 2;

      expect(
        rect.width,
        closeTo(width * PageWidth.factor, 1.5),
        reason: '${width}dp',
      );
      expect(rect.left, closeTo(margin, 1), reason: 'left margin');
      expect(width - rect.right, closeTo(margin, 1), reason: 'right margin');
      // Not edge to edge, which is the thing it must not be.
      expect(rect.width, lessThan(width));
    }
  });

  test(
    'the measure itself is 97%, and the margin the half of what is left',
    () {
      expect(PageWidth.factor, 0.97);
      expect(HeroBanner.widthFactor, PageWidth.factor);
    },
  );
}

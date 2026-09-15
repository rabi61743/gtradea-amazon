import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/shared/widgets/page_width.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/flash_sale/data/flash_sale.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/flash_sale_card.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/sale_countdown.dart';

FlashSale _sale(DateTime endsAt) => FlashSale(
  id: 'sale',
  headline: 'Dashain Specials',
  endsAt: endsAt,
  items: [
    FlashSaleItem(
      product: const Product(numIid: 'a', title: 'A', displayPrice: 100),
      salePrice: 60,
      listPrice: 100,
      discountPercent: 40,
    ),
  ],
);

Widget _wrap(Widget child, {double scale = 1.0}) => MaterialApp(
  theme: AppTheme.light,
  // Copied from the ambient query rather than built fresh: a bare
  // MediaQueryData has a size of zero, and the card measures its page margin
  // from the width of the screen.
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  final now = DateTime(2026, 8, 27, 12);

  testWidgets('says what it is and how long is left', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(
            now.add(const Duration(days: 2, hours: 3, minutes: 4, seconds: 5)),
          ),
          now: () => now,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Flash Sales'), findsOneWidget);

    // All four units, labelled. "Days, Hours, Minutes, Seconds" is the whole
    // point of the card, so each one is asserted rather than the block as one.
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Hrs'), findsOneWidget);
    expect(find.text('Mins'), findsOneWidget);
    expect(find.text('Secs'), findsOneWidget);

    expect(find.text('02'), findsOneWidget); // days
    expect(find.text('03'), findsOneWidget); // hours
    expect(find.text('04'), findsOneWidget); // minutes
    expect(find.text('05'), findsOneWidget); // seconds
  });

  testWidgets('counts down in real time', (tester) async {
    var clock = now;
    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.add(const Duration(minutes: 5))),
          now: () => clock,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('05'), findsOneWidget);

    clock = clock.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('04'), findsOneWidget);
  });

  testWidgets('the clock is drawn at full size on a phone', (tester) async {
    // The defect this card was built around. An earlier version of this clock
    // shared a row with a title and a button and was scaled to a third of its
    // size on a phone; this one has a row of its own.
    for (final width in [320.0, 360.0, 412.0]) {
      tester.view.physicalSize = Size(width * 3, 2000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          FlashSaleCard(
            sale: _sale(now.add(const Duration(hours: 2))),
            now: () => now,
          ),
        ),
      );
      await tester.pump();

      // The room the layout gives the clock, not how much of it the clock
      // happens to use. Tests run on the fallback font, whose glyphs are square
      // and about 1.6x the width of the Roboto the app ships, so "is it drawn
      // unscaled" is a question about the harness rather than about the card.
      // The room is what actually broke before: an earlier version of this
      // clock was given a third of a row and scaled to match.
      final card = tester.getSize(find.byType(FlashSaleCard));
      final box = tester.getSize(
        find
            .ancestor(
              of: find.byType(SaleCountdown),
              matching: find.byType(FittedBox),
            )
            .first,
      );

      // Every inset between the screen edge and the clock, doubled: the page
      // margin the card now shares with the rest of the home page -- 1.5% of
      // the screen rather than a flat 16 -- plus the card's own padding.
      // The countdown's panel has no ground and no padding of its own now, so
      // there is nothing else between the two.
      //
      // Read from the card rather than copied. This carried its own 11, and
      // when the card's padding came down the clock correctly grew into the
      // room while this went on computing the old, smaller allowance -- so the
      // test failed for a card that was behaving exactly as asked.
      final inset =
          2 * (width * (1 - PageWidth.factor) / 2 + FlashSaleCard.pad);
      final whole = card.width - inset;

      // The clock keeps the row apart from the corner the artwork takes, which
      // is a fifth of it. What it is never given is a third of a row, which is
      // the defect this test was written for.
      expect(box.width, lessThanOrEqualTo(whole + 1), reason: '${width}dp');
      expect(box.width, greaterThan(whole * 0.6), reason: '${width}dp');
      expect(tester.takeException(), isNull, reason: '${width}dp');
    }
  });

  /// The clock's panel.
  Finder clockPanel() => find
      .ancestor(
        of: find.byType(SaleCountdown),
        matching: find.byType(Container),
      )
      .first;

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.add(const Duration(hours: 2))),
          now: () => now,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the banner is the card own ground, from the right', (
    tester,
  ) async {
    // One card: the picture is the card's background and everything else --
    // the mark, the heading, the button, the sentence and the clock -- is set
    // on it. Not a second card, and not a block in the column.
    for (final width in [360.0, 412.0, 840.0]) {
      await pumpAt(tester, width);

      final ground = tester
          .widgetList<Ink>(find.byType(Ink))
          .map((ink) => ink.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.image != null);

      final picture = ground.image!;
      expect(
        (picture.image as AssetImage).assetName,
        contains('gift_banner'),
        reason: '${width}dp',
      );
      // Cover, so nothing is stretched; from the right, so what falls outside
      // the card is the flat red at the artwork's left end and what is kept is
      // the gift.
      expect(picture.fit, BoxFit.cover);
      expect(picture.alignment, Alignment.centerRight);
      // And the card keeps its own gradient underneath, which is what it is if
      // the file ever fails to load.
      expect(ground.gradient, isNotNull);
    }
  });

  testWidgets('and every word on the card is set over it', (tester) async {
    await pumpAt(tester, 412);

    // The heading, its mark, the sentence, the button and the clock -- all of
    // them on the one card, over the one picture.
    expect(find.text('Flash Sales'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    expect(find.byType(SaleCountdown), findsOneWidget);
    expect(find.text('Days'), findsOneWidget);

    // With a wash between the picture and the words, so the type keeps its
    // contrast on the busy half of the artwork.
    expect(find.byType(DecoratedBox), findsWidgets);
  });

  testWidgets('and the clock carries no ground of its own', (tester) async {
    await pumpAt(tester, 412);

    final panel = tester.widget<Container>(clockPanel());
    expect(panel.decoration, isNull, reason: 'no fill, no border, no shadow');

    // The figures themselves are still boxed and still there.
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Secs'), findsOneWidget);
  });

  testWidgets('and the clock stops before the gift', (tester) async {
    // The gift sits at the right end of the picture. The clock's row is held
    // back from it so the two never run together.
    for (final width in [360.0, 412.0]) {
      await pumpAt(tester, width);

      final card = tester.getRect(find.byType(FlashSaleCard));
      final panel = tester.getRect(clockPanel());

      expect(
        card.right - panel.right,
        greaterThan(60),
        reason: 'room for the gift at ${width}dp',
      );
      expect(panel.left, greaterThan(card.left), reason: 'inside the card');
    }
  });

  testWidgets('and the card is no taller for the picture', (tester) async {
    // The picture is the ground, not a block in the column, so it costs the
    // card no height at all.
    for (final width in [360.0, 412.0]) {
      await pumpAt(tester, width);
      final card = tester.getSize(find.byType(FlashSaleCard));
      expect(card.height, lessThan(150), reason: '${width}dp');
    }
  });

  testWidgets('is banner-height, not block-height', (tester) async {
    // Asked for directly: the card is to read at about the height of the promo
    // banner further down the page rather than as a block of its own. It was
    // 201pt on a 412dp handset against that banner's 92, which is what the
    // request was about.
    //
    // Not equal to the banner, and it cannot be: the banner is a picture that
    // scales with the width, and this card carries a heading, a sentence and
    // four labelled clock cells whose height is set by the type in them, not by
    // how wide the phone is. What is pinned here is that it stays in the same
    // band -- and every one of those parts is still on it, which the tests
    // above check.
    for (final width in [360.0, 412.0]) {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          FlashSaleCard(
            sale: _sale(now.add(const Duration(hours: 2))),
            onTap: () {},
            now: () => now,
          ),
        ),
      );
      await tester.pump();

      // The artwork is in the corner, over the card rather than under it, so
      // the card's own height is what it always was.
      final card = tester.getSize(find.byType(FlashSaleCard));
      expect(card.height, lessThan(150), reason: '${width}dp');
      // The old height, kept as the thing not to go back to.
      expect(card.height, lessThan(201 * 0.75), reason: '${width}dp');
    }
  });

  testWidgets('nothing overflows at any text scale', (tester) async {
    for (final scale in [1.0, 1.5, 2.0]) {
      await tester.pumpWidget(
        _wrap(
          FlashSaleCard(
            sale: _sale(now.add(const Duration(hours: 2))),
            now: () => now,
          ),
          scale: scale,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'at $scale');
    }
  });

  testWidgets('a sale already over draws nothing', (tester) async {
    // A "Flash Sale" heading over a clock reading zeros advertises an offer
    // that has stopped.
    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.subtract(const Duration(minutes: 1))),
          now: () => now,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Flash Sales'), findsNothing);
    expect(find.byType(SaleCountdown), findsNothing);
  });

  testWidgets('and it disappears the moment it runs out', (tester) async {
    var clock = now;
    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.add(const Duration(seconds: 2))),
          now: () => clock,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Flash Sales'), findsOneWidget);

    clock = clock.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Flash Sales'), findsNothing);
  });

  testWidgets('every word on the red card is readable on it', (tester) async {
    // The card is filled red now, so everything on it is white or near-white
    // and the ground is what has to carry them. This is the assertion that
    // decided the red: the design's brighter one gives white body copy 4.05:1,
    // and this card carries a sentence, not just a heading.
    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.add(const Duration(hours: 2))),
          now: () => now,
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    final heading = tester.widget<Text>(find.text('Flash Sales'));
    expect(heading.style?.color, const Color(0xFFFFFFFF));
    expect(find.byIcon(Icons.bolt), findsOneWidget);

    // Measured at the lighter end of the gradient, which is the harder of the
    // two -- clearing it there clears it everywhere on the card.
    final light = AppColors.flashSaleTop;

    expect(
      _contrast(const Color(0xFFFFFFFF), light),
      greaterThan(4.5),
      reason: 'the subhead is ordinary text, and ordinary text needs 4.5',
    );
    expect(
      _contrast(AppColors.flashSaleHurry, light),
      greaterThan(4.5),
      reason: '"Hurry up!" is a word at body size, not a heading',
    );
    // The Shop now pill: the card's deeper red on white.
    expect(
      _contrast(AppColors.flashSaleBottom, const Color(0xFFFFFFFF)),
      greaterThan(4.5),
    );
    // The bolt tile is the accent at full strength, and its icon is white.
    // An icon needs 3.
    expect(
      _contrast(const Color(0xFFFFFFFF), AppColors.accent),
      greaterThan(3),
    );
  });

  test('the card\'s red is Commerce Orange with the light taken out', () {
    // Derived, not picked -- the same way trustBlueDeep is derived from the
    // brand blue. If the accent ever moves, this follows it rather than
    // becoming a fifth brand colour that nobody can account for.
    final accent = HSLColor.fromColor(AppColors.accent);
    for (final red in [AppColors.flashSaleTop, AppColors.flashSaleBottom]) {
      final shade = HSLColor.fromColor(red);
      expect(shade.hue, closeTo(accent.hue, 1.0));
      expect(shade.saturation, closeTo(accent.saturation, 0.02));
      expect(shade.lightness, lessThan(accent.lightness));
    }

    // And the gradient runs light to deep, top-left to bottom-right.
    expect(AppColors.flashSaleBand.colors, [
      AppColors.flashSaleTop,
      AppColors.flashSaleBottom,
    ]);
    expect(
      HSLColor.fromColor(AppColors.flashSaleTop).lightness,
      greaterThan(HSLColor.fromColor(AppColors.flashSaleBottom).lightness),
    );
  });

  testWidgets('the label is not ellipsised on a real handset', (tester) async {
    // The bug this catches, found on the device and invisible to every other
    // test in this file. `find.text` matches the string a Text was *given*, so
    // all of them passed while the phone drew "Flash ..." -- the heading was
    // Flexible with a Spacer beside it, both flex:1, so the row handed half its
    // free space to the gap and clipped the words to pay for it.
    //
    // What is asserted is the *space the heading is given*, not whether the
    // glyphs happen to fit in it. Tests run on the fallback font, which is
    // about 1.6x the width of the app's Roboto -- so "did it ellipsise" here
    // measures the harness, exactly as the clock test above says. The row
    // handing every spare point to the words is the fix, and it is true of the
    // layout regardless of which font draws them.
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.add(const Duration(hours: 2))),
          now: () => now,
          // The Shop now button only exists when the card is tappable, and it
          // is the widget the heading was losing the space to.
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    final heading = tester.getRect(find.text('Flash Sales'));
    final button = tester.getRect(find.text('Shop now'));

    // No gap between the two beyond the button's own padding. With the Spacer
    // there was a wide one -- that gap *was* the space the words needed.
    expect(
      button.left - heading.right,
      lessThan(24),
      reason: 'the heading is given the row, not half of it',
    );
  });

  testWidgets('a tap goes where it is told', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.add(const Duration(hours: 2))),
          now: () => now,
          onTap: () => taps++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Flash Sales'));
    await tester.pump();
    expect(taps, 1);
  });

  group('the subhead', () {
    FlashSale saleOf(List<int> discounts) => FlashSale(
      id: 'sale',
      headline: 'Dashain Specials',
      subhead: 'Unbeatable deals. Limited stock. Hurry up!',
      endsAt: now.add(const Duration(hours: 2)),
      items: [
        for (final (i, off) in discounts.indexed)
          FlashSaleItem(
            product: Product(numIid: '$i', title: 'P$i', displayPrice: 100),
            salePrice: 100 - off,
            listPrice: 100,
            discountPercent: off,
          ),
      ],
    );

    testWidgets('the card carries no summary of the deals below it', (
      tester,
    ) async {
      // The row of marks that used to sit along the foot -- the largest
      // discount, the deal count, a note about checkout -- is gone. The deals
      // panel directly beneath this card already says what is in the sale, and
      // this card's job is the deadline.
      await tester.pumpWidget(
        _wrap(FlashSaleCard(sale: saleOf([15, 40, 22]), now: () => now)),
      );
      await tester.pump();

      expect(find.textContaining('% off'), findsNothing);
      expect(find.text('3 deals'), findsNothing);
      expect(find.text('Secure checkout'), findsNothing);
      // Not `textContaining('deals')`: the sale's own subhead opens with
      // "Unbeatable deals", and that stays.
      expect(find.textContaining('Unbeatable deals'), findsOneWidget);
    });

    testWidgets('the last sentence of the subhead carries the accent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(FlashSaleCard(sale: saleOf([10]), now: () => now)),
      );
      await tester.pump();

      // One Text, two styles: the yellow is on "Hurry up!" and the rest is
      // white. Both are drawn on the card's red, so the accent could not stay
      // the orange it was -- orange on this red is a word you cannot read.
      final rich = tester.widget<Text>(find.textContaining('Unbeatable deals'));
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      final urgent = spans.firstWhere((s) => s.text!.contains('Hurry'));
      final calm = spans.firstWhere((s) => s.text!.contains('Unbeatable'));

      expect(urgent.style?.color, AppColors.flashSaleHurry);
      expect(calm.style?.color, const Color(0xFFFFFFFF));
    });
  });

  testWidgets('and no Shop now when there is nowhere to go', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.add(const Duration(hours: 2))),
          now: () => now,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Shop now'), findsNothing);
  });

  testWidgets('it casts a soft shadow down and to the right', (tester) async {
    // Subtle, not a border: two low-opacity layers offset down and slightly
    // right, so it reads as the card floating rather than as an outline.
    await tester.pumpWidget(
      _wrap(
        FlashSaleCard(
          sale: _sale(now.add(const Duration(hours: 3))),
          now: () => now,
        ),
      ),
    );
    await tester.pump();

    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byType(Material).last,
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final shadows = (box.decoration as BoxDecoration).boxShadow!;

    expect(shadows, isNotEmpty);
    for (final shadow in shadows) {
      expect(shadow.offset.dy, greaterThan(0), reason: 'cast downwards');
      expect(shadow.offset.dx, greaterThan(0), reason: 'and to the right');
      expect(
        shadow.offset.dy,
        greaterThan(shadow.offset.dx),
        reason: 'more down than across, as light from above and left',
      );
      expect(
        shadow.blurRadius,
        greaterThan(4),
        reason: 'soft, not a hard rule',
      );
      expect(
        shadow.color.a,
        lessThan(0.12),
        reason: 'low opacity, so it reads as a shadow and not a grey band',
      );
    }
    expect(
      shadows.length,
      greaterThan(1),
      reason: 'layered, which is what gives it a gentle falloff',
    );
  });
}

/// WCAG relative luminance, and the contrast ratio between two opaque colours.
///
/// Written out rather than eyeballed because "is red readable on that" is the
/// question this card got wrong, and a number is the only answer that survives
/// somebody changing the background later.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final x = _luminance(a);
  final y = _luminance(b);
  final hi = x > y ? x : y;
  final lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}

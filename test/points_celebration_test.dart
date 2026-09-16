import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/wallet/presentation/points_celebration.dart';

/// The coin and figure as the card lays them out, at a given real balance.
Widget _chip({required int balance, bool reducedMotion = false}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnimatedPointsCoin(
                size: 28,
                child: SizedBox(key: ValueKey('coin'), width: 28, height: 28),
              ),
              const SizedBox(width: 8),
              AnimatedPointsFigure(
                balance: balance,
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _figure(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('points-figure'))).data!;

/// True while the coin is drawing its glow and sparkles.
bool _celebrating(WidgetTester tester) => find
    .descendant(
      of: find.byType(AnimatedPointsCoin),
      matching: find.byType(CustomPaint),
    )
    .evaluate()
    .isNotEmpty;

/// Past the arrival's delay and through the arrival itself.
Future<void> _arrived(WidgetTester tester) async {
  await tester.pump(AnimatedPointsCoin.arrivalDelay);
  await tester.pumpAndSettle();
}

void main() {
  setUp(PointsCelebration.resetForTest);

  group('the app-open arrival', () {
    testWidgets('plays once when the coin first appears', (tester) async {
      await tester.pumpWidget(_chip(balance: 1000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 520));

      expect(_celebrating(tester), isTrue, reason: 'pop, glow and sparkles');

      await tester.pumpAndSettle();
      expect(_celebrating(tester), isFalse, reason: 'and nothing left behind');
      expect(_figure(tester), '1,000', reason: 'the balance is untouched');
    });

    testWidgets('does not replay when the header is built again', (
      tester,
    ) async {
      await tester.pumpWidget(_chip(balance: 1000));
      await _arrived(tester);

      // The card gone and back -- a rebuild, a tab switch, a scroll.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_chip(balance: 1000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_celebrating(tester), isFalse, reason: 'once per app open');
    });

    testWidgets('stays still for reduced motion', (tester) async {
      await tester.pumpWidget(_chip(balance: 1000, reducedMotion: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_celebrating(tester), isFalse);
    });
  });

  group('a real rise, as the points API will report it', () {
    testWidgets('rolls up, overshoots a little, and lands on the new balance', (
      tester,
    ) async {
      await tester.pumpWidget(_chip(balance: 1000));
      await _arrived(tester);

      // The API would have put the new figure in the store by now.
      await tester.pumpWidget(_chip(balance: 1200));
      PointsCelebration.play(previousBalance: 1000, newBalance: 1200);
      await tester.pump();

      // It starts from where it was, not at the answer.
      expect(_figure(tester), '1,000');

      final seen = <int>[];
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        seen.add(int.parse(_figure(tester).replaceAll(',', '')));
      }
      expect(
        seen.where((v) => v > 1000 && v < 1200),
        isNotEmpty,
        reason: 'counted through the values in between',
      );
      expect(
        seen.reduce((a, b) => a > b ? a : b),
        greaterThan(1200),
        reason: 'a slight overshoot',
      );

      await tester.pumpAndSettle();
      expect(_figure(tester), '1,200', reason: 'and settles on the real one');
      expect(find.text('+200'), findsNothing, reason: 'the badge has gone');
    });

    testWidgets('sends a +N up, with no preview label', (tester) async {
      await tester.pumpWidget(_chip(balance: 1200));
      await _arrived(tester);

      PointsCelebration.play(previousBalance: 1000, newBalance: 1200);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('+200'), findsOneWidget);
      expect(find.text('preview'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('a fall or no change plays nothing', (tester) async {
      await tester.pumpWidget(_chip(balance: 900));
      await _arrived(tester);

      PointsCelebration.play(previousBalance: 1000, newBalance: 900);
      PointsCelebration.play(previousBalance: 900, newBalance: 900);
      await tester.pump(const Duration(milliseconds: 200));

      expect(_celebrating(tester), isFalse);
      expect(find.textContaining('+'), findsNothing);
      expect(_figure(tester), '900');
    });
  });

  testWidgets(
    'the floating badge has a text style, not the warning underline',
    (tester) async {
      // Drawn in the overlay, outside any Material: on the phone its text came
      // out with Flutter's yellow double underline until it was given one.
      await tester.pumpWidget(_chip(balance: 1000));
      await _arrived(tester);

      PointsCelebration.preview(balance: 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final badge = find.text('+${PointsCelebration.previewAmount}');
      expect(
        find.ancestor(of: badge, matching: find.byType(Material)),
        findsWidgets,
      );
      final style = DefaultTextStyle.of(tester.element(badge)).style;
      expect(style.decoration, isNot(TextDecoration.underline));

      await tester.pumpAndSettle();
    },
  );

  group('the preview', () {
    testWidgets('is labelled, and hands the figure back to the real balance', (
      tester,
    ) async {
      await tester.pumpWidget(_chip(balance: 1000));
      await _arrived(tester);

      PointsCelebration.preview(balance: 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Plainly a demonstration, never a reward.
      expect(find.text('+${PointsCelebration.previewAmount}'), findsOneWidget);
      expect(find.text('preview'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Animation preview. No points were added.'),
        findsOneWidget,
      );

      // Up to the example figure...
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_figure(tester), '1,050');

      // ...and back down to what the account really holds.
      await tester.pumpAndSettle();
      expect(_figure(tester), '1,000');
    });
  });
}

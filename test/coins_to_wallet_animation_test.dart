import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/audio/app_sound.dart';
import 'package:gtradea_amazon/core/audio/app_sounds.dart';
import 'package:gtradea_amazon/core/audio/sound_settings.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/wallet/presentation/coins_to_wallet_animation.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _scene({
  int value = CoinsToWalletAnimation.demoValue,
  bool preview = false,
  bool reducedMotion = false,
  VoidCallback? onFinished,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            height: 380,
            child: CoinsToWalletAnimation(
              value: value,
              preview: preview,
              onFinished: onFinished,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The total's opacity and scale, as drawn, or null before it appears.
({double opacity, double scale})? _total(WidgetTester tester, String text) {
  final found = find.text(text);
  if (found.evaluate().isEmpty) return null;
  final opacity = tester
      .widget<Opacity>(
        find.ancestor(of: found, matching: find.byType(Opacity)).first,
      )
      .opacity;
  final scale = tester
      .widget<Transform>(find.byKey(const ValueKey('wallet-total-scale')))
      .transform
      // The x scale. getMaxScaleOnAxis also counts z, which is always 1.
      .storage[0];
  return (opacity: opacity, scale: scale);
}

void main() {
  test('the whole sequence is exactly one second', () {
    expect(CoinsToWalletAnimation.duration, const Duration(seconds: 1));
  });

  testWidgets('the total is hidden until the coins are in, at 0.8 s', (
    tester,
  ) async {
    await tester.pumpWidget(_scene());
    await tester.pump();

    for (final step in [200, 300, 290]) {
      await tester.pump(Duration(milliseconds: step));
      expect(_total(tester, '1,000'), isNull, reason: 'coins still arriving');
    }
    // 790 ms: the last coin is landing. 10 ms later the total is on its way.
    await tester.pump(const Duration(milliseconds: 15));
    expect(_total(tester, '1,000'), isNotNull);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'it rises from 80% and 60% to full between 0.8 s and the settle',
    (tester) async {
      await tester.pumpWidget(_scene());
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 805));
      final early = _total(tester, '1,000');
      expect(early, isNotNull);
      expect(early!.opacity, closeTo(0.6, 0.05), reason: 'starting faint');
      expect(early.scale, closeTo(0.8, 0.05), reason: 'and small');

      await tester.pump(const Duration(milliseconds: 195));
      final settled = _total(tester, '1,000')!;
      expect(settled.opacity, 1);
      expect(settled.scale, closeTo(1, 0.01), reason: 'the breath has passed');

      await tester.pumpAndSettle();
    },
  );

  group('the coins sound', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      SoundSettings.instance.resetForTest();
      await AppSounds.coins.resetForTest();
    });

    tearDown(() {
      AppSound.enabled = true;
      SoundSettings.instance.resetForTest();
    });

    test('is its own bundled clip', () {
      expect(AppSounds.coins.asset, 'assets/sounds/coins.wav');
    });

    testWidgets('plays once, as the animation starts', (tester) async {
      AppSound.enabled = true;
      await tester.pumpWidget(_scene());
      await tester.pump();
      expect(AppSounds.coins.plays, 1);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(AppSounds.coins.plays, 1, reason: 'not again as it plays');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stays quiet when the shopper has sound off', (tester) async {
      AppSound.enabled = true;
      await SoundSettings.instance.setEnabled(false);
      await tester.pumpWidget(_scene());
      await tester.pump(const Duration(milliseconds: 1000));
      expect(AppSounds.coins.plays, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('reports when the one second has played', (tester) async {
    var finished = 0;
    await tester.pumpWidget(_scene(onFinished: () => finished++));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 990));
    expect(finished, 0);
    await tester.pump(const Duration(milliseconds: 20));
    expect(finished, 1);
  });

  testWidgets('reveals whatever value it is given', (tester) async {
    // What makes it ready for the real balance: the number is an input, not
    // part of the animation.
    await tester.pumpWidget(_scene(value: 2450));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('2,450'), findsOneWidget);
    expect(find.text('1,000'), findsNothing);
  });

  testWidgets('a preview is labelled as one, on screen and aloud', (
    tester,
  ) async {
    await tester.pumpWidget(_scene(preview: true));
    await tester.pump();

    expect(find.text('Preview'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('No points were added')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
  });

  testWidgets('a real total carries no preview label', (tester) async {
    await tester.pumpWidget(_scene());
    await tester.pump();

    expect(find.text('Preview'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion still reveals the total, without the flight', (
    tester,
  ) async {
    await tester.pumpWidget(_scene(reducedMotion: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    final shown = _total(tester, '1,000')!;
    expect(shown.opacity, 1);
    expect(tester.takeException(), isNull);
  });

  group('shown over the page', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => CoinsToWalletAnimation.show(
                    context,
                    value: CoinsToWalletAnimation.demoValue,
                    preview: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
    }

    testWidgets('closes itself shortly after the sequence', (tester) async {
      await open(tester);
      expect(find.byType(CoinsToWalletAnimation), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(CoinsToWalletAnimation), findsOneWidget);

      await tester.pump(CoinsToWalletAnimation.linger);
      await tester.pumpAndSettle();
      expect(find.byType(CoinsToWalletAnimation), findsNothing);
    });

    testWidgets('and a tap closes it early', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(CoinsToWalletAnimation));
      await tester.pumpAndSettle();
      expect(find.byType(CoinsToWalletAnimation), findsNothing);
    });

    testWidgets('its text has a style, not the warning underline', (
      tester,
    ) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 1));

      final style = DefaultTextStyle.of(tester.element(find.text('1,000')))
          .style;
      expect(style.decoration, isNot(TextDecoration.underline));

      await tester.pump(CoinsToWalletAnimation.linger);
      await tester.pumpAndSettle();
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/presentation/account_screen.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

/// WCAG contrast between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Every box on the page that paints a shadow.
Iterable<BoxDecoration> _lifted(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .where((d) => (d.boxShadow ?? const []).isNotEmpty);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    stubCatalog();
  });

  tearDown(clearApiStub);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AccountScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the account blocks are lifted, and nothing else is', (
    tester,
  ) async {
    signInForTest();
    await pump(tester);

    // The one card that now holds all the account items, and inside it the
    // three blocks that were already lifted: Account, Account settings, Help
    // and information.
    expect(_lifted(tester), hasLength(4));

    // The quick-action tiles and the rows inside the cards stay flat.
    expect(find.text('Account settings'), findsOneWidget);
    expect(find.text('Help and information'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('the guest card does not offer Google or Apple itself', (
    tester,
  ) async {
    // Even with both switched on at the server. They belong to the sign-in
    // and create account pages, which the two buttons on this card open.
    final auth = FakeApi()
      ..on(
        'GET',
        '/settings',
        body: {
          'external': {'google': true, 'apple': true, 'email': true},
        },
      );
    AuthStore.instance.repositoryForTest = AuthRepository(
      sessions: SessionStore.instance,
      dio: auth.dio(baseUrl: 'https://test.local/auth/v1'),
    );

    await pump(tester);

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('or continue with'), findsNothing);
  });

  testWidgets('what the guest card says can be read against it', (
    tester,
  ) async {
    await pump(tester);

    final card = tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.text('Sign In'),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => (d.boxShadow ?? const []).isNotEmpty);
    final ground = card.color!;
    expect(ground.a, 1.0, reason: 'an opaque fill, not a tint over the page');

    final subtitle = tester.widget<Text>(
      find.textContaining('Track orders, save addresses'),
    );
    final ink = Color.alphaBlend(subtitle.style!.color!, ground);
    expect(
      _contrast(ink, ground),
      greaterThanOrEqualTo(4.5),
      reason: 'body-size text needs 4.5:1',
    );

    // The outlined button's edge and words are the brand blue, not the
    // hairline that disappeared into the tint.
    final signUp = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Sign Up'),
    );
    final primary = AppTheme.light.colorScheme.primary;
    expect(signUp.style!.side!.resolve({})!.color, primary);
    expect(signUp.style!.foregroundColor!.resolve({}), primary);
  });

  testWidgets('a guest gets the same lift on the block that asks them in', (
    tester,
  ) async {
    await pump(tester);

    expect(_lifted(tester), isNotEmpty);
    expect(find.text('Account settings'), findsOneWidget);
  });

  testWidgets('every lifted card carries the same shadow', (tester) async {
    signInForTest();
    await pump(tester);

    final shadows = _lifted(tester).map((d) => d.boxShadow!.single).toSet();
    expect(shadows, hasLength(1), reason: 'one shadow, defined once');
  });

  testWidgets('and every card runs the full width of the page', (tester) async {
    signInForTest();
    await pump(tester);

    final width = tester.getSize(find.byType(AccountScreen)).width;
    for (final label in ['Profile settings', 'Help centre']) {
      final card = find
          .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
          .first;
      expect(tester.getSize(card).width, width, reason: label);
    }
  });

  testWidgets('and the rows still open what they always did', (tester) async {
    signInForTest();
    await pump(tester);

    await tester.scrollUntilVisible(find.text('Help centre'), 200);
    expect(find.text('Help centre'), findsOneWidget);
    expect(find.text('Profile settings'), findsOneWidget);
  });
}

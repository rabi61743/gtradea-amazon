import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/auth/data/remembered_email.dart';
import 'package:gtradea_amazon/features/auth/presentation/auth_screen.dart';
import 'package:gtradea_amazon/shared/widgets/brand_wordmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// GoTrue's own shape, enough of it for this screen.
Map<String, dynamic> _session({String email = 'rabi@example.com'}) => {
  'access_token': 'access-token',
  'refresh_token': 'refresh-token',
  'expires_in': 3600,
  'token_type': 'bearer',
  'user': {'id': 'user-1', 'email': email},
};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    api = FakeApi();
    // GoTrue sits on its own base, and the store is the seam every auth test
    // drives it through.
    AuthStore.instance.repositoryForTest = AuthRepository(
      sessions: SessionStore.instance,
      dio: api.dio(baseUrl: 'https://test.local/auth/v1'),
    );
  });

  tearDown(() async {
    clearApiStub();
    await RememberedEmail.clear();
  });

  /// The auth screen on a window tall enough to hold the whole form.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AuthScreen()),
    );
    await tester.pumpAndSettle();
  }

  /// The provider list the button is gated on.
  void wireProviders({bool google = true}) {
    api.on(
      'GET',
      '/settings',
      body: {
        'external': {'google': google, 'email': true, 'apple': false},
      },
    );
  }

  group('what the page shows', () {
    testWidgets('the supplied logo, and what the page is for', (tester) async {
      wireProviders();
      await pump(tester);

      // The lockup carries the name, so it is not set again as text under it.
      // Found by the name it carries: Image.asset wraps its provider in a
      // ResizeImage when a cache width is given, so the provider type is not
      // the thing to match on.
      final logo = tester.widget<Image>(
        find.byWidgetPredicate(
          (w) => w is Image && w.semanticLabel == AppBrand.name,
        ),
      );
      expect(logo.fit, BoxFit.contain);
      expect(logo.semanticLabel, AppBrand.name);
      expect(find.text('GtradeA'), findsNothing);

      expect(find.text('Sign in to continue shopping'), findsOneWidget);
    });

    testWidgets('drawn at the artwork own shape, never stretched', (
      tester,
    ) async {
      wireProviders();
      await pump(tester);

      final box = tester.getSize(
        find
            .ancestor(
              of: find.byType(Image).first,
              matching: find.byType(AspectRatio),
            )
            .first,
      );

      expect(box.width / box.height, closeTo(AppBrand.lockupAspectRatio, 0.01));
      // Inside the form's own column, so it cannot reach a field or a button.
      expect(box.width, lessThanOrEqualTo(300));
    });

    testWidgets('the two fields, named on themselves', (tester) async {
      wireProviders();
      await pump(tester);

      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('remember me, forgot password, and the reassurance', (
      tester,
    ) async {
      wireProviders();
      await pump(tester);

      expect(find.text('Remember me'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Your data is 100% secure'), findsOneWidget);
      expect(find.text('We never share your information'), findsOneWidget);
    });

    testWidgets('and the password can be shown', (tester) async {
      wireProviders();
      await pump(tester);

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField).last,
          matching: find.byType(TextField),
        ),
      );
      expect(field.obscureText, isTrue);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();

      final shown = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField).last,
          matching: find.byType(TextField),
        ),
      );
      expect(shown.obscureText, isFalse);
    });
  });

  group('the sign-up half', () {
    testWidgets('opens with the same logo', (tester) async {
      wireProviders();
      tester.view.physicalSize = const Size(1100, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const AuthScreen(initialMode: AuthMode.signUp),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.semanticLabel == AppBrand.name,
        ),
        findsOneWidget,
      );
      // The form under it is untouched.
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Create account'), findsWidgets);
    });
  });

  group('continue with Google', () {
    testWidgets('is offered when the server has it configured', (tester) async {
      wireProviders();
      await pump(tester);

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('or continue with'), findsOneWidget);
    });

    testWidgets('and is not offered when it does not', (tester) async {
      // A button that opens a page saying "Unsupported provider" is worse than
      // no button.
      wireProviders(google: false);
      await pump(tester);

      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('or continue with'), findsNothing);
    });

    testWidgets('nor when the settings call fails', (tester) async {
      api.on('GET', '/settings', status: 500, body: {});
      await pump(tester);

      expect(find.text('Continue with Google'), findsNothing);
      // The rest of the page is unaffected: email and password still work.
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('remember me', () {
    testWidgets('a signed-in address comes back on the next visit', (
      tester,
    ) async {
      wireProviders();
      api.on('POST', '/token', body: _session());
      await pump(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'rabi@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'correct-horse',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(await RememberedEmail.read(), 'rabi@example.com');

      // A fresh screen fills it in. Torn down first, or the framework reuses
      // the State and initState never runs again.
      AuthStore.instance.signOut();
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester);
      expect(find.text('rabi@example.com'), findsOneWidget);
    });

    testWidgets('unticking forgets it there and then', (tester) async {
      // Not at the next sign-in: somebody clearing it on a shared handset
      // means now.
      await RememberedEmail.write('rabi@example.com');
      wireProviders();
      await pump(tester);

      expect(find.text('rabi@example.com'), findsOneWidget);

      await tester.tap(find.text('Remember me'));
      await tester.pumpAndSettle();

      expect(await RememberedEmail.read(), isNull);
    });

    testWidgets('and an unticked sign-in leaves nothing behind', (
      tester,
    ) async {
      wireProviders();
      api.on('POST', '/token', body: _session());
      await pump(tester);

      await tester.tap(find.text('Remember me'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'rabi@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'correct-horse',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(AuthStore.instance.isSignedIn, isTrue);
      expect(await RememberedEmail.read(), isNull);
    });

    testWidgets('a refused sign-in remembers nothing', (tester) async {
      // The address is only worth keeping once the server has accepted it.
      wireProviders();
      api.on(
        'POST',
        '/token',
        status: 400,
        body: {'error': 'Invalid login credentials'},
      );
      await pump(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'typo@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'correct-horse',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(await RememberedEmail.read(), isNull);
      expect(
        find.text('That email and password do not match an account.'),
        findsOneWidget,
      );
    });
  });
}

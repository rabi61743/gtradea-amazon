import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/config/env.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/auth/presentation/forgot_password_screen.dart';
import 'package:gtradea_amazon/features/auth/presentation/reset_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// What `POST /verify` answers with for a good recovery token: a session.
Map<String, dynamic> _verified() => {
  'access_token': 'recovery-access',
  'refresh_token': 'recovery-refresh',
  'expires_in': 3600,
  'token_type': 'bearer',
};

Map<String, dynamic> _user() => {'id': 'user-1', 'email': 'rabi@example.com'};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AuthStore.instance.resetForTest();

    api = FakeApi();
    AuthStore.instance.repositoryForTest = AuthRepository(
      sessions: SessionStore.instance,
      dio: api.dio(baseUrl: 'https://test.local/auth/v1'),
    );
  });

  tearDown(clearApiStub);

  Future<void> pumpForgot(
    WidgetTester tester, {
    String initialEmail = '',
  }) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ForgotPasswordScreen(initialEmail: initialEmail),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpReset(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ResetPasswordScreen()),
    );
    await tester.pumpAndSettle();
  }

  group('asking for a reset link', () {
    testWidgets('a malformed address never reaches the server', (tester) async {
      await pumpForgot(tester);

      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('an empty one says so', (tester) async {
      await pumpForgot(tester);

      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('a valid one is sent to GoTrue, with where the link lands', (
      tester,
    ) async {
      api.on('POST', '/recover', body: {});
      await pumpForgot(tester);

      await tester.enterText(find.byType(TextFormField), 'rabi@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      final call = api.calls.single;
      expect(call.method, 'POST');
      expect(call.path, '/recover');
      expect(call.json['email'], 'rabi@example.com');
      expect(call.json['redirect_to'], Env.passwordResetUrl);
    });

    testWidgets('and the confirmation does not say whether it exists', (
      tester,
    ) async {
      // The whole point: a page that says "no such account" is a way to find
      // out who shops here.
      api.on('POST', '/recover', body: {});
      await pumpForgot(tester);

      await tester.enterText(find.byType(TextFormField), 'rabi@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('If '), findsOneWidget);
      expect(find.textContaining('rabi@example.com'), findsOneWidget);
      expect(find.textContaining('has an account'), findsOneWidget);
    });

    testWidgets('the address is carried in from the sign-in form', (
      tester,
    ) async {
      await pumpForgot(tester, initialEmail: 'rabi@example.com');

      expect(find.text('rabi@example.com'), findsOneWidget);
    });

    testWidgets('a second tap while it is in flight sends nothing', (
      tester,
    ) async {
      api.onCall(
        'POST',
        '/recover',
        (_) => reply({}, delay: const Duration(milliseconds: 300)),
      );
      await pumpForgot(tester);

      await tester.enterText(find.byType(TextFormField), 'rabi@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pump();

      // Mid-flight: the button shows the spinner and answers to nothing.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(CircularProgressIndicator));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpAndSettle();
      expect(api.calls, hasLength(1));
    });

    testWidgets('being rate limited says what to do about it', (tester) async {
      api.on(
        'POST',
        '/recover',
        status: 429,
        body: {'msg': 'For security purposes rate limit exceeded'},
      );
      await pumpForgot(tester);

      await tester.enterText(find.byType(TextFormField), 'rabi@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Wait a minute'), findsOneWidget);
      // Not the success panel: nothing was sent.
      expect(find.text('Check your email'), findsNothing);
    });

    testWidgets('a server failure is shown, not swallowed', (tester) async {
      api.on('POST', '/recover', status: 500, body: {'msg': 'boom'});
      await pumpForgot(tester);

      await tester.enterText(find.byType(TextFormField), 'rabi@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.text('Check your email'), findsNothing);
      expect(find.text('Send reset link'), findsOneWidget);
    });
  });

  group('the token out of a link', () {
    test('from the query, however it is named', () {
      expect(
        AuthRepository.tokenFromLink(
          'https://gtradea.com/reset-password?token=abc123&type=recovery',
        ),
        'abc123',
      );
      expect(
        AuthRepository.tokenFromLink(
          'https://gtradea.com/auth?mode=reset&token_hash=xyz789',
        ),
        'xyz789',
      );
    });

    test('from the fragment, which is where GoTrue puts it', () {
      expect(
        AuthRepository.tokenFromLink(
          'https://gtradea.com/reset-password#token_hash=frag-token&type=recovery',
        ),
        'frag-token',
      );
    });

    test('a bare code is the token itself', () {
      expect(AuthRepository.tokenFromLink('  pkce_abc123  '), 'pkce_abc123');
    });

    test('and something with no token in it is not one', () {
      expect(AuthRepository.tokenFromLink('https://gtradea.com/'), isNull);
      expect(AuthRepository.tokenFromLink(''), isNull);
      expect(AuthRepository.tokenFromLink('please reset my password'), isNull);
    });
  });

  group('setting the new password', () {
    testWidgets('trades the token for a session and sets the password', (
      tester,
    ) async {
      api.on('POST', '/verify', body: _verified());
      api.on('PUT', '/user', body: _user());
      await pumpReset(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(
        fields.at(0),
        'https://gtradea.com/reset-password?token=abc123',
      );
      await tester.enterText(fields.at(1), 'new-password-1');
      await tester.enterText(fields.at(2), 'new-password-1');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      final verify = api.calls.first;
      expect(verify.path, '/verify');
      expect(verify.json['type'], 'recovery');
      expect(verify.json['token_hash'], 'abc123');

      final update = api.calls.last;
      expect(update.method, 'PUT');
      expect(update.path, '/user');
      expect(update.json['password'], 'new-password-1');
      // The short-lived session from the exchange, not the app's own.
      expect(update.headers['Authorization'], 'Bearer recovery-access');

      expect(find.text('Password updated'), findsOneWidget);
      expect(AuthStore.instance.isSignedIn, isTrue);
    });

    testWidgets('a short password is refused before any call', (tester) async {
      await pumpReset(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'https://x.test/?token=abc123');
      await tester.enterText(fields.at(1), 'short');
      await tester.enterText(fields.at(2), 'short');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('so is a pair that does not match', (tester) async {
      await pumpReset(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'https://x.test/?token=abc123');
      await tester.enterText(fields.at(1), 'new-password-1');
      await tester.enterText(fields.at(2), 'new-password-2');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(find.text('Both passwords must match'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('a link with no token in it never reaches the server', (
      tester,
    ) async {
      await pumpReset(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'https://gtradea.com/');
      await tester.enterText(fields.at(1), 'new-password-1');
      await tester.enterText(fields.at(2), 'new-password-1');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(
        find.text('That does not look like a reset link.'),
        findsOneWidget,
      );
      expect(api.calls, isEmpty);
    });

    testWidgets('an expired link is the server saying so, in plain words', (
      tester,
    ) async {
      // The live answer: 403 otp_expired, "Email link is invalid or has
      // expired".
      api.on(
        'POST',
        '/verify',
        status: 403,
        body: {
          'error_code': 'otp_expired',
          'msg': 'Email link is invalid or has expired',
        },
      );
      await pumpReset(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'https://x.test/?token=stale');
      await tester.enterText(fields.at(1), 'new-password-1');
      await tester.enterText(fields.at(2), 'new-password-1');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('already been used or has expired'),
        findsOneWidget,
      );
      expect(find.text('Password updated'), findsNothing);
      expect(AuthStore.instance.isSignedIn, isFalse);
      // The password was not set, so nothing followed the refusal.
      expect(api.calls, hasLength(1));
    });

    testWidgets('the password is never shown back in the clear', (
      tester,
    ) async {
      await pumpReset(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'new-password-1');
      await tester.pump();

      for (final index in [1, 2]) {
        final field = tester.widget<TextField>(
          find.descendant(
            of: fields.at(index),
            matching: find.byType(TextField),
          ),
        );
        expect(field.obscureText, isTrue, reason: 'field $index');
      }
    });
  });
}

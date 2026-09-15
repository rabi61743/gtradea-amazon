import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/security/presentation/login_activity_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

/// The user object as GoTrue returns it for `GET /user`.
Map<String, dynamic> _user({String provider = 'email'}) => {
  'id': 'user-1',
  'email': 'rabi@example.com',
  'last_sign_in_at': '2026-09-10T08:30:00Z',
  'app_metadata': {
    'provider': provider,
    'providers': [provider],
  },
  'identities': [
    {'provider': provider},
  ],
};

/// A stand-in GoTrue with a live session parked in the store.
FakeApi _goTrue({int expiresAt = 0}) {
  SessionStore.instance.write(
    AuthSession(
      accessToken: 'this-device',
      refreshToken: 'this-refresh',
      expiresAt: expiresAt == 0 ? null : expiresAt,
    ),
  );
  final auth = FakeApi();
  AuthStore.instance.repositoryForTest = AuthRepository(
    sessions: SessionStore.instance,
    dio: auth.dio(baseUrl: 'https://test.local/auth/v1'),
  );
  return auth;
}

Future<void> _pump(WidgetTester tester, {Size size = const Size(400, 900)}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const LoginActivityScreen()),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSignOutOthers(WidgetTester tester) async {
  await tester.tap(find.text('Sign out all other devices'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    ensureApiStub();
    signInForTest();
  });

  tearDown(clearApiStub);

  group('the repository', () {
    test('asks GoTrue to end the other sessions, as this one', () async {
      final auth = _goTrue()..on('POST', '/logout', status: 204);
      await AuthStore.instance.repositoryForTestValue.signOutOtherDevices();

      final call = auth.calls.single;
      expect(call.path, '/logout');
      expect(call.query, {'scope': 'others'});
      expect(call.authorization, 'Bearer this-device');
      // This device is still signed in.
      expect(await SessionStore.instance.read(), isNotNull);
    });

    test('renews an expired token first rather than failing', () async {
      final auth = _goTrue(expiresAt: 1)
        ..on('POST', '/token', body: const {
          'access_token': 'renewed',
          'refresh_token': 'r2',
          'expires_in': 3600,
        })
        ..on('POST', '/logout', status: 204);
      await AuthStore.instance.repositoryForTestValue.signOutOtherDevices();

      expect(auth.calls.map((c) => c.path), ['/token', '/logout']);
      expect(auth.calls.last.authorization, 'Bearer renewed');
    });

    test('a refused session is signed out, not reported as done', () async {
      _goTrue().on('POST', '/logout', status: 401, body: const {'msg': 'x'});
      await expectLater(
        AuthStore.instance.repositoryForTestValue.signOutOtherDevices(),
        throwsA(isA<Object>()),
      );
      expect(await SessionStore.instance.read(), isNull);
    });
  });

  group('the screen', () {
    testWidgets('shows what the server says about this account', (
      tester,
    ) async {
      _goTrue().on('GET', '/user', body: _user());
      await _pump(tester);

      expect(find.text('Current device'), findsOneWidget);
      expect(find.text('rabi@example.com'), findsOneWidget);
      expect(find.text('Email and password'), findsOneWidget);
      // The date the server sent, in local time.
      expect(find.textContaining('Sep 2026'), findsOneWidget);
      // And says what it cannot show, rather than inventing it.
      expect(find.textContaining('not available yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading, then an error with a retry that works', (
      tester,
    ) async {
      var fail = true;
      _goTrue().onCall(
        'GET',
        '/user',
        (_) => fail
            ? reply(const {'msg': 'down'}, status: 500)
            : reply(_user()),
      );
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const LoginActivityScreen()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('Login details could not be loaded.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Email and password'), findsOneWidget);
    });

    testWidgets('an expired session says so', (tester) async {
      _goTrue().on('GET', '/user', status: 401, body: const {'msg': 'x'});
      await _pump(tester);
      expect(find.text('Your session has expired'), findsOneWidget);
    });

    testWidgets('a wrong password is refused and nothing is signed out', (
      tester,
    ) async {
      final auth = _goTrue()
        ..on('GET', '/user', body: _user())
        ..on('POST', '/token', status: 400, body: const {
          'error': 'invalid_grant',
          'msg': 'Invalid login credentials',
        })
        ..on('POST', '/logout', status: 204);
      await _pump(tester);
      await _openSignOutOthers(tester);

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Sign out others'));
      await tester.pumpAndSettle();

      expect(find.text('That password is not correct.'), findsOneWidget);
      expect(auth.calls.where((c) => c.path == '/logout'), isEmpty);
      // The dialog stays, so they can try again.
      expect(find.text('Sign out all other devices?'), findsOneWidget);
    });

    testWidgets('the right password signs the others out, and says so', (
      tester,
    ) async {
      final auth = _goTrue()
        ..on('GET', '/user', body: _user())
        ..on('POST', '/token', body: const {
          'access_token': 'check-only',
          'refresh_token': 'x',
        })
        ..on('POST', '/logout', status: 204);
      await _pump(tester);
      await _openSignOutOthers(tester);

      await tester.enterText(find.byType(TextField), 'right-password');
      await tester.tap(find.text('Sign out others'));
      await tester.pumpAndSettle();

      final logout = auth.calls.singleWhere((c) => c.path == '/logout');
      expect(logout.query, {'scope': 'others'});
      // With this device's token, not the one the check produced.
      expect(logout.authorization, 'Bearer this-device');
      expect(find.text('Signed out of all other devices.'), findsOneWidget);
      expect(AuthStore.instance.isSignedIn, isTrue);
    });

    testWidgets('a failed request is reported, never claimed as done', (
      tester,
    ) async {
      _goTrue()
        ..on('GET', '/user', body: _user())
        ..on('POST', '/token', body: const {
          'access_token': 'a',
          'refresh_token': 'r',
        })
        ..on('POST', '/logout', status: 500, body: const {'msg': 'boom'});
      await _pump(tester);
      await _openSignOutOthers(tester);
      await tester.enterText(find.byType(TextField), 'right-password');
      await tester.tap(find.text('Sign out others'));
      await tester.pumpAndSettle();

      expect(find.text('Signed out of all other devices.'), findsNothing);
      expect(find.text('Sign out all other devices?'), findsOneWidget);
    });

    testWidgets('a Google-only account confirms without a password', (
      tester,
    ) async {
      final auth = _goTrue()
        ..on('GET', '/user', body: _user(provider: 'google'))
        ..on('POST', '/logout', status: 204);
      await _pump(tester);
      expect(find.text('Google'), findsOneWidget);
      await _openSignOutOthers(tester);

      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Sign out others'));
      await tester.pumpAndSettle();
      expect(auth.calls.where((c) => c.path == '/token'), isEmpty);
      expect(auth.calls.where((c) => c.path == '/logout'), hasLength(1));
    });

    testWidgets('sign out of this device asks first', (tester) async {
      _goTrue()
        ..on('GET', '/user', body: _user())
        ..on('POST', '/logout', status: 204);
      await _pump(tester);

      await tester.tap(find.text('Sign out of this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(AuthStore.instance.isSignedIn, isTrue);

      await tester.tap(find.text('Sign out of this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    testWidgets('fits a narrow phone without overflowing', (tester) async {
      _goTrue().on('GET', '/user', body: _user());
      await _pump(tester, size: const Size(320, 700));
      expect(tester.takeException(), isNull);
    });
  });
}

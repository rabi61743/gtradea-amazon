import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/auth/presentation/two_factor_challenge_screen.dart';
import 'package:gtradea_amazon/features/security/data/mfa_repository.dart';
import 'package:gtradea_amazon/features/security/data/mfa_store.dart';
import 'package:gtradea_amazon/features/security/presentation/two_factor_screen.dart';

import 'support/fake_api.dart';

/// A token GoTrue would issue, at the given assurance level. The signature is
/// not real and does not need to be: the app never judges one -- only the
/// server does -- and reads `aal` purely to choose a screen.
String jwt(String aal) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': 'user-1', 'aal': aal})}.sig';
}

Map<String, dynamic> user({List<Map<String, dynamic>> factors = const []}) => {
  'id': 'user-1',
  'email': 'two@example.com',
  'app_metadata': {
    'providers': ['email'],
  },
  'user_metadata': {'first_name': 'Two'},
  'factors': factors,
};

Map<String, dynamic> factor({String status = 'verified', String id = 'f1'}) => {
  'id': id,
  'factor_type': 'totp',
  'status': status,
  'friendly_name': 'Gtradea authenticator',
};

Map<String, dynamic> tokenBody(String aal, Map<String, dynamic> u) => {
  'access_token': jwt(aal),
  'refresh_token': 'refresh-$aal',
  'expires_in': 3600,
  'user': u,
};

late FakeApi gotrue;

void wire() {
  gotrue = FakeApi();
  final dio = gotrue.dio(baseUrl: 'https://test.local/auth/v1');
  final auth = AuthRepository(sessions: SessionStore.instance, dio: dio);
  final mfa = MfaRepository(dio: dio);
  AuthStore.instance
    ..repositoryForTest = auth
    ..mfaRepositoryForTest = mfa;
  MfaStore.instance
    ..authRepositoryForTest = auth
    ..mfaRepositoryForTest = mfa;
  gotrue.on('POST', '/logout', status: 204);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    MfaStore.instance.resetForTest();
    wire();
  });

  group('reading the assurance level', () {
    test('aal comes from the token and defaults to aal1', () {
      expect(MfaRepository.aalOf(jwt('aal2')), 'aal2');
      expect(MfaRepository.aalOf(jwt('aal1')), 'aal1');
      expect(MfaRepository.aalOf('not-a-jwt'), 'aal1');
    });

    test('a second factor is needed only for verified factors at aal1', () {
      AuthSession s(String aal, List<Map<String, dynamic>> f) =>
          AuthSession.fromJson(tokenBody(aal, user(factors: f)));

      expect(MfaRepository.needsSecondFactor(s('aal1', [factor()])), isTrue);
      expect(MfaRepository.needsSecondFactor(s('aal2', [factor()])), isFalse);
      expect(MfaRepository.needsSecondFactor(s('aal1', const [])), isFalse);
      // An unfinished setup protects nothing, so it asks for nothing.
      expect(
        MfaRepository.needsSecondFactor(
          s('aal1', [factor(status: 'unverified')]),
        ),
        isFalse,
      );
    });

    test('the QR data URI is decoded to SVG markup', () {
      expect(
        MfaRepository.svgFromDataUri('data:image/svg+xml;utf-8,<svg></svg>'),
        '<svg></svg>',
      );
      expect(
        MfaRepository.svgFromDataUri(
          'data:image/svg+xml;utf-8,%3Csvg%3E%3C%2Fsvg%3E',
        ),
        '<svg></svg>',
      );
    });
  });

  group('signing in to an account with 2FA', () {
    setUp(() {
      gotrue.on(
        'POST',
        '/token',
        body: tokenBody('aal1', user(factors: [factor()])),
      );
      gotrue.on('POST', '/factors/f1/challenge', body: {'id': 'c1'});
    });

    test('the right password alone does not sign in or store anything', () async {
      await expectLater(
        AuthStore.instance.signIn(email: 'two@example.com', password: 'pw'),
        throwsA(isA<MfaRequired>()),
      );
      expect(AuthStore.instance.isSignedIn, isFalse);
      expect(AuthStore.instance.awaitingSecondFactor, isTrue);
      expect(
        await SessionStore.instance.read(),
        isNull,
        reason: 'the aal1 session must never reach storage',
      );
    });

    test('a wrong code is refused by the server and nothing changes', () async {
      gotrue.on(
        'POST',
        '/factors/f1/verify',
        status: 422,
        body: {
          'code': 422,
          'error_code': 'mfa_verification_failed',
          'msg': 'Invalid TOTP code entered',
        },
      );
      await expectLater(
        AuthStore.instance.signIn(email: 'two@example.com', password: 'pw'),
        throwsA(isA<MfaRequired>()),
      );

      await expectLater(
        AuthStore.instance.completeMfa('000000'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            MfaError.invalidCode,
          ),
        ),
      );
      expect(AuthStore.instance.isSignedIn, isFalse);
      expect(await SessionStore.instance.read(), isNull);
      expect(
        AuthStore.instance.awaitingSecondFactor,
        isTrue,
        reason: 'the person can try again',
      );
    });

    test('a valid code signs in with the aal2 session the server issued', () async {
      gotrue.on(
        'POST',
        '/factors/f1/verify',
        body: tokenBody('aal2', user(factors: [factor()])),
      );
      await expectLater(
        AuthStore.instance.signIn(email: 'two@example.com', password: 'pw'),
        throwsA(isA<MfaRequired>()),
      );

      await AuthStore.instance.completeMfa('123456');

      expect(AuthStore.instance.isSignedIn, isTrue);
      expect(AuthStore.instance.awaitingSecondFactor, isFalse);
      final stored = await SessionStore.instance.read();
      expect(MfaRepository.aalOf(stored!.accessToken), 'aal2');

      final verify = gotrue.calls.firstWhere(
        (c) => c.path == '/factors/f1/verify',
      );
      expect((verify.body as Map)['code'], '123456');
      expect((verify.body as Map)['challenge_id'], 'c1');
      expect(
        verify.headers['Authorization'],
        'Bearer ${jwt('aal1')}',
        reason: 'the aal1 token is used to verify, and only for that',
      );
    });

    test('an expired challenge is replaced, and the next code uses it', () async {
      var verifies = 0;
      gotrue.onCall('POST', '/factors/f1/verify', (_) {
        verifies++;
        return verifies == 1
            ? const FakeReply(
                status: 422,
                body: {
                  'error_code': 'mfa_challenge_expired',
                  'msg': 'Challenge expired',
                },
              )
            : FakeReply(status: 200, body: tokenBody('aal2', user(factors: [factor()])));
      });
      await expectLater(
        AuthStore.instance.signIn(email: 'two@example.com', password: 'pw'),
        throwsA(isA<MfaRequired>()),
      );

      await expectLater(
        AuthStore.instance.completeMfa('111111'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            MfaError.challengeExpired,
          ),
        ),
      );
      await AuthStore.instance.completeMfa('222222');

      expect(AuthStore.instance.isSignedIn, isTrue);
      expect(
        gotrue.calls.where((c) => c.path == '/factors/f1/challenge').length,
        2,
      );
    });

    test('cancelling ends the half-signed-in session on the server', () async {
      await expectLater(
        AuthStore.instance.signIn(email: 'two@example.com', password: 'pw'),
        throwsA(isA<MfaRequired>()),
      );
      await AuthStore.instance.cancelMfa();

      expect(AuthStore.instance.awaitingSecondFactor, isFalse);
      expect(AuthStore.instance.isSignedIn, isFalse);
      expect(gotrue.calls.any((c) => c.path == '/logout'), isTrue);
    });

    test('a stored aal1 session for a 2FA account is not trusted at startup', () async {
      await SessionStore.instance.write(
        AuthSession.fromJson(tokenBody('aal1', user(factors: [factor()]))),
      );
      await AuthStore.instance.load();
      expect(AuthStore.instance.isSignedIn, isFalse);
    });
  });

  group('signing in without 2FA', () {
    test('is unchanged: stored and signed in straight away', () async {
      gotrue.on('POST', '/token', body: tokenBody('aal1', user()));
      await AuthStore.instance.signIn(email: 'two@example.com', password: 'pw');

      expect(AuthStore.instance.isSignedIn, isTrue);
      expect(await SessionStore.instance.read(), isNotNull);
      expect(gotrue.calls.any((c) => c.path.startsWith('/factors')), isFalse);
    });
  });

  group('verifying an email code', () {
    test('never downgrades an aal2 session to aal1', () async {
      await SessionStore.instance.write(
        AuthSession.fromJson(tokenBody('aal2', user(factors: [factor()]))),
      );
      gotrue.on(
        'POST',
        '/verify',
        body: tokenBody('aal1', user(factors: [factor()])),
      );

      await AuthStore.instance.repositoryForTestValue.verifyEmailOtp(
        email: 'new@example.com',
        token: '123456',
      );

      final stored = await SessionStore.instance.read();
      expect(MfaRepository.aalOf(stored!.accessToken), 'aal2');
    });
  });

  group('the 2FA setting', () {
    Future<void> signedIn(List<Map<String, dynamic>> factors, {String aal = 'aal1'}) async {
      final session = AuthSession.fromJson(
        tokenBody(aal, user(factors: factors)),
      );
      await SessionStore.instance.write(session);
      await AuthStore.instance.load();
      gotrue.on('GET', '/user', body: user(factors: factors));
    }

    test('reads Disabled, Enabled and Setup incomplete from the server', () async {
      await signedIn(const []);
      await MfaStore.instance.load();
      expect(MfaStore.instance.status, MfaStatus.disabled);

      gotrue.on('GET', '/user', body: user(factors: [factor(status: 'unverified')]));
      await MfaStore.instance.load();
      expect(MfaStore.instance.status, MfaStatus.setupIncomplete);

      gotrue.on('GET', '/user', body: user(factors: [factor()]));
      await MfaStore.instance.load();
      expect(MfaStore.instance.status, MfaStatus.enabled);
    });

    test('turning on needs the password, and is only on after the server verifies', () async {
      await signedIn(const []);
      gotrue.on('POST', '/token', body: tokenBody('aal1', user()));
      gotrue.on(
        'POST',
        '/factors',
        body: {
          'id': 'f9',
          'type': 'totp',
          'totp': {
            'secret': 'JBSWY3DPEHPK3PXP',
            'qr_code': 'data:image/svg+xml;utf-8,<svg></svg>',
            'uri': 'otpauth://totp/Gtradea:two@example.com?secret=JBSWY3DPEHPK3PXP',
          },
        },
      );

      final setup = await MfaStore.instance.startEnable(password: 'pw');
      expect(setup.secret, 'JBSWY3DPEHPK3PXP');
      expect(setup.qrSvg, '<svg></svg>');
      expect(
        gotrue.calls.first.path,
        '/token',
        reason: 'the password is checked before anything is generated',
      );
      expect(MfaStore.instance.status, isNot(MfaStatus.enabled));

      // A wrong code: the server refuses, and 2FA is not on.
      gotrue.on('POST', '/factors/f9/challenge', body: {'id': 'c9'});
      gotrue.on(
        'POST',
        '/factors/f9/verify',
        status: 422,
        body: {'error_code': 'mfa_verification_failed', 'msg': 'Invalid'},
      );
      gotrue.on('GET', '/user', body: user(factors: [factor(id: 'f9', status: 'unverified')]));
      await expectLater(
        MfaStore.instance.confirmEnable('f9', '000000'),
        throwsA(isA<ApiError>()),
      );
      expect(MfaStore.instance.status, isNot(MfaStatus.enabled));

      // The right code: on, and the session is raised to aal2.
      gotrue.on(
        'POST',
        '/factors/f9/verify',
        body: tokenBody('aal2', user(factors: [factor(id: 'f9')])),
      );
      gotrue.on('GET', '/user', body: user(factors: [factor(id: 'f9')]));
      await MfaStore.instance.confirmEnable('f9', '123456');

      expect(MfaStore.instance.status, MfaStatus.enabled);
      final stored = await SessionStore.instance.read();
      expect(MfaRepository.aalOf(stored!.accessToken), 'aal2');
    });

    test('a wrong password generates nothing', () async {
      await signedIn(const []);
      gotrue.on(
        'POST',
        '/token',
        status: 400,
        body: {'msg': 'Invalid login credentials'},
      );
      await expectLater(
        MfaStore.instance.startEnable(password: 'wrong'),
        throwsA(
          isA<ApiError>().having((e) => e.message, 'm', 'That password is not correct.'),
        ),
      );
      expect(gotrue.calls.any((c) => c.path == '/factors'), isFalse);
    });

    test('turning off verifies a code first, then removes the factor on the server', () async {
      await signedIn([factor()], aal: 'aal2');
      gotrue.on('POST', '/token', body: tokenBody('aal1', user(factors: [factor()])));
      gotrue.on('POST', '/factors/f1/challenge', body: {'id': 'c1'});
      gotrue.on(
        'POST',
        '/factors/f1/verify',
        body: tokenBody('aal2', user(factors: [factor()])),
      );
      var deleted = false;
      gotrue.onCall('DELETE', '/factors/f1', (_) {
        deleted = true;
        return const FakeReply(status: 200, body: {'id': 'f1'});
      });
      gotrue.onCall(
        'GET',
        '/user',
        (_) => FakeReply(status: 200, body: user(factors: deleted ? const [] : [factor()])),
      );

      await MfaStore.instance.disable(password: 'pw', code: '123456');

      final paths = gotrue.calls.map((c) => '${c.method} ${c.path}').toList();
      expect(
        paths.indexOf('POST /factors/f1/verify'),
        lessThan(paths.indexOf('DELETE /factors/f1')),
        reason: 'the code is verified before the factor is removed',
      );
      expect(MfaStore.instance.status, MfaStatus.disabled);
    });

    test('a wrong code leaves 2FA on', () async {
      await signedIn([factor()], aal: 'aal2');
      gotrue.on('POST', '/token', body: tokenBody('aal1', user(factors: [factor()])));
      gotrue.on('POST', '/factors/f1/challenge', body: {'id': 'c1'});
      gotrue.on(
        'POST',
        '/factors/f1/verify',
        status: 422,
        body: {'error_code': 'mfa_verification_failed', 'msg': 'Invalid'},
      );

      await expectLater(
        MfaStore.instance.disable(password: 'pw', code: '000000'),
        throwsA(isA<ApiError>()),
      );
      expect(gotrue.calls.any((c) => c.method == 'DELETE'), isFalse);
    });
  });

  group('screens', () {
    testWidgets('the challenge screen shows a refused code and stays open', (
      tester,
    ) async {
      gotrue.on('POST', '/token', body: tokenBody('aal1', user(factors: [factor()])));
      gotrue.on('POST', '/factors/f1/challenge', body: {'id': 'c1'});
      gotrue.on(
        'POST',
        '/factors/f1/verify',
        status: 422,
        body: {'error_code': 'mfa_verification_failed', 'msg': 'Invalid'},
      );
      await tester.runAsync(() async {
        try {
          await AuthStore.instance.signIn(email: 'two@example.com', password: 'pw');
        } on MfaRequired {
          // Expected.
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const TwoFactorChallengeScreen(email: 'two@example.com'),
        ),
      );
      await tester.enterText(find.byType(TextField), '000000');
      await tester.pumpAndSettle();

      expect(find.text(MfaError.invalidCode), findsOneWidget);
      expect(find.byType(TwoFactorChallengeScreen), findsOneWidget);
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    testWidgets('the status chip names each state', (tester) async {
      Future<void> pump(MfaStatus s) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MfaStatusChip(status: s))),
      );
      await pump(MfaStatus.enabled);
      expect(find.text('Enabled'), findsOneWidget);
      await pump(MfaStatus.disabled);
      expect(find.text('Not enabled'), findsOneWidget);
      await pump(MfaStatus.setupIncomplete);
      expect(find.text('Setup incomplete'), findsOneWidget);
    });
  });
}

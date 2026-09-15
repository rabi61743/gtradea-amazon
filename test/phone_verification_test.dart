import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/profile/data/phone_repository.dart';
import 'package:gtradea_amazon/features/profile/data/phone_store.dart';
import 'package:gtradea_amazon/features/profile/data/profile_store.dart';
import 'package:gtradea_amazon/features/profile/presentation/phone_verification_screen.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

/// The flow, driven against a stubbed GoTrue and a stubbed gateway.
///
/// **The data here is invented; the paths and the rules are not.** Every stub
/// answers on the route the app really calls, in the shape GoTrue really
/// returns, so what these tests prove is that the screens read a real answer
/// correctly -- not that a verification can be faked. The one thing they are
/// most careful about is the opposite: that the success panel cannot be reached
/// unless the server said `phone_confirmed_at`.
late FakeApi api;
late FakeApi auth;

const _number = '9812345678';
const _e164 = '+9779812345678';

Map<String, dynamic> _profileJson({String? phone}) => {
  'id': 'user-1',
  'email': 'rabi@example.com',
  'first_name': 'Rabi',
  'last_name': 'Yadav',
  'phone': phone,
  'avatar_url': null,
};

/// A GoTrue user, with or without the field that says the number was proved.
Map<String, dynamic> _user({String? phone, bool confirmed = false}) => {
  'id': 'user-1',
  'email': 'rabi@example.com',
  if (phone != null) 'phone': phone.replaceAll('+', ''),
  if (confirmed) 'phone_confirmed_at': '2026-09-14T10:00:00Z',
};

FakeApi _stubGoTrue() {
  SessionStore.instance.write(
    const AuthSession(accessToken: 'test-access', refreshToken: 'test-refresh'),
  );
  final fake = FakeApi();
  final repo = AuthRepository(
    sessions: SessionStore.instance,
    dio: fake.dio(baseUrl: 'https://test.local/auth/v1'),
  );
  AuthStore.instance.repositoryForTest = repo;
  PhoneRepository.instance.authRepositoryForTest = repo;
  return fake;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const PhoneVerificationScreen()),
  );
  await tester.pumpAndSettle();
}

/// Types a number and asks for a code.
Future<void> _sendCode(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, _number);
  await tester.tap(find.text('Send OTP'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    ProfileStore.instance.resetForTest();
    PhoneStore.instance.resetForTest();
    // The demo walks the screens without an SMS round-trip, and `kDebugMode`
    // is true in a test, so it is on by default. Every test in this file is
    // about what the *server* said -- its rate limit, its rejection, its
    // `phone_confirmed_at` -- and the demo answers before any of that is
    // asked for, which is why they were failing: no request was recorded and
    // the server's own words never reached the screen.
    PhoneRepository.demo = false;
    api = stubCatalog();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/profile', body: _profileJson());
    auth = _stubGoTrue();
    signInForTest();
  });

  tearDown(() async {
    // Back to the shipped default, so turning it off here cannot leak into
    // another suite.
    PhoneRepository.demo = true;
    ApiClient.overrideDio = null;
    await SessionStore.instance.clear();
    clearApiStub();
  });

  group('asking for a code', () {
    testWidgets('the first panel asks for a number, not a code', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Change Phone Number'), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);
      expect(find.textContaining('+977'), findsWidgets);
      expect(find.text('Verify'), findsNothing);
    });

    testWidgets('a short number is refused before the server is troubled', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField).first, '98');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid phone number.'), findsOneWidget);
      expect(auth.calls.where((c) => c.path == '/otp'), isEmpty);
    });

    testWidgets('sending one moves to the code panel', (tester) async {
      auth.on('POST', '/otp', body: const {});
      await _pump(tester);
      await _sendCode(tester);

      expect(find.text('Verify Phone Number'), findsOneWidget);
      expect(find.text('Enter the 6-digit code sent to'), findsOneWidget);
      // The number it was actually sent to, grouped the way it is dialled.
      expect(find.text('+977 9812345678'), findsOneWidget);
      expect(find.textContaining('Code expires in'), findsOneWidget);

      final sent = auth.calls.firstWhere((c) => c.path == '/otp');
      expect(sent.json['phone'], _e164);
    });

    testWidgets('the code is never in the app, only the request for it', (
      tester,
    ) async {
      // The property that makes this a verification rather than a screen that
      // agrees with itself: nothing in the answer carries a code.
      auth.on('POST', '/otp', body: const {});
      await _pump(tester);
      await _sendCode(tester);

      final sent = auth.calls.firstWhere((c) => c.path == '/otp');
      expect(sent.json.containsKey('token'), isFalse);
      expect(sent.json.containsKey('code'), isFalse);
    });
  });

  group('when the server refuses to send', () {
    testWidgets('a rate limit shows its own wait, not one we invented', (
      tester,
    ) async {
      // GoTrue's wording. The figure on screen is the server's.
      auth.on(
        'POST',
        '/otp',
        status: 429,
        body: const {
          'msg': 'For security purposes, you can only request this after 47 '
              'seconds.',
        },
      );
      await _pump(tester);
      await _sendCode(tester);

      expect(find.textContaining('47 seconds'), findsOneWidget);
      expect(find.textContaining('Resend OTP in'), findsOneWidget);
      expect(PhoneStore.instance.resendIn, 47);
    });

    testWidgets('an unconfigured SMS provider says so rather than blaming the '
        'number', (tester) async {
      auth.on(
        'POST',
        '/otp',
        status: 422,
        body: const {'msg': 'Unsupported phone provider'},
      );
      await _pump(tester);
      await _sendCode(tester);

      expect(find.textContaining('Unsupported phone provider'), findsOneWidget);
      // Still on the number panel: there is no code coming, so asking for one
      // would be a box that can never be filled.
      expect(find.text('Send OTP'), findsOneWidget);
      expect(find.text('Verify'), findsNothing);
    });

    testWidgets('a rejected number keeps the panel and says why', (
      tester,
    ) async {
      auth.on(
        'POST',
        '/otp',
        status: 400,
        body: const {'msg': 'Invalid phone number format'},
      );
      await _pump(tester);
      await _sendCode(tester);

      expect(
        find.textContaining('Invalid phone number format'),
        findsOneWidget,
      );
      expect(find.text('Send OTP'), findsOneWidget);
    });
  });

  group('typing the code', () {
    Future<void> reachCodePanel(WidgetTester tester) async {
      auth.on('POST', '/otp', body: const {});
      await _pump(tester);
      await _sendCode(tester);
    }

    testWidgets('Verify stays off until six digits are in', (tester) async {
      await reachCodePanel(tester);

      final before = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Verify'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(before.onPressed, isNull, reason: 'nothing typed yet');

      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.pumpAndSettle();

      final after = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Verify'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(after.onPressed, isNotNull);
    });

    testWidgets('a wrong code is refused by the server and said so', (
      tester,
    ) async {
      await reachCodePanel(tester);
      auth.on(
        'POST',
        '/verify',
        status: 400,
        body: const {'msg': 'Token has expired or is invalid'},
      );

      await tester.enterText(find.byType(TextField).first, '000000');
      // See above: the frame that enables Verify has to be pumped.
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Token has expired or is invalid'),
        findsOneWidget,
      );
      expect(find.text('Phone Number Updated!'), findsNothing);
      expect(
        api.calls.where((c) => c.method == 'PATCH'),
        isEmpty,
        reason: 'a refused code never reaches the profile',
      );
    });

    testWidgets('an answer without confirmation is NOT treated as success', (
      tester,
    ) async {
      // The dangerous case: the server answered 200 but never said the number
      // was confirmed. Showing "Verified" here would be the exact lie this
      // flow exists to prevent.
      await reachCodePanel(tester);
      auth.on('POST', '/verify', body: _user(phone: _e164));

      await tester.enterText(find.byType(TextField).first, '123456');
      // `enterText` ends in `idle()`, which flushes microtasks but paints no
      // frame -- so without this the tap lands on a Verify that has not yet
      // been told there are six digits, and nothing is sent. A real keyboard
      // produces the frame on its own.
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.text('Phone Number Updated!'), findsNothing);
      expect(find.textContaining('did not confirm'), findsOneWidget);
      expect(api.calls.where((c) => c.method == 'PATCH'), isEmpty);
    });

    testWidgets('Change number goes back to the number panel', (tester) async {
      await reachCodePanel(tester);

      await tester.tap(find.text('Change number'));
      await tester.pumpAndSettle();

      expect(find.text('Change Phone Number'), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);
    });
  });

  group('when the server confirms', () {
    Future<void> verify(WidgetTester tester) async {
      auth.on('POST', '/otp', body: const {});
      auth.on(
        'POST',
        '/verify',
        body: {
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'expires_in': 3600,
          'user': _user(phone: _e164, confirmed: true),
        },
      );
      api.on('PATCH', '/profile', body: _profileJson(phone: _e164));

      await _pump(tester);
      await _sendCode(tester);
      await tester.enterText(find.byType(TextField).first, '123456');
      // `enterText` ends in `idle()`, which flushes microtasks but paints no
      // frame -- so without this the tap lands on a Verify that has not yet
      // been told there are six digits, and nothing is sent. A real keyboard
      // produces the frame on its own.
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
    }

    testWidgets('the success panel shows the number and the tick', (
      tester,
    ) async {
      await verify(tester);

      expect(find.text('Phone Number Updated!'), findsOneWidget);
      expect(find.text('+977 9812345678'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Back to Profile'), findsOneWidget);
    });

    testWidgets('and only then is the number written to the profile', (
      tester,
    ) async {
      // Order matters: the row a courier reads is never told about a number
      // the server has not proved.
      await verify(tester);

      // Both of these throw if the call was never made, so reaching the lines
      // below is itself the proof that each happened.
      auth.calls.firstWhere((c) => c.path == '/verify');
      final patch = api.calls.lastWhere((c) => c.method == 'PATCH');
      expect(patch.path, '/profile');
      expect(patch.json['phone'], _e164);
      expect(
        api.calls.where((c) => c.method == 'PATCH'),
        hasLength(1),
        reason: 'the row is written once, not once per attempt',
      );

      // What this test is named for -- that the write happens only *after* the
      // server confirmed -- is not checked here, and cannot be: the gateway and
      // GoTrue are two FakeApi instances with a `calls` list each and no shared
      // clock, so there is nothing to order one against the other by. The
      // assertion that used to sit here looked like it covered that and did
      // not: `indexOf(verifyCall) >= 0 && calls.contains(patch)` reads back two
      // objects that had just been taken out of those same lists, so neither
      // half could ever be false.
      //
      // The ordering is held by PhoneRepository.confirmCode instead, which
      // cannot reach its PATCH until verifyPhoneOtp has returned and the
      // unconfirmed answer has been thrown out, and by the sibling test above:
      // a refused code leaves the PATCH list empty.
    });

    testWidgets('the verified flag comes from the server, not from arriving '
        'here', (tester) async {
      await verify(tester);

      final confirmed = PhoneStore.instance.confirmed;
      expect(confirmed, isNotNull);
      expect(confirmed!.verified, isTrue);
      expect(confirmed.e164, _e164);
    });
  });

  group('the numbers on the account', () {
    test('an unproved number on the profile is shown as unproved', () async {
      auth.on('GET', '/user', body: _user());
      api.on('GET', '/profile', body: _profileJson(phone: _e164));

      final numbers = await PhoneRepository.instance.list();

      expect(numbers, hasLength(1));
      expect(numbers.first.e164, _e164);
      expect(
        numbers.first.verified,
        isFalse,
        reason: 'nothing checked it, so it is not verified',
      );
      expect(numbers.first.primary, isTrue);
    });

    test('a confirmed number reads as verified', () async {
      auth.on('GET', '/user', body: _user(phone: _e164, confirmed: true));
      api.on('GET', '/profile', body: _profileJson(phone: _e164));

      final numbers = await PhoneRepository.instance.list();

      expect(numbers.first.verified, isTrue);
      expect(numbers.first.primary, isTrue);
    });

    test('an account with no number at all is empty, not broken', () async {
      auth.on('GET', '/user', body: _user());
      api.on('GET', '/profile', body: _profileJson());

      expect(await PhoneRepository.instance.list(), isEmpty);
    });
  });

  group('the clock', () {
    test('counts in mm:ss', () {
      expect(PhoneStore.clock(272), '04:32');
      expect(PhoneStore.clock(59), '00:59');
      expect(PhoneStore.clock(0), '00:00');
      expect(PhoneStore.clock(-5), '00:00', reason: 'never below zero');
    });
  });
}

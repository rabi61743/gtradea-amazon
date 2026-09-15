import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/address/presentation/address_list_screen.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/profile/data/email_verification_store.dart';
import 'package:gtradea_amazon/features/profile/data/profile.dart';
import 'package:gtradea_amazon/features/profile/data/profile_repository.dart';
import 'package:gtradea_amazon/features/profile/data/profile_store.dart';
import 'package:gtradea_amazon/features/profile/presentation/profile_settings_screen.dart';
import 'package:gtradea_amazon/features/security/data/mfa_repository.dart';
import 'package:gtradea_amazon/features/security/data/mfa_store.dart';
import 'package:gtradea_amazon/features/security/presentation/two_factor_screen.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// The profile row as the gateway returns it, in the server's own spelling.
Map<String, dynamic> profileJson({
  String first = 'Rabi',
  String last = 'Yadav',
  String? avatar,
}) => {
  'id': 'user-1',
  'email': 'rabi@example.com',
  'first_name': first,
  'last_name': last,
  'phone': '9800000000',
  'avatar_url': avatar,
  'marketing_opt_in': false,
};

/// A stand-in GoTrue on its own FakeApi, since auth does not share the
/// gateway's Dio -- the real one deliberately keeps a separate client.
///
/// Also parks a session in the store. `signInForTest` adopts an account
/// without one, which is right for the screens that only need "somebody is
/// signed in" -- but `PUT /user` reads the access token out of the session, so
/// a test of it needs the token to exist.
FakeApi stubGoTrue() {
  SessionStore.instance.write(
    const AuthSession(accessToken: 'test-access', refreshToken: 'test-refresh'),
  );

  final auth = FakeApi();
  AuthStore.instance.repositoryForTest = AuthRepository(
    sessions: SessionStore.instance,
    dio: auth.dio(baseUrl: 'https://test.local/auth/v1'),
  );
  ProfileStore.instance.authRepositoryForTest = AuthRepository(
    sessions: SessionStore.instance,
    dio: auth.dio(baseUrl: 'https://test.local/auth/v1'),
  );
  // The verification flow keeps its own handle on auth. Without this it would
  // fall back to the real repository and a test that turns the demo off would
  // reach the network instead of this fake.
  EmailVerificationStore.instance.authRepositoryForTest = AuthRepository(
    sessions: SessionStore.instance,
    dio: auth.dio(baseUrl: 'https://test.local/auth/v1'),
  );
  return auth;
}

Widget _wrap() =>
    MaterialApp(theme: AppTheme.light, home: const ProfileSettingsScreen());

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Without this the keystore call never answers in a test, and a save that
    // writes the session finishes a turn later than the pump that looks for it.
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
    api = stubCatalog();
    AuthStore.instance.resetForTest();
    ProfileStore.instance.resetForTest();
    MfaStore.instance.resetForTest();
    EmailVerificationStore.instance.resetForTest();
    api.on('GET', '/profile', body: profileJson());
  });

  group('the profile row', () {
    test('is read from the gateway, in the server\'s field names', () async {
      // first_name / last_name / avatar_url, not camelCase. Verified against
      // the storefront bundle: getting these wrong is a page of empty boxes
      // that looks like an account with no details rather than a decode bug.
      signInForTest();
      final profile = await ProfileRepository.instance.fetch();

      expect(profile.fullName, 'Rabi Yadav');
      expect(profile.email, 'rabi@example.com');
      expect(api.calls.last.path, '/profile');
    });

    test('a wrapped payload decodes as well as a bare one', () async {
      // The gateway wraps some answers and returns others bare. Both are read
      // rather than betting on which kind this endpoint is.
      final wrapped = Profile.fromJson({'profile': profileJson()});
      expect(wrapped?.fullName, 'Rabi Yadav');
    });

    test('a row with no id is refused rather than half-built', () {
      expect(Profile.fromJson(const {'first_name': 'Rabi'}), isNull);
    });
  });

  group('the name', () {
    test('is split on the LAST space, so a middle name survives', () {
      // "Rabi Kumar Yadav" has to reach the server as first "Rabi Kumar" and
      // last "Yadav". Splitting on the first space would silently drop the
      // middle name into the surname.
      final parts = Profile.splitName('Rabi Kumar Yadav');
      expect(parts.first, 'Rabi Kumar');
      expect(parts.last, 'Yadav');
    });

    test('a single word is a first name, not an error', () {
      // Mononyms are ordinary here. The server takes an empty last name.
      final parts = Profile.splitName('Kabita');
      expect(parts.first, 'Kabita');
      expect(parts.last, '');
    });

    test('is PATCHed, and only the fields being changed are sent', () async {
      // The bug this rules out: sending phone: '' or avatar_url: '' because
      // the caller happened not to be editing them wipes fields nobody touched.
      signInForTest();
      api.on(
        'PATCH',
        '/profile',
        body: profileJson(first: 'Rabi', last: 'K'),
      );

      await ProfileRepository.instance.update(firstName: 'Rabi', lastName: 'K');

      final sent = api.calls.lastWhere((c) => c.method == 'PATCH');
      expect(sent.path, '/profile');
      expect(sent.json['first_name'], 'Rabi');
      expect(sent.json['last_name'], 'K');
      expect(sent.json.containsKey('phone'), isFalse);
      expect(sent.json.containsKey('avatar_url'), isFalse);
    });

    testWidgets('an empty name is refused before anything is sent', (
      tester,
    ) async {
      signInForTest();
      await _pump(tester);

      // Each detail is edited in its own sheet now, opened by the row.
      await tester.tap(find.text('Full Name'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Full name'),
        '   ',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your name.'), findsOneWidget);
      expect(
        api.calls.where((c) => c.method == 'PATCH'),
        isEmpty,
        reason: 'nothing was sent',
      );
    });

    testWidgets('saving it reports success and keeps the server\'s answer', (
      tester,
    ) async {
      signInForTest();
      stubGoTrue().on('PUT', '/user', body: const {'id': 'user-1'});
      api.on(
        'PATCH',
        '/profile',
        body: profileJson(first: 'Kabita', last: 'Sharma'),
      );

      await _pump(tester);
      await tester.tap(find.text('Full Name'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Full name'),
        'Kabita Sharma',
      );
      await tester.tap(find.text('Save'));
      // Twice, and not by superstition. A successful save goes on to mirror the
      // name into GoTrue's user_metadata, and writing the session awaits a
      // platform channel -- which schedules no frame, so the first settle
      // returns while that reply is still outstanding. The failure path has no
      // such await, which is why only this test needs the second pump.
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(find.text('Name updated'), findsOneWidget);
      // The row the server returned, not a hopeful copy of what was typed.
      expect(ProfileStore.instance.profile?.fullName, 'Kabita Sharma');
    });

    testWidgets('the phone row opens verification, not a text box', (
      tester,
    ) async {
      // A number is the one detail here that has to be *proved* rather than
      // typed: it is what a courier rings, and an order carrying none is
      // refused outright by the server. Editing it in place would write
      // whatever was entered, including somebody else's number.
      signInForTest();
      stubGoTrue();
      api.on('PATCH', '/profile', body: profileJson());

      await _pump(tester);
      await tester.tap(find.text('Phone Number'));
      await tester.pumpAndSettle();

      expect(
        find.text('Change Phone Number'),
        findsOneWidget,
        reason: 'the row opens the verification flow',
      );
      expect(
        find.text('Send OTP'),
        findsOneWidget,
        reason: 'and asks the server for a code rather than saving a guess',
      );
      expect(
        api.calls.where((c) => c.method == 'PATCH'),
        isEmpty,
        reason: 'nothing reaches the profile until a code is confirmed',
      );
    });

    testWidgets('a rejected save leaves the old profile untouched', (
      tester,
    ) async {
      // "Keep existing user data unchanged if an update fails" -- asserted on
      // the store rather than on the screen, because the screen showing the old
      // value is a consequence of the store still holding it.
      signInForTest();
      api.on('PATCH', '/profile', status: 500, body: const {'error': 'Nope.'});

      await _pump(tester);
      expect(ProfileStore.instance.profile?.fullName, 'Rabi Yadav');

      await tester.tap(find.text('Full Name'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Full name'),
        'Someone',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Nope.'), findsOneWidget);
      expect(ProfileStore.instance.profile?.fullName, 'Rabi Yadav');
    });
  });

  group('the photo', () {
    test('goes to the media service first, and the profile second', () async {
      // Two requests, in this order. Patching the row before the picture is
      // stored would leave the profile pointing at an address holding nothing.
      signInForTest();
      final file = File(
        '${Directory.systemTemp.createTempSync('avatar').path}/me.jpg',
      )..writeAsBytesSync(List.filled(64, 7));
      // Best effort. Windows keeps the handle open until the multipart stream
      // is collected, and failing to tidy a temp file is not a test result.
      addTearDown(() {
        try {
          file.parent.deleteSync(recursive: true);
        } on FileSystemException {
          // Nothing to do; the OS reclaims it.
        }
      });

      api.on(
        'POST',
        '/media/upload',
        body: const {
          'key': 'avatars/me.jpg',
          'public_url': 'https://cdn.test/me.jpg',
        },
      );
      api.on(
        'PATCH',
        '/profile',
        body: profileJson(avatar: 'https://cdn.test/me.jpg'),
      );

      await ProfileStore.instance.savePhoto(file);

      final upload = api.calls.firstWhere((c) => c.path == '/media/upload');
      final patch = api.calls.lastWhere((c) => c.method == 'PATCH');
      expect(
        api.calls.indexOf(upload),
        lessThan(api.calls.indexOf(patch)),
        reason: 'the picture is stored before the row points at it',
      );
      expect(patch.json['avatar_url'], 'https://cdn.test/me.jpg');
      expect(
        ProfileStore.instance.avatarUrl,
        'https://cdn.test/me.jpg',
        reason: 'and the new photo is what every screen now draws',
      );
    });

    test('a picture over the limit never leaves the phone', () async {
      // The storefront checks 5 MB before uploading and so does this: a
      // rejection after a slow mobile upload is a minute of someone's life for
      // an answer that was knowable up front.
      signInForTest();
      final file = File(
        '${Directory.systemTemp.createTempSync('big').path}/big.jpg',
      )..writeAsBytesSync(List.filled(ProfileRepository.maxPhotoBytes + 1, 0));
      // Best effort. Windows keeps the handle open until the multipart stream
      // is collected, and failing to tidy a temp file is not a test result.
      addTearDown(() {
        try {
          file.parent.deleteSync(recursive: true);
        } on FileSystemException {
          // Nothing to do; the OS reclaims it.
        }
      });

      await expectLater(
        ProfileRepository.instance.uploadAvatar(file),
        throwsA(isA<ApiError>()),
      );
      expect(api.calls.where((c) => c.path == '/media/upload'), isEmpty);
    });

    test('a failed upload writes nothing to the profile', () async {
      signInForTest();
      final file = File(
        '${Directory.systemTemp.createTempSync('avatar').path}/me.jpg',
      )..writeAsBytesSync(List.filled(64, 7));
      // Best effort. Windows keeps the handle open until the multipart stream
      // is collected, and failing to tidy a temp file is not a test result.
      addTearDown(() {
        try {
          file.parent.deleteSync(recursive: true);
        } on FileSystemException {
          // Nothing to do; the OS reclaims it.
        }
      });

      api.on('POST', '/media/upload', status: 500, body: const {'error': 'no'});

      await expectLater(
        ProfileStore.instance.savePhoto(file),
        throwsA(isA<ApiError>()),
      );
      expect(api.calls.where((c) => c.method == 'PATCH'), isEmpty);
    });
  });

  group('the email', () {
    testWidgets('a malformed address is refused before anything is sent', (
      tester,
    ) async {
      signInForTest();
      final auth = stubGoTrue();
      // The demo walks the screens without a mail round-trip, and `kDebugMode`
      // is true in a test, so it is on by default. Left on, nothing would be
      // sent for a *good* address either and the last assertion would hold for
      // the wrong reason.
      EmailVerificationStore.demo = false;
      addTearDown(() => EmailVerificationStore.demo = true);
      await _pump(tester);

      // The row opens the verification flow now, not a sheet.
      await tester.tap(find.text('Email Address'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'youremail@example.com'),
        'rabi@nowhere',
      );
      await tester.tap(find.text('Send Verification Code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    test('the current password is checked before the address moves', () async {
      // Without this, a found unlocked phone is a stolen account: GoTrue's
      // PUT /user does not ask for the old password.
      signInForTest();
      final auth = stubGoTrue()
        ..on(
          'POST',
          '/token',
          status: 400,
          body: const {'msg': 'Bad password'},
        );

      await expectLater(
        ProfileStore.instance.changeEmail(
          newEmail: 'new@example.com',
          currentPassword: 'wrong',
        ),
        throwsA(isA<ApiError>()),
      );
      expect(
        auth.calls.where((c) => c.method == 'PUT'),
        isEmpty,
        reason: 'the address was never sent',
      );
    });

    test(
      'a pending confirmation is reported as pending, not as done',
      () async {
        // GoTrue leaves `email` alone and parks the new address in `new_email`
        // until the link is followed. Saying "email updated" there is a lie the
        // shopper only finds out about the next time they try to sign in.
        signInForTest();
        stubGoTrue()
          ..on(
            'POST',
            '/token',
            body: const {
              'access_token': 'a',
              'refresh_token': 'r',
              'expires_in': 3600,
            },
          )
          ..on(
            'PUT',
            '/user',
            body: const {
              'id': 'user-1',
              'email': 'rabi@example.com',
              'new_email': 'new@example.com',
            },
          );

        final result = await ProfileStore.instance.changeEmail(
          newEmail: 'new@example.com',
          currentPassword: 'right',
        );

        expect(result, EmailChange.confirmationSent);
      },
    );
  });

  group('the password', () {
    testWidgets('a mismatched confirmation is caught here, not by the server', (
      tester,
    ) async {
      signInForTest();
      final auth = stubGoTrue();
      await _pump(tester);

      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current password'),
        'oldpassword',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        'newpassword',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm new password'),
        'newpasswordX',
      );
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(find.text('The two new passwords do not match.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('a short password is refused with the length it needs', (
      tester,
    ) async {
      signInForTest();
      stubGoTrue();
      await _pump(tester);

      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current password'),
        'oldpassword',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        'short',
      );
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 8 characters'), findsOneWidget);
    });

    testWidgets('every password box is obscured', (tester) async {
      // The one assertion that has to be true of all three. A reveal toggle is
      // fine; a box that starts readable is a credential on screen.
      signInForTest();
      stubGoTrue();
      await _pump(tester);

      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();

      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .where((f) => f.decoration?.labelText?.contains('assword') ?? false);
      expect(fields, hasLength(3));
      expect(fields.every((f) => f.obscureText), isTrue);
    });

    test('goes to GoTrue, and never to the gateway', () async {
      // Passwords are GoTrue's business. A profile PATCH carrying one would be
      // a credential written to a table that has no reason to hold it.
      signInForTest();
      final auth = stubGoTrue()
        ..on(
          'POST',
          '/token',
          body: const {
            'access_token': 'a',
            'refresh_token': 'r',
            'expires_in': 3600,
          },
        )
        ..on('PUT', '/user', body: const {'id': 'user-1'});

      await ProfileStore.instance.changePassword(
        currentPassword: 'oldpassword',
        newPassword: 'newpassword',
      );

      expect(auth.calls.last.method, 'PUT');
      expect(auth.calls.last.path, '/user');
      expect(auth.calls.last.json['password'], 'newpassword');
      expect(
        api.calls.where((c) => c.method == 'PATCH'),
        isEmpty,
        reason: 'the gateway never sees a password',
      );
    });
  });

  group('while a save is in flight', () {
    test('a second submit is dropped rather than sent twice', () async {
      // Duplicate submission. The button is also disabled, but a disabled
      // button is a UI detail and this is the guarantee.
      signInForTest();
      api.on('PATCH', '/profile', body: profileJson());
      stubGoTrue().on('PUT', '/user', body: const {'id': 'user-1'});

      final first = ProfileStore.instance.saveName('One Name');
      final second = ProfileStore.instance.saveName('Other Name');
      await Future.wait([first, second]);

      expect(
        api.calls.where((c) => c.method == 'PATCH').length,
        1,
        reason: 'the second tap sent nothing',
      );
    });
  });

  group('signing out', () {
    test('drops the profile, so it cannot reach the next account', () async {
      signInForTest();
      ProfileStore.instance.seedForTest(
        Profile.fromJson(profileJson(avatar: 'https://cdn.test/me.jpg')),
      );
      expect(ProfileStore.instance.avatarUrl, isNotNull);

      await AuthStore.instance.signOut();

      expect(ProfileStore.instance.profile, isNull);
      expect(ProfileStore.instance.avatarUrl, isNull);
    });
  });

  group('the page matches the reference', () {
    testWidgets('every changeable row offers "Change"', (
      tester,
    ) async {
      signInForTest();
      await _pump(tester);

      // Full Name, Phone Number, Email Address, Location.
      expect(find.text('Change'), findsNWidgets(4));
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('left out on request: Member since, Verified, Preferences', (
      tester,
    ) async {
      signInForTest();
      await _pump(tester);

      expect(find.textContaining('Member since'), findsNothing);
      expect(find.text('Verified'), findsNothing);
      expect(find.textContaining('Profile Preferences'), findsNothing);
      expect(find.textContaining('Show my profile'), findsNothing);
    });

    testWidgets('the page is set in Nunito Sans', (tester) async {
      signInForTest();
      await _pump(tester);

      final title = tester.widget<Text>(find.text('Profile Settings'));
      expect(title.style?.fontFamily, 'NunitoSans');
    });
  });

  group('the location', () {
    testWidgets('states the default delivery address', (tester) async {
      // Read from the address book rather than typed here: two answers to
      // "where does a parcel go" is one too many.
      signInForTest();
      AddressStore.instance.add(
        label: AddressLabel.home,
        fullName: 'Rabi Yadav',
        phone: '9800000000',
        province: 'Bagmati',
        city: 'Kathmandu',
        area: 'Jhamsikhel',
        makeDefault: true,
      );
      await _pump(tester);

      expect(find.text('Kathmandu, Bagmati'), findsOneWidget);
      expect(find.textContaining('(Optional)'), findsOneWidget);
    });

    testWidgets('says "Not set" when there is none, and Change opens the book', (
      tester,
    ) async {
      signInForTest();
      await _pump(tester);

      expect(find.text('Not set'), findsOneWidget);

      // The label reads "Location (Optional)" as one line of text.
      await tester.tap(find.text('Not set'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressListScreen), findsOneWidget);
    });
  });

  group('two-factor authentication', () {
    /// GoTrue, answering the account's factors. The row must show whatever the
    /// server holds -- there is no local 2FA flag to read instead.
    FakeApi stubFactors(List<Map<String, dynamic>> factors) {
      final auth = stubGoTrue()
        ..on(
          'GET',
          '/user',
          body: {'id': 'user-1', 'email': 'rabi@example.com', 'factors': factors},
        );
      final dio = auth.dio(baseUrl: 'https://test.local/auth/v1');
      MfaStore.instance
        ..authRepositoryForTest = AuthRepository(
          sessions: SessionStore.instance,
          dio: dio,
        )
        ..mfaRepositoryForTest = MfaRepository(dio: dio);
      return auth;
    }

    testWidgets('the row states "Not enabled" when the server has no factor', (
      tester,
    ) async {
      signInForTest();
      stubFactors(const []);
      await _pump(tester);

      expect(find.text('Two-Factor Authentication (2FA)'), findsOneWidget);
      expect(find.text('Not enabled'), findsOneWidget);
    });

    testWidgets('the row states "Enabled" when the server has a verified factor', (
      tester,
    ) async {
      signInForTest();
      stubFactors([
        {'id': 'f1', 'factor_type': 'totp', 'status': 'verified'},
      ]);
      await _pump(tester);

      expect(find.text('Enabled'), findsOneWidget);
    });

    testWidgets('tapping it opens the two-factor settings', (tester) async {
      signInForTest();
      stubFactors(const []);
      await _pump(tester);

      await tester.tap(find.text('Two-Factor Authentication (2FA)'));
      await tester.pumpAndSettle();
      expect(find.byType(TwoFactorScreen), findsOneWidget);
    });
  });

  group('page width', () {
    /// The section column every card stretches to -- the real width
    /// constraint, measured as rendered rather than read from a constant.
    Future<Rect> columnAt(WidgetTester tester, Size logical) async {
      signInForTest();
      tester.view.physicalSize = logical * 2;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      return tester.getRect(
        find
            .ancestor(
              of: find.text('Personal Information'),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
    }

    testWidgets('a phone uses about 97% of the width', (tester) async {
      final rect = await columnAt(tester, const Size(406, 900));
      expect(rect.width, closeTo(406 * 0.97, 2));
      expect(rect.left, closeTo(406 * 0.015, 1));
    });

    testWidgets('a tablet gets a centred 680 column, not 97%', (tester) async {
      final rect = await columnAt(tester, const Size(800, 1200));
      expect(rect.width, 680);
      expect(rect.left, closeTo((800 - 680) / 2, 1));
    });

    testWidgets('a desktop gets a centred 720 column', (tester) async {
      final rect = await columnAt(tester, const Size(1400, 1000));
      expect(rect.width, 720);
      expect(rect.left, closeTo((1400 - 720) / 2, 1));
    });
  });

  group('on a phone', () {
    testWidgets('360 dp wide, nothing overflows', (tester) async {
      signInForTest(name: 'Prabhakar Adhikari');
      api.on(
        'GET',
        '/profile',
        body: profileJson(first: 'Prabhakar', last: 'Adhikari'),
      );
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Personal Information'), findsOneWidget);
    });
  });

  tearDown(() async {
    ApiClient.overrideDio = null;
    await SessionStore.instance.clear();
  });
}

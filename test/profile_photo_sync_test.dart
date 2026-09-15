import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/profile/data/profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// The photograph a Google sign-in brings with it, before the shopper ever
/// picks one of their own.
const _google = 'https://lh3.googleusercontent.com/old-google-picture';
const _uploaded = 'https://cdn.example.com/avatars/new-photo.jpg';

Map<String, dynamic> _user({Map<String, dynamic>? meta}) => {
  'id': 'user-1',
  'email': 'rabi@example.com',
  'app_metadata': {'provider': 'google'},
  'user_metadata': meta ?? {'picture': _google},
};

Map<String, dynamic> _profile({String? avatar}) => {
  'id': 'user-1',
  'email': 'rabi@example.com',
  'first_name': 'Rabi',
  'last_name': 'Yadav',
  'phone': '9800000000',
  'avatar_url': avatar,
  'marketing_opt_in': false,
};

late FakeApi api;
late FakeApi goTrue;

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The avatar the list of accounts on this device would draw for user-1.
Future<String?> _listedPhoto() async {
  await AuthStore.instance.refreshSavedAccounts();
  return AuthStore.instance.savedAccounts
      .firstWhere((saved) => saved.id == 'user-1')
      .account
      .avatarUrl;
}

Future<File> _photoFile() async {
  final dir = await Directory.systemTemp.createTemp('avatar_test');
  addTearDown(() => dir.delete(recursive: true));
  return File('${dir.path}/me.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    ProfileStore.instance.resetForTest();

    api = stubCatalog();
    api.on('GET', '/profile', body: _profile());
    api.on('POST', '/media/upload', body: const {'public_url': _uploaded});
    api.on('PATCH', '/profile', body: _profile(avatar: _uploaded));

    goTrue = FakeApi();
    final repo = AuthRepository(
      sessions: SessionStore.instance,
      dio: goTrue.dio(baseUrl: 'https://test.local/auth/v1'),
    );
    AuthStore.instance.repositoryForTest = repo;
    ProfileStore.instance.authRepositoryForTest = repo;
    // GoTrue merges `data` into user_metadata and answers with the user.
    goTrue.onCall('PUT', '/user', (call) {
      final data = (call.json['data'] as Map?)?.cast<String, dynamic>() ?? {};
      return reply(_user(meta: {'picture': _google, ...data}));
    });

    // Signed in the way a Google account arrives: with Google's picture.
    await SessionStore.instance.write(
      AuthSession(
        accessToken: 'user-1-access',
        refreshToken: 'user-1-refresh',
        expiresAt: 9999999999,
        user: _user(),
      ),
    );
    await AuthStore.instance.load();
    await _settle();
  });

  tearDown(clearApiStub);

  test('before: the list shows the sign-in picture', () async {
    expect(await _listedPhoto(), _google);
  });

  test('a saved photo reaches the sign-in record and the account list', () async {
    await ProfileStore.instance.savePhoto(await _photoFile());
    await _settle();

    final put = goTrue.calls.singleWhere((c) => c.method == 'PUT');
    expect(put.path, '/user');
    expect(
      (put.json['data'] as Map)['avatar_url'],
      _uploaded,
      reason: 'the photo is written where every copy of the account reads it',
    );
    expect(AuthStore.instance.account?.avatarUrl, _uploaded);
    expect(await _listedPhoto(), _uploaded);
    // And the header's own source agrees.
    expect(ProfileStore.instance.avatarUrl, _uploaded);
  });

  test('if the sign-in server cannot be told, this device still is', () async {
    goTrue.on('PUT', '/user', status: 503, body: const {'msg': 'down'});

    await ProfileStore.instance.savePhoto(await _photoFile());
    await _settle();

    expect(await _listedPhoto(), _uploaded);
  });

  test('a photo changed somewhere else arrives with the profile', () async {
    // Changed on the website, or before this fix: the profile row has it,
    // the sign-in copy does not.
    api.on('GET', '/profile', body: _profile(avatar: _uploaded));

    await ProfileStore.instance.load(force: true);
    await _settle();

    expect(await _listedPhoto(), _uploaded);
    expect(
      goTrue.calls.where((c) => c.method == 'PUT'),
      isEmpty,
      reason: 'reading a profile changes nothing on the server',
    );
  });

  test('a switch during the upload does not give the photo to the next account', () async {
    api.onCall(
      'POST',
      '/media/upload',
      (_) => FakeReply(
        status: 200,
        body: const {'public_url': _uploaded},
        delay: const Duration(milliseconds: 80),
      ),
    );

    final saving = ProfileStore.instance.savePhoto(await _photoFile());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // Another account becomes active while the photo is still uploading.
    AuthStore.instance.adoptForTest(
      const Account(id: 'user-2', email: 'someone.else@example.com'),
    );
    await saving;
    await _settle();

    expect(
      goTrue.calls.where((c) => c.method == 'PUT'),
      isEmpty,
      reason: "user-1's photo must not be written into user-2's sign-in",
    );
    expect(AuthStore.instance.account?.avatarUrl, isNull);
  });
}

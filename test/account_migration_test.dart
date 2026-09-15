import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/account/data/recently_viewed_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/notifications/data/notification_store.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';

/// What an app updated from the one-account build finds on disk: history and
/// alert choices under the device-wide keys, and a signed-in session that is
/// only known a moment after the first screens have already read them.
const _seen = SavedProduct(id: 'p1', title: 'Seen before the update', price: 10);

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    RecentlyViewedStore.instance.resetForTest();
    NotificationSettings.instance.resetForTest();
    ensureApiStub();
    RecentlyViewedStore.instance.bindToAuth();
    NotificationSettings.instance.bindToAuth();
  });

  tearDown(clearApiStub);

  test('history read before sign-in was known becomes that account\'s', () async {
    SharedPreferences.setMockInitialValues({
      'gtradea_recently_viewed': jsonEncode([_seen.toJson()]),
    });

    // The first screen reads it while the session is still being restored.
    await RecentlyViewedStore.instance.load();
    expect(RecentlyViewedStore.instance.items.map((p) => p.id), ['p1']);

    // Then the restored account arrives.
    signInForTest(id: 'user-1');
    await _settle();

    expect(
      RecentlyViewedStore.instance.items.map((p) => p.id),
      ['p1'],
      reason: 'the history is still on screen, now as the account\'s',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey(RecentlyViewedStore.storageKeyFor('user-1')),
      isTrue,
    );
    expect(
      prefs.containsKey('gtradea_recently_viewed'),
      isFalse,
      reason: 'moved once, so no other account can inherit it',
    );
  });

  test('an account with its own history is not given the old one', () async {
    SharedPreferences.setMockInitialValues({
      'gtradea_recently_viewed': jsonEncode([_seen.toJson()]),
      RecentlyViewedStore.storageKeyFor('user-2'): jsonEncode([
        const SavedProduct(id: 'p2', title: 'Its own', price: 20).toJson(),
      ]),
    });
    await RecentlyViewedStore.instance.load();

    signInForTest(id: 'user-2');
    await _settle();

    expect(RecentlyViewedStore.instance.items.map((p) => p.id), ['p2']);
  });

  test('alert choices made before the update carry over the same way', () async {
    final muted = NotificationGroup.values.last;
    SharedPreferences.setMockInitialValues({
      'gtradea_notification_settings': [muted.name],
    });
    await NotificationSettings.instance.load();
    expect(NotificationSettings.instance.isEnabled(muted), isFalse);

    signInForTest(id: 'user-1');
    await _settle();

    expect(
      NotificationSettings.instance.isEnabled(muted),
      isFalse,
      reason: 'a mute set before the update is still a mute',
    );
  });
}

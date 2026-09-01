import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/notifications/data/device_notifications.dart';
import 'package:gtradea_amazon/features/notifications/data/notification_sound.dart';
import 'package:gtradea_amazon/features/notifications/data/notification_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

Map<String, dynamic> _row({
  String id = 'n-1',
  bool read = false,
  String title = 'Your quote is ready',
}) => {
  'id': id,
  'type': 'quote_ready',
  'title': title,
  'message': 'The seller priced your request.',
  'is_read': read,
  'created_at': '2026-08-30T09:00:00Z',
};

void main() {
  late FakeApi api;

  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  setUp(() async {
    // The player is a singleton, so its quiet window would otherwise carry
    // from one test into the next and silence it.
    await NotificationSound.instance.resetForTest();
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    NotificationStore.instance.resetForTest();
    // The counter stands in for the speaker, which a test does not have.
    NotificationSound.enabled = true;
    NotificationSound.plays = 0;
    // The chime is what sounds when the device will not post a notification.
    // With device notifications available the platform's own tone plays
    // instead -- see the "one sound per event" test below.
    DeviceNotifications.enabled = false;
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/notifications', body: const []);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    NotificationStore.instance.resetForTest();
    NotificationSound.enabled = false;
    clearApiStub();
  });

  group('when the chime sounds', () {
    test('never on the first load, however much is waiting', () async {
      // Opening the app is not news. A chime here is exactly the "plays on
      // page load" that the requirement rules out.
      signIn();
      api.on(
        'GET',
        '/notifications',
        body: [
          _row(id: 'a'),
          _row(id: 'b'),
        ],
      );

      await NotificationStore.instance.load();

      expect(NotificationSound.plays, 0);
      expect(NotificationStore.instance.unreadCount, 2);
    });

    test('once when something genuinely new arrives', () async {
      signIn();
      await NotificationStore.instance.load();
      expect(NotificationSound.plays, 0);

      api.on('GET', '/notifications', body: [_row(id: 'a')]);
      await NotificationStore.instance.load();

      expect(NotificationSound.plays, 1);
    });

    test('not again for a notification already announced', () async {
      signIn();
      await NotificationStore.instance.load();
      api.on('GET', '/notifications', body: [_row(id: 'a')]);
      await NotificationStore.instance.load();
      expect(NotificationSound.plays, 1);

      // The same one, still unread, on the next refresh.
      await NotificationStore.instance.load();
      await NotificationStore.instance.load();

      expect(NotificationSound.plays, 1, reason: 'it is not new any more');
    });

    test('once for a batch, not once per notification', () async {
      signIn();
      await NotificationStore.instance.load();

      api.on(
        'GET',
        '/notifications',
        body: [
          _row(id: 'a'),
          _row(id: 'b'),
          _row(id: 'c'),
          _row(id: 'd'),
        ],
      );
      await NotificationStore.instance.load();

      expect(NotificationSound.plays, 1);
    });

    test('not for one that arrives already read', () async {
      // Read somewhere else. It is new to this device, but it is not news.
      signIn();
      await NotificationStore.instance.load();

      api.on('GET', '/notifications', body: [_row(id: 'a', read: true)]);
      await NotificationStore.instance.load();

      expect(NotificationSound.plays, 0);
    });

    test('a failed refresh is silent', () async {
      signIn();
      await NotificationStore.instance.load();

      api.on('GET', '/notifications', status: 500, body: const {});
      await NotificationStore.instance.load();

      expect(NotificationSound.plays, 0);
    });

    test('the next account starts silent', () async {
      // Or signing in as somebody else chimes for their whole history.
      signIn();
      api.on('GET', '/notifications', body: [_row(id: 'a')]);
      await NotificationStore.instance.load();
      expect(NotificationSound.plays, 0, reason: 'first sync of this account');

      // A different account: the store is rebuilt from scratch for them.
      NotificationStore.instance.resetForTest();
      await NotificationStore.instance.load();

      expect(NotificationSound.plays, 0);
    });
  });

  group('one sound per event', () {
    test('the chime is silent when the device posts one instead', () async {
      // A posted device notification carries the platform's own tone -- the
      // one the shopper chose, at the notification volume, silenced by Do Not
      // Disturb. Chiming on top of it is two sounds for one event.
      DeviceNotifications.enabled = true;
      DeviceNotifications.instance.resetForTest();
      // Stands in for a device that posted it.
      DeviceNotifications.pretendPosted = true;
      addTearDown(() => DeviceNotifications.pretendPosted = false);
      signIn();
      await NotificationStore.instance.load();

      api.on('GET', '/notifications', body: [_row(id: 'a')]);
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, ['a'], reason: 'the device got it');
      expect(NotificationSound.plays, 0, reason: 'so the chime stayed quiet');
    });

    test('the chime covers for a device that will not post', () async {
      // Permission refused, no notification service, or the post failed. The
      // shopper still hears that something arrived.
      DeviceNotifications.enabled = false;
      DeviceNotifications.instance.resetForTest();
      signIn();
      await NotificationStore.instance.load();

      api.on('GET', '/notifications', body: [_row(id: 'a')]);
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, isEmpty);
      expect(NotificationSound.plays, 1);
    });
  });

  group('the player itself', () {
    test('a burst within the quiet window is one sound', () async {
      NotificationSound.plays = 0;
      await NotificationSound.instance.play();
      await NotificationSound.instance.play();
      await NotificationSound.instance.play();

      expect(
        NotificationSound.plays,
        1,
        reason: 'three arrivals a moment apart are one chime',
      );
      await NotificationSound.instance.resetForTest();
    });

    test('switched off, it does nothing at all', () async {
      NotificationSound.enabled = false;
      NotificationSound.plays = 0;

      await NotificationSound.instance.play();

      expect(NotificationSound.plays, 0);
    });
  });
}

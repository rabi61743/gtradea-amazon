import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
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
  String type = 'quote_ready',
  String title = 'New Quote Received',
}) => {
  'id': id,
  'type': type,
  'title': title,
  'message': 'You received a new quote for your product.',
  'is_read': read,
  'created_at': '2026-08-30T09:00:00Z',
  'data': {'request_id': 'req-9'},
};

void main() {
  late FakeApi api;

  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  setUp(() async {
    await NotificationSound.instance.resetForTest();
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    NotificationStore.instance.resetForTest();
    DeviceNotifications.instance.resetForTest();
    // The recorded list stands in for the notification shade, which a test
    // does not have.
    DeviceNotifications.enabled = true;
    NotificationSound.enabled = false;
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/notifications', body: const []);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    NotificationStore.instance.resetForTest();
    DeviceNotifications.instance.resetForTest();
    DeviceNotifications.enabled = false;
    clearApiStub();
  });

  group('what reaches the device', () {
    test('nothing on the first sync, however much is waiting', () async {
      // Opening the app must not fill the shade with everything the account
      // already had.
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

      expect(DeviceNotifications.posted, isEmpty);
    });

    test('a genuinely new one is posted', () async {
      signIn();
      await NotificationStore.instance.load();

      api.on('GET', '/notifications', body: [_row(id: 'a')]);
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, ['a']);
    });

    test('the same event is never posted twice', () async {
      signIn();
      await NotificationStore.instance.load();
      api.on('GET', '/notifications', body: [_row(id: 'a')]);
      await NotificationStore.instance.load();
      expect(DeviceNotifications.posted, ['a']);

      // Still unread, still on the server, on two further refreshes.
      await NotificationStore.instance.load();
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, ['a'], reason: 'no duplicate');
    });

    test('one per arrival, so a batch is not collapsed into a line', () async {
      signIn();
      await NotificationStore.instance.load();

      api.on(
        'GET',
        '/notifications',
        body: [
          _row(id: 'a'),
          _row(id: 'b'),
          _row(id: 'c'),
        ],
      );
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, ['a', 'b', 'c']);
    });

    test('a long absence does not push forty at once', () async {
      signIn();
      await NotificationStore.instance.load();

      api.on(
        'GET',
        '/notifications',
        body: [for (var i = 0; i < 20; i++) _row(id: 'n$i')],
      );
      await NotificationStore.instance.load();

      expect(
        DeviceNotifications.posted.length,
        lessThanOrEqualTo(5),
        reason: 'the shade is not a dumping ground',
      );
    });

    test('one that arrives already read is not posted', () async {
      signIn();
      await NotificationStore.instance.load();

      api.on('GET', '/notifications', body: [_row(id: 'a', read: true)]);
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, isEmpty);
    });

    test('a support reply reaches the device too', () async {
      signIn();
      await NotificationStore.instance.load();

      api.on(
        'GET',
        '/notifications',
        body: [
          _row(
            id: 's',
            type: 'support_ticket_reply',
            title: 'Support Response',
          ),
        ],
      );
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, ['s']);
    });

    test('a failed refresh posts nothing', () async {
      signIn();
      await NotificationStore.instance.load();

      api.on('GET', '/notifications', status: 500, body: const {});
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, isEmpty);
    });

    test('switched off, nothing is posted at all', () async {
      DeviceNotifications.enabled = false;
      signIn();
      await NotificationStore.instance.load();
      api.on('GET', '/notifications', body: [_row(id: 'a')]);
      await NotificationStore.instance.load();

      expect(DeviceNotifications.posted, isEmpty);
    });
  });

  group('how a notification is dressed', () {
    // There is no notification service on the test binding, so the branding
    // is pinned by reading the details the plugin is handed rather than by
    // looking at a shade that does not exist.

    test('carries the shop mark rather than the launcher icon', () {
      // '@mipmap/ic_launcher' was the old value, and on this project that file
      // is still the stock Flutter logo `flutter create` writes. A small icon
      // is drawn as an alpha mask, so it arrived as a white blob of somebody
      // else's shape.
      expect(DeviceNotifications.androidDetails.icon, 'ic_notification');
      expect(
        DeviceNotifications.notificationIcon,
        isNot(contains('launcher')),
        reason: 'the launcher icon is not a notification icon',
      );
    });

    test('is tinted Trust Blue rather than a colour the device picked', () {
      // Left unset, Android chooses its own accent, which varies by
      // manufacturer, theme and version -- the "random colour".
      expect(DeviceNotifications.androidDetails.color, AppColors.trustBlue);
    });

    test('takes that blue from the palette, not from a second copy of it', () {
      // The point of reading AppColors here: a brand change moves one constant
      // and this follows, rather than drifting into a hex of its own.
      expect(DeviceNotifications.notificationAccent, AppColors.trustBlue);
      expect(AppColors.trustBlue, const Color(0xFF267488));
    });

    test('does not colorise the whole row', () {
      // Colorising is for media and call notifications. The accent belongs on
      // the icon and the app name, which is what the rest of the app looks
      // like.
      expect(DeviceNotifications.androidDetails.colorized, isFalse);
    });

    test('and keeps the delivery settings it already had', () {
      // The branding change must not quietly alter how notifications behave.
      // High importance is what lets the device wake the screen and show a
      // heads-up, according to that device's own settings.
      expect(DeviceNotifications.androidDetails.importance, Importance.high);
      expect(DeviceNotifications.androidDetails.priority, Priority.high);
    });
  });

  group('on the lock screen', () {
    test('it appears, but leaves the preview to the phone owner', () {
      // `public` forces the full title and body onto the lock screen even for
      // someone who has turned sensitive previews off. `private` still shows
      // the notification and lets the device redact the content when that is
      // what its owner asked for.
      expect(
        DeviceNotifications.androidDetails.visibility,
        NotificationVisibility.private,
      );
      expect(
        DeviceNotifications.androidDetails.visibility,
        isNot(NotificationVisibility.public),
        reason: 'the app does not overrule the device privacy setting',
      );
      expect(
        DeviceNotifications.androidDetails.visibility,
        isNot(NotificationVisibility.secret),
        reason: 'nor hide the notification from the lock screen entirely',
      );
    });

    test('and does not claim the screen the way an alarm would', () {
      // A full-screen intent takes over a locked device. It is for alarms and
      // incoming calls, needs a special permission from Android 14, and using
      // it for a shop notification would be exactly the kind of lock-screen
      // bypass that must not be attempted.
      expect(DeviceNotifications.androidDetails.fullScreenIntent, isFalse);
    });
  });

  group('a tap that arrives before anything is listening', () {
    test('is held, and handed over once', () {
      // A notification that launched the app from cold: the widget tree is not
      // up yet, and dropping the tap would land the shopper on the home page
      // with no idea why.
      final held = DeviceNotifications.instance;
      expect(held.takePendingTap(), isNull);
    });
  });
}

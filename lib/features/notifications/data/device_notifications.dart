import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/colors.dart';
import 'notification_store.dart';

/// Where a tapped device notification wants to go.
///
/// Carried through the payload as the category and the id it points at, which
/// is the same pair the in-app list already routes on -- so a tap from the
/// lock screen and a tap in the list end up in exactly the same place.
class NotificationTap {
  const NotificationTap({required this.category, this.targetId, this.orderId});

  final NotificationCategory category;
  final String? targetId;
  final String? orderId;
}

/// Whether the device will let this app post notifications.
enum NotificationPermission {
  /// Allowed, and notifications will appear.
  granted,

  /// Refused. The shopper has to turn it on in the system settings; asking
  /// again from here does nothing on Android 13+ after the second refusal.
  denied,

  /// Not asked yet.
  unknown,
}

/// Posts the shop's notifications to the device itself.
///
/// This is what puts them in the notification centre and on the lock screen,
/// rather than only inside the app.
///
/// **What this is not.** It is not background push. The shop's push endpoint
/// (`/notifications/push-subscriptions`) is Web Push -- an `endpoint` from a
/// browser's service worker -- and there is no device-token route, no Firebase
/// project and no sender credentials in this repository. Delivering to a
/// *closed* app would need all of those, and inventing them is not something
/// this can do. So these are posted by the app itself the moment the existing
/// realtime channel says something arrived, which covers the app being open or
/// backgrounded with its socket alive.
class DeviceNotifications {
  DeviceNotifications._();

  static final DeviceNotifications instance = DeviceNotifications._();

  /// Off in tests: there is no notification service on the test binding, and
  /// initialising one would leave a pending platform call.
  @visibleForTesting
  static bool enabled = true;

  /// What has been posted, so a test can assert without a device.
  @visibleForTesting
  static final List<String> posted = [];

  /// What [show] reports when there is no notification service to post to.
  ///
  /// False everywhere but a test, which is the truthful answer on a device
  /// that cannot post: the caller then falls back to the in-app chime. A test
  /// sets it true to stand in for a device that posted successfully, so both
  /// halves of the one-sound-per-event rule can be exercised.
  @visibleForTesting
  static bool pretendPosted = false;

  /// Set by the app so a tap can be routed once the widget tree is up.
  void Function(NotificationTap tap)? onTap;

  static const _channelId = 'gtradea_updates';
  static const _askedKey = 'gtradea_notification_permission_asked';

  /// The shop's own mark, as a drawable Android can use for a small icon.
  ///
  /// Not the launcher icon, which is what this used to point at. A small icon
  /// is drawn as an alpha mask, so a full-colour launcher PNG arrives as a
  /// white blob -- and the launcher icon here was still the stock Flutter logo
  /// that `flutter create` writes, so the blob was not even this shop's shape.
  static const notificationIcon = 'ic_notification';

  /// What the system tints that mask with, and the accent beside the title.
  ///
  /// Read from the palette rather than written down again: left unset, Android
  /// picks an accent of its own, which differs by manufacturer, theme and
  /// version -- the "random colour". This is the same Trust Blue the header
  /// band and the rest of the app already use.
  static const notificationAccent = AppColors.trustBlue;

  /// How every notification this app posts is dressed.
  ///
  /// Exposed so a test can assert the branding without a device: there is no
  /// notification service on the test binding, so the only way to pin the icon
  /// and the colour is to read the details the plugin is handed.
  @visibleForTesting
  static const androidDetails = AndroidNotificationDetails(
    _channelId,
    'Order and account updates',
    channelDescription:
        'Quotes, support replies and updates about your orders.',
    importance: Importance.high,
    priority: Priority.high,
    icon: notificationIcon,
    color: notificationAccent,
    // The accent tints the icon and the app name; it does not flood the
    // notification's background. Colorising the whole row is for media and
    // call notifications, and would not match anything else in this app.
    colorized: false,
    // Shown on the lock screen, and redacted there if the shopper asked for
    // that.
    //
    // This was `public`, on the reasoning that the shop's own words carry
    // nothing a passer-by should not read. That reasoning is the app deciding
    // on the shopper's behalf: `public` *overrides* the device setting for
    // hiding sensitive content, so someone who had chosen to keep previews off
    // their lock screen got a quote total on it anyway.
    //
    // `private` still puts the notification on the lock screen. It only gives
    // the choice about the content back to the person whose phone it is: they
    // see it in full when their settings allow previews, and the redacted form
    // when they do not.
    visibility: NotificationVisibility.private,
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _readying;

  /// A tap that arrived before anything was listening -- which is what happens
  /// when the notification launched the app from cold.
  NotificationTap? _pending;

  Future<void> _ensureReady() {
    if (_ready) return Future<void>.value();
    return _readying ??= () async {
      try {
        await _plugin.initialize(
          const InitializationSettings(
            // The shop's mark, not the launcher icon. See [notificationIcon]:
            // the launcher icon was still the stock Flutter logo, and a small
            // icon is an alpha mask, so it arrived as a white blob.
            android: AndroidInitializationSettings(
              '@drawable/$notificationIcon',
            ),
            iOS: DarwinInitializationSettings(
              // Asked for separately, at a moment that makes sense, rather
              // than the first time a notification happens to be posted.
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
          onDidReceiveNotificationResponse: _onResponse,
        );
        _ready = true;
      } catch (_) {
        // No notification service on this device. The app goes on showing
        // them in its own list, which is the correct failure.
      } finally {
        _readying = null;
      }
    }();
  }

  void _onResponse(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final tap = NotificationTap(
        category: NotificationCategory.values.firstWhere(
          (c) => c.name == decoded['category'],
          orElse: () => NotificationCategory.account,
        ),
        targetId: decoded['targetId'] as String?,
        orderId: decoded['orderId'] as String?,
      );
      final handler = onTap;
      if (handler == null) {
        // Launched from cold by the tap: hold it until something is listening.
        _pending = tap;
        return;
      }
      handler(tap);
    } catch (_) {
      // A payload this app cannot read is not worth crashing over.
    }
  }

  /// The tap that started the app, if one did. Returned once.
  NotificationTap? takePendingTap() {
    final tap = _pending;
    _pending = null;
    return tap;
  }

  /// What the device currently allows.
  Future<NotificationPermission> permission() async {
    if (!enabled) return NotificationPermission.denied;
    await _ensureReady();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final granted = await android.areNotificationsEnabled();
        if (granted == true) return NotificationPermission.granted;
        return (await _hasAsked())
            ? NotificationPermission.denied
            : NotificationPermission.unknown;
      }
    } catch (_) {
      // Fall through to unknown rather than claiming either way.
    }
    return NotificationPermission.unknown;
  }

  /// Asks, once.
  ///
  /// Android remembers a refusal and stops showing the dialog, so asking again
  /// and again would be both useless and irritating. This records that the
  /// question has been put, and the caller uses [permission] afterwards to say
  /// something useful about the answer.
  Future<NotificationPermission> request() async {
    if (!enabled) return NotificationPermission.denied;
    await _ensureReady();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      await _markAsked();
      if (granted == true) return NotificationPermission.granted;
      return NotificationPermission.denied;
    } catch (_) {
      return NotificationPermission.unknown;
    }
  }

  Future<bool> _hasAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_askedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_askedKey, true);
    } catch (_) {
      // Worst case the question is put once more.
    }
  }

  /// Posts one notification to the device.
  ///
  /// The id is the shop's own, used as the device notification id too, so the
  /// same event posted twice replaces its own notification instead of stacking
  /// a duplicate beside it.
  ///
  /// Returns whether it was actually posted. The caller needs to know, because
  /// a posted notification carries the platform's own sound and an in-app
  /// chime on top of it would be two sounds for one event.
  Future<bool> show(AppNotification notification) async {
    if (!enabled) return false;
    posted.add(notification.id);

    try {
      await _ensureReady();
      if (!_ready) return pretendPosted;

      await _plugin.show(
        notification.id.hashCode,
        notification.title,
        notification.body.isEmpty ? null : notification.body,
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode({
          'category': notification.category.name,
          'targetId': notification.targetId,
          'orderId': notification.orderId,
        }),
      );
      return true;
    } catch (_) {
      // See the class doc: a device that will not post one must not cost the
      // shopper the notification itself.
      return false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    posted.clear();
    _pending = null;
    onTap = null;
  }
}

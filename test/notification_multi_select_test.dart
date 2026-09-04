import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/notifications/data/notification_store.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notifications_screen.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

/// Three notifications the server owns, so deleting them is a real request.
List<Map<String, dynamic>> get _rows => [
  for (var i = 1; i <= 3; i++)
    {
      'id': 'n-$i',
      'title': 'Notice $i',
      'body': 'Something happened, number $i.',
      'category': 'order_placed',
      'created_at': '2026-09-03T09:0$i:00Z',
      'read': false,
    },
];

void main() {
  late FakeApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NotificationStore.instance.resetForTest();
    NotificationSettings.instance.resetForTest();
    // The server only hands notifications to a signed-in account, and
    // signInForTest installs a stub of its own -- so the FakeApi goes on after
    // it, not before.
    signInForTest();
    api = FakeApi()..on('GET', '/notifications', body: _rows);
    ApiClient.overrideDio = api.dio();
    await NotificationStore.instance.syncFromServer();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const NotificationsScreen()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> longPress(WidgetTester tester, String title) async {
    await tester.longPress(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Delete selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
  }

  group('entering selection mode', () {
    testWidgets('the three arrive, and nothing is selected', (tester) async {
      await open(tester);

      expect(find.text('Notice 1'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.byTooltip('Delete selected'), findsNothing);
    });

    testWidgets('a long press starts it and ticks that one', (tester) async {
      await open(tester);

      await longPress(tester, 'Notice 2');

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byTooltip('Delete selected'), findsOneWidget);
    });

    testWidgets('a tap then adds more without leaving it', (tester) async {
      await open(tester);
      await longPress(tester, 'Notice 2');

      await tester.tap(find.text('Notice 1'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });

    testWidgets('and a tap on a ticked one unticks it', (tester) async {
      await open(tester);
      await longPress(tester, 'Notice 2');
      await tester.tap(find.text('Notice 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notice 1'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('unticking the last one leaves selection mode', (tester) async {
      await open(tester);
      await longPress(tester, 'Notice 2');

      await tester.tap(find.text('Notice 2'));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.byTooltip('Delete selected'), findsNothing);
    });
  });

  group('leaving without deleting', () {
    testWidgets('cancel puts everything back', (tester) async {
      await open(tester);
      await longPress(tester, 'Notice 2');

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(NotificationStore.instance.count, 3, reason: 'nothing deleted');
    });

    testWidgets('and so does declining the confirmation', (tester) async {
      await open(tester);
      await longPress(tester, 'Notice 2');

      await tester.tap(find.byTooltip('Delete selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(NotificationStore.instance.count, 3);
      expect(find.text('1 selected'), findsOneWidget, reason: 'still ticked');
    });
  });

  group('deleting the selected', () {
    testWidgets('asks first, naming how many', (tester) async {
      await open(tester);
      await longPress(tester, 'Notice 1');
      await tester.tap(find.text('Notice 2'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete selected'));
      await tester.pumpAndSettle();

      expect(find.text('Delete 2 notifications?'), findsOneWidget);
    });

    testWidgets('deletes them on the server, then takes them off', (
      tester,
    ) async {
      api
        ..on('DELETE', '/notifications/n-1', status: 204, body: const {})
        ..on('DELETE', '/notifications/n-2', status: 204, body: const {});

      await open(tester);
      await longPress(tester, 'Notice 1');
      await tester.tap(find.text('Notice 2'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(
        api.calls.where((c) => c.method == 'DELETE').map((c) => c.path),
        containsAll(['/notifications/n-1', '/notifications/n-2']),
      );
      expect(find.text('Notice 1'), findsNothing);
      expect(find.text('Notice 2'), findsNothing);
      expect(find.text('Notice 3'), findsOneWidget, reason: 'not selected');
      expect(NotificationStore.instance.count, 1);
      expect(find.text('2 notifications deleted'), findsOneWidget);
    });

    testWidgets('and leaves selection mode afterwards', (tester) async {
      api.on('DELETE', '/notifications/n-1', status: 204, body: const {});

      await open(tester);
      await longPress(tester, 'Notice 1');
      await confirm(tester);

      expect(find.text('Notifications'), findsOneWidget);
    });
  });

  group('when the server refuses', () {
    testWidgets('the row stays on the list', (tester) async {
      // The rule this whole feature rests on: nothing leaves the screen that
      // the server still holds, or it comes back on the next sync.
      api.on('DELETE', '/notifications/n-1', status: 500, body: const {});

      await open(tester);
      await longPress(tester, 'Notice 1');
      await confirm(tester);

      expect(find.text('Notice 1'), findsOneWidget);
      expect(NotificationStore.instance.count, 3);
    });

    testWidgets('it says so rather than claiming success', (tester) async {
      api.on('DELETE', '/notifications/n-1', status: 500, body: const {});

      await open(tester);
      await longPress(tester, 'Notice 1');
      await confirm(tester);

      expect(find.textContaining('could not be deleted'), findsOneWidget);
    });

    testWidgets('the failed one stays ticked, ready to retry', (tester) async {
      api.on('DELETE', '/notifications/n-1', status: 500, body: const {});

      await open(tester);
      await longPress(tester, 'Notice 1');
      await confirm(tester);

      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('a partial failure deletes only what the server took', (
      tester,
    ) async {
      api
        ..on('DELETE', '/notifications/n-1', status: 204, body: const {})
        ..on('DELETE', '/notifications/n-2', status: 500, body: const {});

      await open(tester);
      await longPress(tester, 'Notice 1');
      await tester.tap(find.text('Notice 2'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('Notice 1'), findsNothing, reason: 'the server took it');
      expect(find.text('Notice 2'), findsOneWidget, reason: 'it refused this');
      expect(find.textContaining('Deleted 1 of 2'), findsOneWidget);
    });
  });

  group('the page still works as it did', () {
    testWidgets('a plain tap opens rather than selects', (tester) async {
      await open(tester);

      await tester.tap(find.text('Notice 1'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsNothing);
    });
  });
}

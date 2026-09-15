import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/notifications/data/notification_repository.dart';
import 'package:gtradea_amazon/features/notifications/data/notification_store.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notifications_screen.dart';
import 'package:gtradea_amazon/features/quotes/presentation/quote_request_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// A quote notification, in the shape the shop's table holds.
Map<String, dynamic> _quoteRow({
  String id = 'n-1',
  bool read = false,
  String requestId = 'req-9',
}) => {
  'id': id,
  'type': 'quote_ready',
  'title': 'Your quote is ready',
  'message': 'The seller priced your request.',
  'is_read': read,
  'created_at': '2026-08-30T09:00:00Z',
  'data': {'request_id': requestId},
};

Map<String, dynamic> _supportRow({String id = 'n-2'}) => {
  'id': id,
  'type': 'support_ticket_reply',
  'title': 'Support replied',
  'message': 'We have answered your message.',
  'is_read': false,
  'created_at': '2026-08-30T10:00:00Z',
  'data': {'ticket_id': 'tkt-3'},
};

void main() {
  late FakeApi api;

  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    NotificationStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/notifications', body: const []);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    NotificationStore.instance.resetForTest();
    clearApiStub();
  });

  group('reading the shop notifications', () {
    test('a quote event becomes a quote notification', () async {
      // The bug: these were never read at all, so a priced quote produced
      // nothing on the device.
      signIn();
      api.on('GET', '/notifications', body: [_quoteRow()]);

      final items = await NotificationRepository.instance.list();

      final one = items.single;
      expect(one.category, NotificationCategory.quote);
      expect(one.title, 'Your quote is ready');
      expect(one.body, 'The seller priced your request.');
      expect(one.targetId, 'req-9', reason: 'so a tap can open it');
      expect(one.read, isFalse);
      expect(one.fromServer, isTrue);
    });

    test('a support reply becomes a support notification', () async {
      signIn();
      api.on('GET', '/notifications', body: [_supportRow()]);

      final one = (await NotificationRepository.instance.list()).single;
      expect(one.category, NotificationCategory.support);
      expect(one.targetId, 'tkt-3');
    });

    test('the type vocabulary is matched loosely, not exactly', () {
      // The server's vocabulary is its own and gains entries without asking.
      expect(
        categoryForServerType('quote_price_updated'),
        NotificationCategory.quote,
      );
      expect(
        categoryForServerType('product_request_replied'),
        NotificationCategory.quote,
      );
      expect(
        categoryForServerType('support_message'),
        NotificationCategory.support,
      );
      expect(
        categoryForServerType('order_shipped'),
        NotificationCategory.orderShipped,
      );
    });

    test('a row with nothing to say is dropped', () {
      expect(notificationFromServer(const {'id': 'x'}), isNull);
      expect(notificationFromServer(const {'title': 'No id'}), isNull);
    });
  });

  group('the store', () {
    test('merges the shop notifications into the list', () async {
      signIn();
      api.on('GET', '/notifications', body: [_quoteRow(), _supportRow()]);

      await NotificationStore.instance.load();

      final ids = NotificationStore.instance.items.map((n) => n.id);
      expect(ids, containsAll(['n-1', 'n-2']));
      expect(NotificationStore.instance.unreadCount, 2);
    });

    test('a second load refreshes rather than doing nothing', () async {
      // The realtime handler calls load() when the server says something
      // arrived. It used to return immediately once loaded, so the one path
      // that most needed to reach the server never did.
      signIn();
      await NotificationStore.instance.load();
      expect(NotificationStore.instance.unreadCount, 0);

      api.on('GET', '/notifications', body: [_quoteRow()]);
      await NotificationStore.instance.load();

      expect(NotificationStore.instance.unreadCount, 1);
    });

    test('the same event twice is one notification, not two', () async {
      signIn();
      api.on('GET', '/notifications', body: [_quoteRow()]);
      await NotificationStore.instance.load();
      await NotificationStore.instance.load();

      expect(
        NotificationStore.instance.items.where((n) => n.id == 'n-1'),
        hasLength(1),
      );
    });

    test('the server wins on whether one has been read', () async {
      signIn();
      api.on('GET', '/notifications', body: [_quoteRow()]);
      await NotificationStore.instance.load();
      expect(NotificationStore.instance.unreadCount, 1);

      // Read on another device.
      api.on('GET', '/notifications', body: [_quoteRow(read: true)]);
      await NotificationStore.instance.load();

      expect(NotificationStore.instance.unreadCount, 0);
    });

    test('marking read reaches the server', () async {
      signIn();
      api.on('GET', '/notifications', body: [_quoteRow()]);
      api.on('PATCH', '/notifications/n-1/read', status: 204);
      await NotificationStore.instance.load();

      NotificationStore.instance.markRead('n-1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        api.calls.where((c) => c.method == 'PATCH'),
        isNotEmpty,
        reason: 'or it comes back unread on the next sync',
      );
      expect(NotificationStore.instance.unreadCount, 0);
    });

    test('a failed sync leaves the list alone', () async {
      // Emptying the bell because the network blinked is worse than being
      // briefly out of date.
      signIn();
      api.on('GET', '/notifications', body: [_quoteRow()]);
      await NotificationStore.instance.load();

      api.on('GET', '/notifications', status: 500, body: const {});
      await NotificationStore.instance.load();

      expect(NotificationStore.instance.items, hasLength(1));
    });

    test('a guest asks for nothing', () async {
      await NotificationStore.instance.load();
      expect(
        api.calls.where((c) => c.path.contains('/notifications')),
        isEmpty,
      );
    });
  });

  group('the notifications screen', () {
    testWidgets('shows a quote notification and opens the quote', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/notifications', body: [_quoteRow()]);
      api.on('PATCH', '/notifications/n-1/read', status: 204);
      api.on(
        'GET',
        '/product-requests/req-9',
        body: const {
          'id': 'req-9',
          'product_title': 'Ice Silk Gloves',
          'status': 'quoted',
          'quoted_price': 900,
        },
      );
      _tall(tester);
      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Your quote is ready'), findsOneWidget);

      await tester.tap(find.text('Your quote is ready'));
      await tester.pumpAndSettle();

      expect(find.byType(QuoteRequestDetailScreen), findsOneWidget);
      // In the header, and again under 'Product Name'.
      expect(find.text('Ice Silk Gloves'), findsWidgets);
    });

    testWidgets('a quote notification with no id still opens the quotes', (
      tester,
    ) async {
      // Measured against production: the shop's quote notification carries no
      // id this app recognises, so a tap used to mark it read and go nowhere.
      // The list is the honest destination when the exact request is unknown.
      signIn();
      api.on(
        'GET',
        '/notifications',
        body: [
          {
            'id': 'n-3',
            'type': 'quote_reply',
            'title': 'New reply on your quote request',
            'message': 'good',
            'is_read': false,
            'created_at': '2026-08-30T09:00:00Z',
          },
        ],
      );
      api.on('PATCH', '/notifications/n-3/read', status: 204);
      api.on('GET', '/product-requests', body: const []);
      _tall(tester);
      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New reply on your quote request'));
      await tester.pumpAndSettle();

      expect(find.text('Product Inquiry'), findsOneWidget);
    });

    testWidgets('shows a support reply', (tester) async {
      signIn();
      api.on('GET', '/notifications', body: [_supportRow()]);
      _tall(tester);
      await tester.pumpWidget(_wrap(const NotificationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Support replied'), findsOneWidget);
    });
  });
}

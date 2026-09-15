import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/support/presentation/support_tickets_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

Widget _wrap() =>
    MaterialApp(theme: AppTheme.light, home: const SupportTicketsScreen());

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

const _delayed = {
  'id': 't1',
  'ticket_number': 'TKT-20260819-1027',
  'subject': 'Parcel never arrived',
  'description': 'It has been three weeks.',
  'status': 'waiting_customer',
  'category': 'shipping',
  'created_at': '2026-09-10T10:00:00Z',
  'updated_at': '2026-09-11T09:00:00Z',
};

const _refund = {
  'id': 't2',
  'ticket_number': 'TKT-20260820-2051',
  'subject': 'Refund for the blender',
  'description': 'It arrived cracked.',
  'status': 'open',
  'category': 'returns',
  'created_at': '2026-09-08T10:00:00Z',
  'updated_at': '2026-09-09T10:00:00Z',
};

/// A support reply, which is what an unread message is.
Map<String, dynamic> _reply(String id, String text, String at) => {
  'id': id,
  'sender_type': 'support',
  'message': text,
  'created_at': at,
};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/support/tickets', body: const [_delayed, _refund]);
    api.on('GET', '/support/tickets/t1/messages', body: const []);
    api.on('GET', '/support/tickets/t2/messages', body: const []);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  group('the inbox', () {
    testWidgets('lists every conversation with its subject and time', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Parcel never arrived'), findsOneWidget);
      expect(find.text('Refund for the blender'), findsOneWidget);
      // The opening line stands in until the thread's own last message is read.
      expect(find.text('It has been three weeks.'), findsOneWidget);
    });

    testWidgets('a row is compact enough to be an inbox', (tester) async {
      // The bug this guards: bordered cards with 14pt padding and a 10pt gap
      // spent roughly a third of the list's height on decoration.
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final row = tester.getRect(
        find.ancestor(
          of: find.text('Parcel never arrived'),
          matching: find.byType(InkWell),
        ).first,
      );
      expect(
        row.height,
        lessThanOrEqualTo(72),
        reason: 'two lines and an avatar, not a card',
      );
    });

    testWidgets('and is drawn as a list, not a stack of cards', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Hairlines between rows; no card, and nothing casting a shadow.
      expect(find.byType(Divider), findsWidgets);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('shows the real last message, and who said it', (tester) async {
      api.on(
        'GET',
        '/support/tickets/t1/messages',
        body: [
          _reply('m1', 'Could you confirm the address?', '2026-09-11T08:00:00Z'),
          const {
            'id': 'm2',
            'sender_type': 'user',
            'message': 'Jawalakhel, Lalitpur.',
            'created_at': '2026-09-11T09:00:00Z',
          },
        ],
      );
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // The shopper's own last word is prefixed, the way a chat inbox does it.
      expect(find.text('You: Jawalakhel, Lalitpur.'), findsOneWidget);
      expect(find.text('It has been three weeks.'), findsNothing);
    });
  });

  group('what is waiting', () {
    testWidgets('unread support replies are counted on the row', (
      tester,
    ) async {
      api.on(
        'GET',
        '/support/tickets/t1/messages',
        body: [
          _reply('m1', 'Looking into it.', '2026-09-11T08:00:00Z'),
          _reply('m2', 'Any update for us?', '2026-09-11T09:00:00Z'),
        ],
      );
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('Any update for us?'), findsOneWidget);
    });

    testWidgets('a thread with nothing from support carries no badge', (
      tester,
    ) async {
      // Nothing invented: the shopper's own messages are not unread, and a
      // badge on a thread nobody has answered would be a lie about it.
      api.on(
        'GET',
        '/support/tickets/t1/messages',
        body: const [
          {
            'id': 'm1',
            'sender_type': 'user',
            'message': 'Still waiting.',
            'created_at': '2026-09-11T09:00:00Z',
          },
        ],
      );
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('You: Still waiting.'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('a thread awaiting the shopper says so', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Named by the status layer now rather than by a literal in the row, so
      // this is the label the shop configures -- or, unconfigured as it is
      // today, the one the support system has always used for this state.
      //
      // Matched on the row's own tag rather than on the words: the filter row
      // above carries a chip with the same label, and "this conversation is
      // awaiting your reply" is a different claim from "there is a filter for
      // that state".
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.key == const ValueKey('status-tag') &&
              w.data == 'Awaiting your reply',
        ),
        findsOneWidget,
      );
      // And the other thread says what state it is in too.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.key == const ValueKey('status-tag') &&
              w.data == 'Open',
        ),
        findsOneWidget,
      );
    });
  });

  group('the search', () {
    Future<void> type(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
    }

    testWidgets('narrows the conversations to what was asked for', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await type(tester, 'blender');

      expect(find.text('Refund for the blender'), findsOneWidget);
      expect(find.text('Parcel never arrived'), findsNothing);
    });

    testWidgets('finds a thread by its ticket number', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await type(tester, '2051');

      expect(find.text('Refund for the blender'), findsOneWidget);
      expect(find.text('Parcel never arrived'), findsNothing);
    });

    testWidgets('searches what was actually said, not just the subject', (
      tester,
    ) async {
      api.on(
        'GET',
        '/support/tickets/t2/messages',
        body: [_reply('m1', 'A courier will collect it.', '2026-09-09T10:00:00Z')],
      );
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await type(tester, 'courier');

      expect(find.text('Refund for the blender'), findsOneWidget);
      expect(find.text('Parcel never arrived'), findsNothing);
    });

    testWidgets('says so when nothing matches, and can still be cleared', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await type(tester, 'motorcycle');

      expect(find.textContaining('No messages match'), findsOneWidget);
      // The box has to survive its own empty result, or the query cannot be
      // corrected.
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      expect(find.text('Parcel never arrived'), findsOneWidget);
      expect(find.text('Refund for the blender'), findsOneWidget);
    });

    testWidgets('filters what the server already sent, without re-asking', (
      tester,
    ) async {
      // `/support/tickets` takes no query parameter and answers unpaged, so a
      // `q` it ignored would redraw every thread under a search box claiming
      // to have filtered them.
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final before = api.calls.where((c) => c.path == '/support/tickets').length;
      await type(tester, 'blender');

      final listCalls = api.calls.where((c) => c.path == '/support/tickets');
      expect(listCalls.length, before);
      expect(
        listCalls.every((c) => !c.query.containsKey('q')),
        isTrue,
        reason: 'nothing is asked of an endpoint that cannot answer it',
      );
    });
  });

  group('an empty inbox', () {
    testWidgets('explains itself, and offers no search box', (tester) async {
      api.on('GET', '/support/tickets', body: const []);
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'nothing to search',
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/support/data/ticket_status_config.dart';
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

/// The status tag on a conversation row, as opposed to a filter chip that may
/// carry exactly the same words.
Finder _rowTag(String label) => find.byWidgetPredicate(
  (w) => w is Text && w.key == const ValueKey('status-tag') && w.data == label,
  description: 'row status tag "$label"',
);

Map<String, dynamic> _ticket({
  required String id,
  required String subject,
  required String status,
  String category = 'general',
}) => {
  'id': id,
  'ticket_number': 'TKT-2026-$id',
  'subject': subject,
  'description': 'Opening line for $subject.',
  'status': status,
  'category': category,
  'created_at': '2026-09-08T10:00:00Z',
  'updated_at': '2026-09-11T09:00:00Z',
};

/// The shape the settings store already uses for `active_payment_methods`:
/// a token to an object carrying its label, colour and order.
const _configured = {
  'setting_key': TicketStatusConfig.settingKey,
  'setting_value': {
    'waiting_customer': {
      'label': 'Needs you now',
      'color': '#E94724',
      'order': 1,
      'enabled': true,
    },
    'open': {'label': 'Being looked at', 'color': '#267488', 'order': 2},
    'archived': {'label': 'Archived', 'order': 3, 'enabled': false},
  },
};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    TicketStatusConfig.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    // Unset is the live state of this key today, and therefore the default
    // every test starts from unless it says otherwise.
    api.on(
      'GET',
      '/site-settings/${TicketStatusConfig.settingKey}',
      body: const {
        'setting_key': TicketStatusConfig.settingKey,
        'setting_value': null,
      },
    );
    api.on('GET', '/support/tickets', body: const []);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    TicketStatusConfig.instance.resetForTest();
    clearApiStub();
  });

  group('reading the shop configuration', () {
    test('an unset setting is not an error, it is just nothing', () async {
      await TicketStatusConfig.instance.load();

      expect(TicketStatusConfig.instance.isLoaded, isTrue);
      expect(TicketStatusConfig.instance.hasBackendConfig, isFalse);
    });

    test('a configured status takes its label, colour and order', () async {
      api.on(
        'GET',
        '/site-settings/${TicketStatusConfig.settingKey}',
        body: _configured,
      );
      await TicketStatusConfig.instance.load();

      final style = TicketStatusConfig.instance.styleFor('waiting_customer');
      expect(style.label, 'Needs you now');
      expect(style.colour, const Color(0xFFE94724));
      expect(style.order, 1);
      expect(style.fromBackend, isTrue);
    });

    test('a status the shop has not configured still gets a label', () async {
      api.on(
        'GET',
        '/site-settings/${TicketStatusConfig.settingKey}',
        body: _configured,
      );
      await TicketStatusConfig.instance.load();

      // Never seen by this build or by the shop's configuration.
      final style = TicketStatusConfig.instance.styleFor(
        'awaiting_seller_reply',
      );
      expect(style.label, 'Awaiting Seller Reply');
      expect(style.fromBackend, isFalse);
    });

    test('a server that cannot be reached costs labels, not the screen', () async {
      api.on(
        'GET',
        '/site-settings/${TicketStatusConfig.settingKey}',
        status: 500,
        body: const {},
      );
      await TicketStatusConfig.instance.load();

      expect(TicketStatusConfig.instance.hasBackendConfig, isFalse);
      expect(TicketStatusConfig.instance.styleFor('open').label, 'Open');
    });

    test('the words come from the token when nothing else knows it', () {
      expect(humaniseStatus('awaiting_customer_reply'), 'Awaiting Customer Reply');
      expect(humaniseStatus('pending-review'), 'Pending Review');
      expect(humaniseStatus(''), '');
    });

    test('filters are built from the statuses actually in hand', () async {
      api.on(
        'GET',
        '/site-settings/${TicketStatusConfig.settingKey}',
        body: _configured,
      );
      await TicketStatusConfig.instance.load();

      final filters = TicketStatusConfig.instance.filtersFor([
        'open',
        'waiting_customer',
        'some_future_state',
        'open',
        // Configured, but switched off by the shop.
        'archived',
      ]);

      expect(
        filters.map((f) => f.label),
        // The shop's order first, then anything it has not configured.
        ['Needs you now', 'Being looked at', 'Some Future State'],
        reason: 'configured order leads, unconfigured follows, none repeat',
      );
    });
  });

  group('the tag on a row', () {
    testWidgets('says what state the conversation is in', (tester) async {
      api.on(
        'GET',
        '/support/tickets',
        body: [
          _ticket(id: 't1', subject: 'Parcel late', status: 'waiting_customer'),
          _ticket(id: 't2', subject: 'Refund', status: 'closed'),
        ],
      );
      api.on('GET', '/support/tickets/t1/messages', body: const []);
      api.on('GET', '/support/tickets/t2/messages', body: const []);
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_rowTag('Awaiting your reply'), findsOneWidget);
      expect(_rowTag('Closed'), findsOneWidget);
    });

    testWidgets('renders a status this build has never heard of', (
      tester,
    ) async {
      // The whole point: a status the backend invents after this release still
      // reads as words rather than as a raw database value, with no code change.
      api.on(
        'GET',
        '/support/tickets',
        body: [
          _ticket(
            id: 't1',
            subject: 'Parcel late',
            status: 'awaiting_warehouse_check',
          ),
        ],
      );
      api.on('GET', '/support/tickets/t1/messages', body: const []);
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_rowTag('Awaiting Warehouse Check'), findsOneWidget);
    });

    testWidgets('takes the shop label over the one worked out here', (
      tester,
    ) async {
      api.on(
        'GET',
        '/site-settings/${TicketStatusConfig.settingKey}',
        body: _configured,
      );
      api.on(
        'GET',
        '/support/tickets',
        body: [
          _ticket(id: 't1', subject: 'Parcel late', status: 'waiting_customer'),
        ],
      );
      api.on('GET', '/support/tickets/t1/messages', body: const []);
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_rowTag('Needs you now'), findsOneWidget);
      expect(_rowTag('Awaiting your reply'), findsNothing);
    });

    testWidgets('and does not make the row any taller', (tester) async {
      api.on(
        'GET',
        '/support/tickets',
        body: [
          _ticket(id: 't1', subject: 'Parcel late', status: 'waiting_customer'),
        ],
      );
      api.on('GET', '/support/tickets/t1/messages', body: const []);
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final row = tester
          .getRect(
            find
                .ancestor(
                  of: find.text('Parcel late'),
                  matching: find.byType(InkWell),
                )
                .first,
          );
      expect(
        row.height,
        lessThanOrEqualTo(72),
        reason: 'the tag rides the line the preview was already on',
      );
    });
  });

  group('filtering by status', () {
    Future<void> pumpTwo(WidgetTester tester) async {
      api.on(
        'GET',
        '/support/tickets',
        body: [
          _ticket(id: 't1', subject: 'Parcel late', status: 'waiting_customer'),
          _ticket(id: 't2', subject: 'Refund', status: 'closed'),
        ],
      );
      api.on('GET', '/support/tickets/t1/messages', body: const []);
      api.on('GET', '/support/tickets/t2/messages', body: const []);
      _phone(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
    }

    /// Taps a filter chip, scrolling the row until it is actually reachable.
    ///
    /// The row scrolls horizontally, so a chip can be built and still sit
    /// outside the viewport on a narrow phone -- where a plain `tap` finds the
    /// widget, misses it in the hit test, and leaves the filter unchanged. A
    /// test that taps nothing and asserts nothing changed passes for the wrong
    /// reason, which is how the last of these hid a real defect.
    Future<void> tapChip(WidgetTester tester, String label) async {
      final chip = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    testWidgets('offers only the states this account actually has', (
      tester,
    ) async {
      await pumpTwo(tester);

      // Both conversations, and so both of their states, are on screen.
      expect(find.text('Parcel late'), findsOneWidget);
      expect(find.text('Refund'), findsOneWidget);
      // Counted by type before anything is looked up by its words: a chip the
      // row never built is invisible to a finder that searches by label, and
      // the whole row failing then looks like one missing status. This is the
      // guard on a filter row that dropped its last state on a narrow phone.
      expect(
        find.byType(ChoiceChip),
        findsNWidgets(3),
        reason: 'All, plus one per state in hand',
      );
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(
        find.widgetWithText(ChoiceChip, 'Awaiting your reply'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ChoiceChip, 'Closed'), findsOneWidget);
      // Nothing is in this state, so there is no dead tab for it.
      expect(find.widgetWithText(ChoiceChip, 'Resolved'), findsNothing);
    });

    testWidgets('choosing one shows just those conversations', (tester) async {
      await pumpTwo(tester);

      await tapChip(tester, 'Closed');

      expect(find.text('Refund'), findsOneWidget);
      expect(find.text('Parcel late'), findsNothing);
    });

    testWidgets('a filter that empties says so and can be undone', (
      tester,
    ) async {
      await pumpTwo(tester);

      await tapChip(tester, 'Closed');
      await tester.enterText(find.byType(TextField), 'parcel');
      await tester.pumpAndSettle();

      // Closed, and searched for a word only the other thread has. The empty
      // state names the state being filtered on as well as the words, because
      // "nothing matches" is a different thing to fix depending on which of
      // the two emptied the list.
      expect(
        find.textContaining('No Closed message matches "parcel"'),
        findsOneWidget,
      );

      await tapChip(tester, 'All');
      expect(find.text('Parcel late'), findsOneWidget);
    });

    testWidgets('is filtered here rather than asked of the server', (
      tester,
    ) async {
      // `/support/tickets` answers unpaged and takes no status parameter --
      // proven by probe, where `?status=open` and no query behave identically.
      // Sending one the server ignored would redraw every thread under a tab
      // claiming to have filtered them.
      await pumpTwo(tester);
      final before = api.calls
          .where((c) => c.path == '/support/tickets')
          .length;

      await tapChip(tester, 'Closed');
      // Proved to have actually filtered, so that "nothing was re-fetched" is
      // a statement about a filter that ran rather than about a tap that
      // missed.
      expect(find.text('Parcel late'), findsNothing);

      final listCalls = api.calls.where((c) => c.path == '/support/tickets');
      expect(listCalls.length, before);
      expect(listCalls.every((c) => !c.query.containsKey('status')), isTrue);
    });
  });
}

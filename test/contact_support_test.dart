import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/help/presentation/contact_support_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

Widget _wrap() =>
    MaterialApp(theme: AppTheme.light, home: const ContactSupportScreen());

/// The page is a long form; the default 600x800 leaves the button unbuilt.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

const _ticket = {
  'id': 't1',
  'ticket_number': 'TKT-20260819-1027',
  'subject': 'Testing Ticket system',
  'description': 'A test.',
  'status': 'open',
  'category': 'general',
  'created_at': '2026-08-19T10:27:00Z',
};

/// Fills every required field. Returns nothing -- the point is the side effect.
Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Your name'),
    'Rabi Yadav',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Brief description of your issue'),
    'Parcel never arrived',
  );
  await tester.enterText(
    find.byType(TextFormField).last,
    'It has been three weeks.',
  );
  await tester.tap(find.text('Select a category'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Order issues').last);
  await tester.pumpAndSettle();
}

void main() {
  late FakeApi api;

  /// Signs in, then puts our own stub back.
  ///
  /// `signInForTest` installs a stub of its own, which would otherwise
  /// swallow every call this file is asserting on.
  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/support/tickets', body: const []);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  group('the Contact Support form', () {
    testWidgets('shows every field the reference asks for', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Submit a Support Ticket'), findsOneWidget);
      expect(find.textContaining("respond within 2-4 hours"), findsOneWidget);
      // Starred, because it is required now.
      expect(find.text('Name *'), findsOneWidget);
      expect(find.text('Select a category'), findsOneWidget);
      expect(find.text('Submit Ticket'), findsOneWidget);
    });

    testWidgets('the email is prefilled from the session', (tester) async {
      // The shop already knows it; asking again for something it has is a
      // question the shopper should not have to answer.
      signIn();
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final email = AuthStore.instance.account!.email;
      expect(find.text(email), findsOneWidget);
    });

    testWidgets('an incomplete form is refused before anything is sent', (
      tester,
    ) async {
      signIn();
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Ticket'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter your name so support knows who is asking.'),
        findsOneWidget,
      );
      expect(find.text('Choose a category.'), findsOneWidget);
      expect(find.text('Add a short subject.'), findsOneWidget);
      expect(find.text('Tell support what happened.'), findsOneWidget);
      expect(
        api.calls.where((c) => c.method == 'POST'),
        isEmpty,
        reason: 'nothing was sent',
      );
    });

    testWidgets('a form with no name is refused', (tester) async {
      signIn();
      api.on('POST', '/support/tickets', body: _ticket);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Everything else filled, so the name is provably the only thing
      // standing between this form and the server.
      await _fillForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'),
        '   ',
      );
      await tester.tap(find.text('Submit Ticket'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter your name so support knows who is asking.'),
        findsOneWidget,
      );
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });

    testWidgets('an obvious typo in the email is caught here', (tester) async {
      signIn();
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'you@example.com'),
        'not-an-email',
      );
      await tester.tap(find.text('Submit Ticket'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('does not look like an email'),
        findsOneWidget,
      );
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });

    testWidgets('a filled form reaches the existing support endpoint', (
      tester,
    ) async {
      signIn();
      api.on('POST', '/support/tickets', body: _ticket);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _fillForm(tester);
      await tester.tap(find.text('Submit Ticket'));
      await tester.pumpAndSettle();

      final sent = api.calls.firstWhere((c) => c.method == 'POST');
      expect(
        sent.path,
        contains('/support/tickets'),
        reason: 'the system the app already has, not a second one',
      );
      expect(sent.json['subject'], 'Parcel never arrived');
      expect(sent.json['description'], 'It has been three weeks.');
      expect(sent.json['category'], 'order');
      expect(sent.json['email'], AuthStore.instance.account!.email);
      expect(
        sent.json['name'],
        'Rabi Yadav',
        reason: 'the required name reaches the support system',
      );
    });

    testWidgets('a sent ticket is confirmed with its number', (tester) async {
      // The number is what somebody quotes when they chase it, so the
      // confirmation carries it rather than a bare "thanks".
      signIn();
      api.on('POST', '/support/tickets', body: _ticket);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _fillForm(tester);
      await tester.tap(find.text('Submit Ticket'));
      await tester.pumpAndSettle();

      expect(find.text('Ticket submitted'), findsOneWidget);
      // Twice: in the confirmation, and at the top of the recent list the
      // new ticket has just joined.
      expect(find.textContaining('TKT-20260819-1027'), findsWidgets);
      expect(find.text('View ticket'), findsOneWidget);
      // The form is gone, so the same ticket cannot be raised twice by a
      // second tap on a button that is still sitting there.
      expect(find.text('Submit Ticket'), findsNothing);
    });

    testWidgets('a refused ticket says why and keeps what was typed', (
      tester,
    ) async {
      signIn();
      api.on(
        'POST',
        '/support/tickets',
        status: 500,
        body: const {'error': 'Support is down for maintenance'},
      );
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _fillForm(tester);
      await tester.tap(find.text('Submit Ticket'));
      await tester.pumpAndSettle();

      expect(find.textContaining('maintenance'), findsOneWidget);
      // Still on the form, with the words still in it -- a failure must not
      // cost somebody the message they just wrote.
      expect(find.text('Submit Ticket'), findsOneWidget);
      expect(find.text('Parcel never arrived'), findsOneWidget);
    });
  });

  group('Your Recent Tickets', () {
    testWidgets('lists what this account has already asked', (tester) async {
      signIn();
      api.on('GET', '/support/tickets', body: const [_ticket]);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Your Recent Tickets'), findsOneWidget);
      expect(find.text('TKT-20260819-1027'), findsOneWidget);
      expect(find.text('Testing Ticket system'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('is absent for an account with none, rather than empty', (
      tester,
    ) async {
      signIn();
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Your Recent Tickets'), findsNothing);
      expect(find.text('Submit a Support Ticket'), findsOneWidget);
    });

    testWidgets('a guest still gets the form', (tester) async {
      // The list needs a session; the form does not -- the server takes a
      // guest ticket against whatever address is typed in.
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Your Recent Tickets'), findsNothing);
      expect(find.text('Submit a Support Ticket'), findsOneWidget);
      expect(
        api.calls.where((c) => c.path.contains('/support/tickets')),
        isEmpty,
        reason: 'no point asking for a signed-in shopper list as a guest',
      );
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/support/data/support_attachment.dart';
import 'package:gtradea_amazon/features/support/data/support_repository.dart';
import 'package:gtradea_amazon/features/support/presentation/message_attachment.dart';
import 'package:gtradea_amazon/features/support/presentation/ticket_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

/// A real 1x1 PNG, so an image attachment actually decodes.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 218, 99, 100, 96, 96, 0, 0, 0, 5, 0, 1, 127, 253, 13, 90, 0, 0, 0, 0, //
  73, 69, 78, 68, 174, 66, 96, 130,
]);

PickedAttachment _file(String name) =>
    PickedAttachment(name: name, bytes: _png);

SupportTicket get _ticket => SupportTicket.fromJson(const {
  'id': 't-1',
  'ticket_number': 'TKT-1',
  'subject': 'Broken item',
  'description': 'It arrived bent',
  'status': 'open',
});

Map<String, dynamic> _message({
  String id = 'm-1',
  String message = 'Here you go',
  List<String> attachments = const [],
  String sender = 'user',
  String? replyTo,
}) => {
  'id': id,
  'sender_type': sender,
  'message': message,
  'created_at': '2026-08-31T09:00:00Z',
  'attachments': attachments,
  'reply_to_message_id': ?replyTo,
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
    SupportAttachmentRepository.instance.clearDownloadsForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on(
      'GET',
      '/support/tickets/t-1',
      body: {
        'id': 't-1',
        'ticket_number': 'TKT-1',
        'subject': 'Broken item',
        'status': 'open',
      },
    );
    api.on('GET', '/support/tickets/t-1/messages', body: const []);
    api.on('POST', '/support/tickets/t-1/messages', body: const {});
    api.on('POST', '/media/upload', body: {'key': 'u/1/shot.png'});
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    SupportAttachmentRepository.pickerOverride = null;
    SupportAttachmentRepository.instance.clearDownloadsForTest();
    clearApiStub();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TicketDetailScreen(ticket: _ticket),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> attach(WidgetTester tester, List<PickedAttachment> files) async {
    SupportAttachmentRepository.pickerOverride = () async => files;
    await tester.tap(find.byTooltip('Attach File'));
    await tester.pumpAndSettle();
  }

  group('attaching to a message', () {
    testWidgets('the paperclip sits beside the input', (tester) async {
      signIn();
      await pump(tester);

      expect(find.byTooltip('Attach File'), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
    });

    testWidgets('a chosen file is shown before sending', (tester) async {
      signIn();
      await pump(tester);

      await attach(tester, [_file('receipt.pdf')]);

      expect(find.text('receipt.pdf'), findsOneWidget);
      expect(find.textContaining('PDF document'), findsOneWidget);
    });

    testWidgets('and can be taken off again', (tester) async {
      signIn();
      await pump(tester);
      await attach(tester, [_file('receipt.pdf')]);

      await tester.tap(find.byTooltip('Remove receipt.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('receipt.pdf'), findsNothing);
    });

    testWidgets('an unsupported file is refused with a reason', (tester) async {
      signIn();
      await pump(tester);

      await attach(tester, [_file('macro.exe')]);

      expect(
        find.textContaining('.exe files are not supported'),
        findsOneWidget,
      );
      expect(find.text('macro.exe'), findsNothing);
    });

    testWidgets('a guest cannot attach', (tester) async {
      await pump(tester);

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Sign in to attach files'),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('what can be sent', () {
    Map<String, dynamic> sentBody() {
      final call = api.calls.lastWhere(
        (c) => c.method == 'POST' && c.path.endsWith('/messages'),
      );
      return jsonDecode(jsonEncode(call.body)) as Map<String, dynamic>;
    }

    testWidgets('text on its own, as before', (tester) async {
      signIn();
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'Any update?');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(sentBody()['message'], 'Any update?');
      expect(sentBody().containsKey('attachments'), isFalse);
    });

    testWidgets('an attachment on its own', (tester) async {
      signIn();
      await pump(tester);
      await attach(tester, [_file('receipt.pdf')]);

      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      final body = sentBody();
      expect(body['attachments'], ['u/1/shot.png']);
      expect(
        body['message'],
        '(attachment)',
        reason: 'a row with no words reads as a blank in the thread',
      );
    });

    testWidgets('text and an attachment together', (tester) async {
      signIn();
      await pump(tester);
      await attach(tester, [_file('receipt.pdf')]);

      await tester.enterText(find.byType(TextField), 'Here is the receipt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      final body = sentBody();
      expect(body['message'], 'Here is the receipt');
      expect(body['attachments'], ['u/1/shot.png']);
    });

    testWidgets('an empty composer sends nothing at all', (tester) async {
      signIn();
      await pump(tester);

      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(
        api.calls.where(
          (c) => c.method == 'POST' && c.path.endsWith('/messages'),
        ),
        isEmpty,
      );
    });

    testWidgets('a failed send keeps the files to try again', (tester) async {
      signIn();
      api.on('POST', '/media/upload', status: 500, body: const {});
      await pump(tester);
      await attach(tester, [_file('receipt.pdf')]);

      await tester.enterText(find.byType(TextField), 'Here it is');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(
        find.text('receipt.pdf'),
        findsOneWidget,
        reason: 'not picked a second time',
      );
    });
  });

  group('what the thread shows afterwards', () {
    testWidgets('an image comes back as a picture', (tester) async {
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [
          _message(attachments: const ['u/1/shot.png']),
        ],
      );
      api.on('GET', '/media/support-attachments/object', body: _png);

      await pump(tester);

      expect(find.byType(MessageAttachment), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('a document comes back named, with a way to open it', (
      tester,
    ) async {
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [
          _message(attachments: const ['u/1/invoice.pdf']),
        ],
      );

      await pump(tester);

      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });

    testWidgets('they survive the thread being reopened', (tester) async {
      // The keys come back with the message, so nothing is held only in this
      // screen's memory.
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [
          _message(attachments: const ['u/1/invoice.pdf']),
        ],
      );

      await pump(tester);
      expect(find.text('invoice.pdf'), findsOneWidget);

      await pump(tester);

      expect(find.text('invoice.pdf'), findsOneWidget);
    });

    testWidgets('a message with no files shows none', (tester) async {
      signIn();
      api.on('GET', '/support/tickets/t-1/messages', body: [_message()]);

      await pump(tester);

      expect(find.text('Here you go'), findsOneWidget);
      expect(find.byType(MessageAttachment), findsNothing);
    });
  });

  group('replying to a message', () {
    Future<void> reply(WidgetTester tester, String toText) async {
      await tester.longPress(find.text(toText));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
    }

    testWidgets('holding a message offers Reply', (tester) async {
      signIn();
      api.on('GET', '/support/tickets/t-1/messages', body: [_message()]);
      await pump(tester);

      await tester.longPress(find.text('Here you go'));
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);
    });

    testWidgets('the message being answered is previewed above the input', (
      tester,
    ) async {
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [
          _message(message: 'Your parcel is on its way', sender: 'support'),
        ],
      );
      await pump(tester);

      await reply(tester, 'Your parcel is on its way');

      // Named, quoted, and cancellable.
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Your parcel is on its way'), findsNWidgets(2));
      expect(find.byTooltip('Cancel reply'), findsOneWidget);
    });

    testWidgets('an attachment is quoted by its file name', (tester) async {
      // A message that is only a file has no words worth quoting.
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [
          _message(
            message: '(attachment)',
            attachments: const ['u/1/invoice.pdf'],
          ),
        ],
      );
      await pump(tester);

      await reply(tester, '(attachment)');

      expect(find.text('invoice.pdf'), findsNWidgets(2));
    });

    testWidgets('the reply is cancelled without sending anything', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/support/tickets/t-1/messages', body: [_message()]);
      await pump(tester);
      await reply(tester, 'Here you go');

      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Cancel reply'), findsNothing);
    });

    testWidgets('sending carries the original message id', (tester) async {
      // The relationship is stored by the server, not remembered here.
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [_message(id: 'm-9', message: 'Your parcel is on its way')],
      );
      await pump(tester);
      await reply(tester, 'Your parcel is on its way');

      await tester.enterText(find.byType(TextField), 'Thanks');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      final call = api.calls.lastWhere(
        (c) => c.method == 'POST' && c.path.endsWith('/messages'),
      );
      final body = jsonDecode(jsonEncode(call.body)) as Map<String, dynamic>;
      expect(body['reply_to_message_id'], 'm-9');
      expect(body['message'], 'Thanks');
    });

    testWidgets('a reply can carry a file as well as words', (tester) async {
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [_message(id: 'm-9', message: 'Send us the receipt')],
      );
      await pump(tester);
      await reply(tester, 'Send us the receipt');
      await attach(tester, [_file('receipt.pdf')]);

      await tester.enterText(find.byType(TextField), 'Here it is');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      final call = api.calls.lastWhere(
        (c) => c.method == 'POST' && c.path.endsWith('/messages'),
      );
      final body = jsonDecode(jsonEncode(call.body)) as Map<String, dynamic>;
      expect(body['reply_to_message_id'], 'm-9');
      expect(body['attachments'], ['u/1/shot.png']);
      expect(body['message'], 'Here it is');
    });

    testWidgets('a stored reply comes back quoted in the thread', (
      tester,
    ) async {
      // Read off the server, so it survives reopening.
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [
          _message(id: 'm-1', message: 'Your parcel is on its way'),
          _message(id: 'm-2', message: 'Thanks', replyTo: 'm-1'),
        ],
      );

      await pump(tester);

      expect(find.text('Thanks'), findsOneWidget);
      expect(
        find.text('Your parcel is on its way'),
        findsNWidgets(2),
        reason: 'once as itself, once quoted inside the reply',
      );
    });

    testWidgets('a reply whose original is gone still reads as a message', (
      tester,
    ) async {
      // The server can hold an id this thread no longer has a row for.
      signIn();
      api.on(
        'GET',
        '/support/tickets/t-1/messages',
        body: [_message(id: 'm-2', message: 'Thanks', replyTo: 'deleted')],
      );

      await pump(tester);

      expect(find.text('Thanks'), findsOneWidget);
    });
  });

  group('naming what came back', () {
    test('the key carries a folder the shopper never named', () {
      expect(
        SupportAttachmentRepository.fileNameFor('u/9/receipt.pdf'),
        'receipt.pdf',
      );
      expect(SupportAttachmentRepository.fileNameFor('shot.png'), 'shot.png');
    });

    test('pictures are told apart from documents by their name', () {
      for (final key in ['a/b.jpg', 'a/b.JPEG', 'a/b.png', 'a/b.webp']) {
        expect(
          SupportAttachmentRepository.isImageKey(key),
          isTrue,
          reason: key,
        );
      }
      for (final key in ['a/b.pdf', 'a/b.docx', 'a/b.txt']) {
        expect(
          SupportAttachmentRepository.isImageKey(key),
          isFalse,
          reason: key,
        );
      }
    });
  });
}

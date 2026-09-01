import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/help/presentation/contact_support_screen.dart';
import 'package:gtradea_amazon/features/support/data/support_attachment.dart';
import 'package:gtradea_amazon/features/support/data/support_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

/// A real 1x1 PNG. Filler bytes would not decode, and a thumbnail that
/// silently fell back to its error icon would let this pass while showing the
/// shopper nothing.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 218, 99, 100, 96, 96, 0, 0, 0, 5, 0, 1, 127, 253, 13, 90, 0, 0, 0, 0, //
  73, 69, 78, 68, 174, 66, 96, 130,
]);

PickedAttachment _image(String name) =>
    PickedAttachment(name: name, bytes: _png);

PickedAttachment _file(String name, {int bytes = 1024}) => PickedAttachment(
  name: name,
  bytes: Uint8List.fromList(List.filled(bytes, 65)),
);

void main() {
  late FakeApi api;

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
    api.on('POST', '/media/upload', body: {'key': 'u/1/shot.png'});
    api.on(
      'POST',
      '/support/tickets',
      body: {'id': 't-1', 'ticket_number': 'TKT-1', 'subject': 'Broken'},
    );
    api.on('POST', '/support/tickets/t-1/messages', body: const {});
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    SupportAttachmentRepository.pickerOverride = null;
    clearApiStub();
  });

  group('what the bucket will take', () {
    // The limits are the server's own, published by GET /media/buckets:
    // support-attachments is max_bytes 10485760, admin_only false.
    test('the ceiling is the bucket own max_bytes', () {
      expect(SupportAttachmentRepository.maxBytes, 10485760);
      expect(formatFileSize(SupportAttachmentRepository.maxBytes), '10 MB');
    });

    test('an oversized file is refused, and says by how much', () {
      final reason = SupportAttachmentRepository.rejectionFor(
        _file('scan.pdf', bytes: 10485761),
      );

      expect(reason, contains('over the 10 MB limit'));
    });

    test('an unsupported type is refused by name', () {
      final reason = SupportAttachmentRepository.rejectionFor(_file('go.exe'));

      expect(reason, contains('.exe files are not supported'));
      expect(reason, contains('PDF'));
    });

    test('the types the storefront accepts are accepted here', () {
      for (final name in [
        'a.jpg',
        'a.jpeg',
        'a.png',
        'a.webp',
        'a.pdf',
        'a.doc',
        'a.docx',
      ]) {
        expect(
          SupportAttachmentRepository.rejectionFor(_file(name)),
          isNull,
          reason: name,
        );
      }
    });

    test('an empty file is refused rather than silently sent', () {
      expect(
        SupportAttachmentRepository.rejectionFor(_file('void.png', bytes: 0)),
        contains('is empty'),
      );
    });

    test('an image is something that can be shown, a document is not', () {
      for (final name in ['a.jpg', 'a.jpeg', 'a.png', 'a.webp', 'a.gif']) {
        expect(_file(name).isImage, isTrue, reason: name);
      }
      for (final name in ['a.pdf', 'a.doc', 'a.docx', 'a.txt']) {
        expect(_file(name).isImage, isFalse, reason: name);
      }
    });

    test('sizes read the way a person reads them', () {
      expect(formatFileSize(900), '900 B');
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(1048576), '1.0 MB');
    });
  });

  group('the upload', () {
    test('goes to the support bucket and returns the storage key', () async {
      signIn();

      final key = await SupportAttachmentRepository.instance.upload(
        _file('shot.png'),
      );

      expect(key, 'u/1/shot.png');
      final call = api.calls.firstWhere(
        (c) => c.path.contains('/media/upload'),
      );
      expect(call.method, 'POST');
    });

    test('a key the server does not return is an error, not a silent drop', () {
      signIn();
      api.on('POST', '/media/upload', body: const {});

      expect(
        SupportAttachmentRepository.instance.upload(_file('shot.png')),
        throwsA(isA<Object>()),
      );
    });

    test('a message carries the keys as attachments', () async {
      signIn();

      await SupportRepository.instance.send(
        't-1',
        'Attached: shot.png',
        attachments: const ['u/1/shot.png'],
      );

      final call = api.calls.firstWhere((c) => c.path.endsWith('/messages'));
      final body = jsonDecode(jsonEncode(call.body)) as Map<String, dynamic>;
      expect(body['attachments'], ['u/1/shot.png']);
    });

    test('a message with no files sends no attachments key', () async {
      signIn();

      await SupportRepository.instance.send('t-1', 'Just text');

      final call = api.calls.firstWhere((c) => c.path.endsWith('/messages'));
      final body = jsonDecode(jsonEncode(call.body)) as Map<String, dynamic>;
      expect(body.containsKey('attachments'), isFalse);
    });

    test('attachments come back off a message', () {
      final message = SupportMessage.fromJson(const {
        'id': 'm-1',
        'sender_type': 'support',
        'message': 'Here is the form',
        'attachments': ['u/1/a.pdf', 'u/1/b.png'],
      });

      expect(message.attachments, ['u/1/a.pdf', 'u/1/b.png']);
    });
  });

  group('the form', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const ContactSupportScreen()),
      );
      await tester.pumpAndSettle();
    }

    Future<void> reveal(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
    }

    /// Every field the form requires: name, email, category, subject and
    /// description.
    Future<void> fillForm(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).at(0), 'Rabi');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'rabi@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'Broken item');
      await tester.enterText(
        find.byType(TextFormField).at(3),
        'It arrived bent',
      );
      await tester.ensureVisible(find.text('Select a category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select a category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Order issues').last);
      await tester.pumpAndSettle();
    }

    testWidgets('says the limit and the types before anything is picked', (
      tester,
    ) async {
      signIn();
      await pump(tester);
      await reveal(tester, find.text('Attach File'));

      expect(
        find.textContaining('Max 10 MB'),
        findsOneWidget,
        reason: 'the ceiling is stated up front',
      );
      expect(find.textContaining('PDF'), findsOneWidget);
    });

    testWidgets('shows the name, kind and size of what was chosen', (
      tester,
    ) async {
      signIn();
      SupportAttachmentRepository.pickerOverride = () async => [
        _file('receipt.pdf', bytes: 2048),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();

      expect(find.text('receipt.pdf'), findsOneWidget);
      expect(find.text('PDF document • 2.0 KB'), findsOneWidget);
    });

    testWidgets('an unsupported pick is explained and not attached', (
      tester,
    ) async {
      signIn();
      SupportAttachmentRepository.pickerOverride = () async => [
        _file('virus.exe'),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('.exe files are not supported'),
        findsOneWidget,
      );
      expect(find.text('virus.exe'), findsNothing);
    });

    testWidgets('a good file survives a bad one in the same pick', (
      tester,
    ) async {
      // Picking a photograph and an oversized video should attach the
      // photograph, not throw both away.
      signIn();
      SupportAttachmentRepository.pickerOverride = () async => [
        _file('good.png'),
        _file('huge.png', bytes: 10485761),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();

      expect(find.text('good.png'), findsOneWidget);
      expect(find.textContaining('over the 10 MB limit'), findsOneWidget);
    });

    testWidgets('an image is previewed as itself, not as an icon', (
      tester,
    ) async {
      signIn();
      SupportAttachmentRepository.pickerOverride = () async => [
        _image('shot.png'),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
    });

    testWidgets('a document keeps an icon, having nothing to show', (
      tester,
    ) async {
      signIn();
      SupportAttachmentRepository.pickerOverride = () async => [
        _file('receipt.pdf'),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('tapping the thumbnail opens the whole picture', (
      tester,
    ) async {
      signIn();
      SupportAttachmentRepository.pickerOverride = () async => [
        _image('shot.png'),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('shot.png'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a file can be taken back off before sending', (tester) async {
      signIn();
      SupportAttachmentRepository.pickerOverride = () async => [
        _file('receipt.pdf'),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();
      expect(find.text('receipt.pdf'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove receipt.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('receipt.pdf'), findsNothing);
    });

    testWidgets('submitting sends the ticket, then the file on it', (
      tester,
    ) async {
      // Attachments live on messages: that is where the server keeps them and
      // the only place the admin ticket console renders them.
      signIn();
      SupportAttachmentRepository.pickerOverride = () async => [
        _file('receipt.pdf'),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();

      await fillForm(tester);
      await tester.ensureVisible(find.text('Submit Ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Ticket'));
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path.contains('/media/upload')),
        hasLength(1),
        reason: 'the file reached storage',
      );
      final message = api.calls.firstWhere((c) => c.path.endsWith('/messages'));
      final body = jsonDecode(jsonEncode(message.body)) as Map<String, dynamic>;
      expect(body['attachments'], ['u/1/shot.png']);
    });

    testWidgets('a failed upload keeps the ticket and offers a retry', (
      tester,
    ) async {
      // The ticket is already raised at this point. Reporting plain failure
      // would invite a second ticket for the same problem; reporting success
      // would say a file is with support when it is nowhere.
      signIn();
      api.on('POST', '/media/upload', status: 500, body: const {});
      SupportAttachmentRepository.pickerOverride = () async => [
        _file('receipt.pdf'),
      ];
      await pump(tester);
      await reveal(tester, find.text('Attach File'));
      await tester.tap(find.text('Attach File'));
      await tester.pumpAndSettle();

      await fillForm(tester);
      await tester.ensureVisible(find.text('Submit Ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Ticket'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Retry upload'));
      await tester.pumpAndSettle();
      expect(find.text('Retry upload'), findsOneWidget);
      expect(find.textContaining('TKT-1 was raised'), findsOneWidget);

      // Retrying must not raise a second ticket.
      api.on('POST', '/media/upload', body: {'key': 'u/1/shot.png'});
      await tester.tap(find.text('Retry upload'));
      await tester.pumpAndSettle();

      expect(
        api.calls.where(
          (c) => c.path == '/support/tickets' && c.method == 'POST',
        ),
        hasLength(1),
        reason: 'one ticket, not two',
      );
      final message = api.calls.firstWhere((c) => c.path.endsWith('/messages'));
      final body = jsonDecode(jsonEncode(message.body)) as Map<String, dynamic>;
      expect(body['attachments'], ['u/1/shot.png']);
    });

    testWidgets('a guest is told why they cannot attach', (tester) async {
      // The bucket is requires_auth, so the button would only fail.
      await pump(tester);
      await reveal(tester, find.text('Attach File'));

      expect(find.text('Sign in to attach files.'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Attach File'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/product/widgets/product_quote_sheet.dart';
import 'package:gtradea_amazon/features/quotes/data/quote_repository.dart';
import 'package:gtradea_amazon/features/support/data/support_attachment.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

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
    api.on('POST', '/product-requests', body: {'id': 'req-1'});
    api.on('POST', '/media/upload', body: {'key': 'u/1/shot.png'});
    api.on('POST', '/product-requests/req-1/messages', body: const {});
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    SupportAttachmentRepository.pickerOverride = null;
    clearApiStub();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ProductQuoteSheet(product: sampleDetail)),
      ),
    );
    await tester.pump();
  }

  Future<void> attach(WidgetTester tester, List<PickedAttachment> files) async {
    SupportAttachmentRepository.pickerOverride = () async => files;
    await tester.tap(find.text('Attach File'));
    await tester.pumpAndSettle();
  }

  group('attaching to a product query', () {
    testWidgets('the limit and the types are stated up front', (tester) async {
      signIn();
      await pump(tester);

      expect(find.text('Attach File'), findsOneWidget);
      expect(find.textContaining('Max 10 MB'), findsOneWidget);
      expect(find.textContaining('PDF'), findsOneWidget);
    });

    testWidgets('a chosen file shows its name, kind and size', (tester) async {
      signIn();
      await pump(tester);

      await attach(tester, [_file('spec.pdf', bytes: 2048)]);

      expect(find.text('spec.pdf'), findsOneWidget);
      expect(find.text('PDF document • 2.0 KB'), findsOneWidget);
    });

    testWidgets('an unsupported type is refused with a reason', (tester) async {
      signIn();
      await pump(tester);

      await attach(tester, [_file('macro.exe')]);

      expect(
        find.textContaining('.exe files are not supported'),
        findsOneWidget,
      );
      expect(find.text('macro.exe'), findsNothing);
    });

    testWidgets('an oversized file is refused with a reason', (tester) async {
      signIn();
      await pump(tester);

      await attach(tester, [_file('huge.png', bytes: 10485761)]);

      expect(find.textContaining('over the 10 MB limit'), findsOneWidget);
      expect(find.text('huge.png'), findsNothing);
    });

    testWidgets('a file can be taken off before sending', (tester) async {
      signIn();
      await pump(tester);
      await attach(tester, [_file('spec.pdf')]);
      expect(find.text('spec.pdf'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove spec.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('spec.pdf'), findsNothing);
    });

    testWidgets('a guest is told why they cannot attach', (tester) async {
      await pump(tester);

      expect(find.text('Sign in to attach files.'), findsOneWidget);
    });
  });

  group('sending the query with its files', () {
    testWidgets('the request is raised, then the file posted onto it', (
      tester,
    ) async {
      // Attachments live on the request's messages: that is where the server
      // keeps them and where the quote thread renders them.
      signIn();
      await pump(tester);
      await attach(tester, [_file('spec.pdf')]);

      await tester.enterText(find.byType(TextField).first, '500 pieces');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      final created = api.calls.where(
        (c) => c.path == '/product-requests' && c.method == 'POST',
      );
      expect(created, hasLength(1), reason: 'one request');
      expect(
        api.calls.where((c) => c.path.contains('/media/upload')),
        hasLength(1),
        reason: 'the file reached storage',
      );

      final message = api.calls.firstWhere((c) => c.path.endsWith('/messages'));
      final body = jsonDecode(jsonEncode(message.body)) as Map<String, dynamic>;
      expect(body['attachments'], ['u/1/shot.png']);
      expect(
        message.path,
        contains('req-1'),
        reason: 'onto the request just raised, not another',
      );
    });

    testWidgets('a query with no files posts no message at all', (
      tester,
    ) async {
      // The existing behaviour is untouched when nothing is attached.
      signIn();
      await pump(tester);

      await tester.enterText(find.byType(TextField).first, 'Just a question');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path.endsWith('/messages')),
        isEmpty,
        reason: 'nothing to attach, so nothing extra is sent',
      );
    });

    testWidgets('a failed upload keeps the request and offers a retry', (
      tester,
    ) async {
      // The request is already raised. Reporting plain failure would invite a
      // second one for the same product.
      signIn();
      api.on('POST', '/media/upload', status: 500, body: const {});
      await pump(tester);
      await attach(tester, [_file('spec.pdf')]);

      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text('Retry upload'), findsOneWidget);
      expect(find.textContaining('request was sent'), findsOneWidget);
      // The typed message is still there to send.
      expect(find.text('spec.pdf'), findsOneWidget);

      api.on('POST', '/media/upload', body: {'key': 'u/1/shot.png'});
      await tester.tap(find.text('Retry upload'));
      await tester.pumpAndSettle();

      expect(
        api.calls.where(
          (c) => c.path == '/product-requests' && c.method == 'POST',
        ),
        hasLength(1),
        reason: 'one request, not two',
      );
      final message = api.calls.firstWhere((c) => c.path.endsWith('/messages'));
      final body = jsonDecode(jsonEncode(message.body)) as Map<String, dynamic>;
      expect(body['attachments'], ['u/1/shot.png']);
    });

    test('an attachment-only message still carries words', () async {
      // A row with no text reads as a blank in the thread.
      signIn();

      await QuoteRepository.instance.sendMessage(
        'req-1',
        '',
        attachments: const ['u/1/shot.png'],
      );

      final message = api.calls.firstWhere((c) => c.path.endsWith('/messages'));
      final body = jsonDecode(jsonEncode(message.body)) as Map<String, dynamic>;
      expect(body['message'], '(attachment)');
    });
  });
}

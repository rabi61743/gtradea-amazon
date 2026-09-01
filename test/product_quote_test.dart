import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/product_quote_sheet.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

Future<void> _pumpPage(WidgetTester tester, {ProductDetail? detail}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(
        product: sampleProduct,
        detail: detail ?? sampleDetail,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// The app-bar action, which is where asking for a quote now lives.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Request a quote'));
  await tester.pumpAndSettle();
}

Finder get _messageField => find.descendant(
  of: find.byType(ProductQuoteSheet),
  matching: find.byType(TextField),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  testWidgets('the way in is an app-bar action, not a card on the page', (
    tester,
  ) async {
    await _pumpPage(tester);

    expect(find.byTooltip('Request a quote'), findsOneWidget);
    // The "Buying in bulk?" card that used to sit under the specification is
    // gone. This is an action about the product, so it belongs beside Save and
    // Share rather than in a block of its own halfway down a long page.
    expect(find.textContaining('Buying in bulk'), findsNothing);
  });

  testWidgets('a guest is told to sign in before typing anything out', (
    tester,
  ) async {
    // `/product-requests` is authenticated -- measured answering 401 without a
    // credential -- so the alternative is a rejection after the whole thing has
    // been written.
    await _pumpPage(tester);
    await tester.tap(find.byTooltip('Request a quote'));
    await tester.pump();

    expect(find.text('Sign in to request a quote'), findsOneWidget);
    expect(find.byType(ProductQuoteSheet), findsNothing);
  });

  testWidgets('the sheet asks for one thing and names the product', (
    tester,
  ) async {
    signInForTest();
    await _pumpPage(tester);
    await _openSheet(tester);

    expect(find.text('Request a quote'), findsWidgets);
    expect(find.text(sampleDetail.title), findsWidgets);
    // One box, and the quantity stepper is gone with the rest: the endpoint
    // carries no quantity field, so a stepper collected a number nothing
    // received.
    expect(_messageField, findsOneWidget);
    expect(
      find.text('Quantity, specs, or questions (optional)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Send request'), findsOneWidget);
  });

  testWidgets('sends the listing the seller needs to price it', (tester) async {
    signInForTest();
    api.on('POST', '/product-requests', body: {'id': 'req-9'});

    await _pumpPage(tester);
    await _openSheet(tester);
    await tester.enterText(_messageField, '500 pieces, custom label');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    final sent = api.calls.lastWhere((c) => c.path == '/product-requests');
    expect(sent.json['product_source_id'], sampleDetail.numIid);
    expect(sent.json['product_title'], sampleDetail.title);
    expect(sent.json['message'], contains('500 pieces'));
    // Closed, and the page says so.
    expect(find.byType(ProductQuoteSheet), findsNothing);
    expect(find.textContaining('Quote request sent'), findsOneWidget);
  });

  testWidgets('the chosen option travels with the request', (tester) async {
    signInForTest();
    api.on('POST', '/product-requests', body: {'id': 'req-9'});

    await _pumpPage(tester);
    await _openSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    // A seller quoting a colourway needs to know which one was being looked at,
    // and it is the part a shopper assumes was sent.
    final sent = api.calls.lastWhere((c) => c.path == '/product-requests');
    expect(sent.json['message'], contains('Red'));
  });

  testWidgets('an empty message is still a valid request', (tester) async {
    signInForTest();
    api.on('POST', '/product-requests', body: {'id': 'req-9'});

    await _pumpPage(tester);
    await _openSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    // "Price this for me" is a complete question. The box says it is optional,
    // so refusing an empty one would be refusing the common case.
    expect(api.calls.where((c) => c.path == '/product-requests'), hasLength(1));
  });

  testWidgets('a failed send keeps the sheet and what was typed', (
    tester,
  ) async {
    signInForTest();
    api.on(
      'POST',
      '/product-requests',
      status: 500,
      body: {'message': 'Could not reach the seller right now.'},
    );

    await _pumpPage(tester);
    await _openSheet(tester);
    await tester.enterText(_messageField, '40 pieces');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductQuoteSheet), findsOneWidget);
    expect(
      tester.widget<TextField>(_messageField).controller?.text,
      '40 pieces',
      reason: 'nothing should have to be typed twice',
    );
  });
}

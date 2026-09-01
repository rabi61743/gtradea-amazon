import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/legal/data/legal_blocks.dart';
import 'package:gtradea_amazon/features/legal/data/legal_page_repository.dart';
import 'package:gtradea_amazon/features/legal/presentation/legal_page_screen.dart';
import 'package:gtradea_amazon/features/legal/presentation/terms_policies_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// The shape the shop actually publishes, tags and all.
const _pages = [
  {
    'id': '1',
    'slug': 'terms',
    'title': 'Terms of Service',
    'content': '<h2>Terms</h2><p>Use the shop fairly.</p>',
  },
  {
    'id': '2',
    'slug': 'privacy',
    'title': 'Privacy Policy',
    'content': '<p>We keep your data.</p>',
  },
  {
    'id': '3',
    'slug': 'about',
    'title': 'About Us',
    'content': '<h2>About GtradeA</h2><p>We import things.</p>',
  },
  {
    'id': '4',
    'slug': 'careers',
    'title': 'Careers at Gtradea',
    'content': '<p>Come and work here.</p>',
  },
];

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LegalPageRepository.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/pages', body: _pages);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    LegalPageRepository.instance.resetForTest();
  });

  group('reading a written page', () {
    test('keeps the headings, paragraphs and bullets it was written with', () {
      // The point of this parser. The app's stripHtml flattens all of it into
      // one run of text, which is unreadable for a policy of any length.
      final blocks = legalBlocks(
        '<h1>Returns</h1><p>You have 7 days.</p>'
        '<ul><li>Unused goods</li><li>Original packaging</li></ul>'
        '<h3>Refunds</h3><p>Paid back to source.</p>',
      );

      expect(blocks.map((b) => b.kind), [
        LegalBlockKind.heading,
        LegalBlockKind.paragraph,
        LegalBlockKind.bullet,
        LegalBlockKind.bullet,
        LegalBlockKind.heading,
        LegalBlockKind.paragraph,
      ]);
      expect(blocks.first.text, 'Returns');
      expect(blocks.first.level, 1);
      expect(blocks[2].text, 'Unused goods');
      expect(blocks[4].level, 3);
    });

    test('inline markup stays with its paragraph', () {
      // Non-greedy matching, or a <strong> in the first paragraph swallows the
      // rest of the document.
      final blocks = legalBlocks(
        '<p>Read the <strong>whole</strong> thing.</p><p>Then agree.</p>',
      );

      expect(blocks.length, 2);
      expect(blocks.first.text, 'Read the whole thing.');
      expect(blocks.last.text, 'Then agree.');
    });

    test('entities are decoded rather than shown raw', () {
      final blocks = legalBlocks(
        '<p>Returns &amp; refunds &quot;policy&quot;</p>',
      );
      expect(blocks.single.text, 'Returns & refunds "policy"');
    });

    test('a page in tags this does not know is still shown', () {
      // Losing the formatting is acceptable; losing the words is not.
      final blocks = legalBlocks('Just some bare text.');
      expect(blocks.single.kind, LegalBlockKind.paragraph);
      expect(blocks.single.text, 'Just some bare text.');
    });

    test('an empty page is no blocks, not one empty one', () {
      expect(legalBlocks(''), isEmpty);
      expect(legalBlocks('<p></p>'), isEmpty);
    });
  });

  group('the pages the shop publishes', () {
    test('are read from the existing pages route', () async {
      final pages = await LegalPageRepository.instance.list();

      expect(api.calls.single.path, contains('/pages'));
      expect(pages.map((p) => p.slug), [
        'terms',
        'privacy',
        'about',
        'careers',
      ]);
      // The markup survives the trip, so the reader can lay it out.
      expect(pages.first.html, contains('<h2>'));
    });

    test('one read from the list costs no second request', () async {
      await LegalPageRepository.instance.list();
      final page = await LegalPageRepository.instance.bySlug('terms');

      expect(page.title, 'Terms of Service');
      expect(
        api.calls.where((c) => c.path.contains('/pages/terms')),
        isEmpty,
        reason: 'the list already carried it',
      );
    });
  });

  group('Terms and policies', () {
    testWidgets('lists the policies and leaves the rest out', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const TermsPoliciesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      // About has its own row on the account page; careers is company news.
      expect(find.text('About Us'), findsNothing);
      expect(find.text('Careers at Gtradea'), findsNothing);
    });

    testWidgets('opens the one that was tapped', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const TermsPoliciesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.text('We keep your data.'), findsOneWidget);
    });

    testWidgets('a failure offers a retry rather than an empty list', (
      tester,
    ) async {
      api.on('GET', '/pages', status: 500, body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap(const TermsPoliciesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('About', () {
    testWidgets('shows the shop own page, headings and all', (tester) async {
      api.on('GET', '/pages/about', body: _pages[2]);
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const LegalPageScreen(slug: 'about', title: 'About GTradeA')),
      );
      await tester.pumpAndSettle();

      expect(find.text('About GtradeA'), findsOneWidget);
      expect(find.text('We import things.'), findsOneWidget);
    });
  });
}

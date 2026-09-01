import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/help/data/help_content.dart';
import 'package:gtradea_amazon/features/help/data/help_repository.dart';
import 'package:gtradea_amazon/features/help/presentation/help_center_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

Widget _wrap() =>
    MaterialApp(theme: AppTheme.light, home: const HelpCenterScreen());

/// A tall window: the page is a long scroll and the default 600x800 leaves
/// everything below the toggle unbuilt.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

const _categories = [
  {
    'id': '1',
    'slug': 'orders',
    'name': 'Orders and delivery',
    'description': 'Tracking, changes and delays.',
    'icon': 'Package',
  },
  {
    'id': '2',
    'slug': 'developers',
    'name': 'Developer guides',
    'description': 'APIs and webhooks.',
    'icon': 'Code',
  },
];

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/help/categories', body: _categories);
    api.on('GET', '/help/articles', body: const []);
    api.on(
      'GET',
      '/site-settings/support_email',
      body: const {
        'setting_key': 'support_email',
        'setting_value': 'business@gtradea.com',
      },
    );
  });

  tearDown(() => ApiClient.overrideDio = null);

  group('the knowledge base', () {
    test('reads the topics the shop published', () async {
      final categories = await HelpRepository.instance.categories();

      expect(categories.map((c) => c.slug), ['orders', 'developers']);
      expect(categories.first.name, 'Orders and delivery');
      expect(categories.first.icon, 'Package');
    });

    test('a topic with no name is dropped rather than drawn blank', () async {
      api.on(
        'GET',
        '/help/categories',
        body: const [
          {'id': '1', 'slug': 'x'},
        ],
      );

      expect(await HelpRepository.instance.categories(), isEmpty);
    });

    test('an empty knowledge base is a list, not a crash', () async {
      // Measured against production: all three help endpoints answer `[]`
      // today, so this is the ordinary case rather than an edge one.
      api.on('GET', '/help/categories', body: const []);

      expect(await HelpRepository.instance.categories(), isEmpty);
    });

    test('the audience and the search reach the server', () async {
      await HelpRepository.instance.articles(
        search: 'refund',
        audience: HelpAudience.developer,
        limit: 20,
      );

      final sent = api.calls.single;
      expect(sent.query['search'], 'refund');
      expect(sent.query['audience'], 'developer');
      expect(sent.query['limit'], 20);
    });

    test('a blank search is left off rather than sent empty', () async {
      // `search=` matches nothing where an absent key matches everything.
      await HelpRepository.instance.articles(search: '   ');

      expect(api.calls.single.query.containsKey('search'), isFalse);
    });

    test('the support address is the shop own setting', () async {
      expect(
        await HelpRepository.instance.supportEmail(),
        'business@gtradea.com',
      );
    });

    test('an unset address is null, not an empty button', () async {
      api.on(
        'GET',
        '/site-settings/support_email',
        body: const {'setting_key': 'support_email', 'setting_value': ''},
      );

      expect(await HelpRepository.instance.supportEmail(), isNull);
    });
  });

  group('the audience shelves', () {
    const orders = HelpCategory(id: '1', slug: 'orders', name: 'Orders');
    const developers = HelpCategory(
      id: '2',
      slug: kDeveloperSlug,
      name: 'Developers',
    );

    test('a customer sees everything except the developer shelf', () {
      expect(
        categoriesFor(const [
          orders,
          developers,
        ], HelpAudience.user).map((c) => c.slug),
        ['orders'],
      );
    });

    test('a developer sees only it', () {
      expect(
        categoriesFor(const [
          orders,
          developers,
        ], HelpAudience.developer).map((c) => c.slug),
        [kDeveloperSlug],
      );
    });
  });

  group('the Help Center', () {
    testWidgets('opens on the search, the actions and the topics', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('How can we help you?'), findsOneWidget);
      expect(find.text('Track my order'), findsOneWidget);
      expect(find.text('Return an item'), findsOneWidget);
      expect(find.text('Payment issues'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('Browse by Topic'), findsOneWidget);
      // The shop's own topic, not an invented one.
      expect(find.text('Orders and delivery'), findsOneWidget);
    });

    testWidgets('there is no audience toggle', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text("I'm a Customer"), findsNothing);
      expect(find.text("I'm a Developer"), findsNothing);
    });

    testWidgets('the developer shelf stays out of a shopper page', (
      tester,
    ) async {
      // The toggle is gone, not the filter behind it: the gateway still holds
      // developer material and it has no business in a shopping app.
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Orders and delivery'), findsOneWidget);
      expect(find.text('Developer guides'), findsNothing);
    });

    testWidgets('the support address comes from the backend', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('business@gtradea.com'), findsOneWidget);
      expect(find.text('Submit a Ticket'), findsOneWidget);
    });

    testWidgets('an empty knowledge base says so rather than showing a gap', (
      tester,
    ) async {
      // What every shop with this backend sees today. A bare heading over
      // nothing reads as a broken page.
      api.on('GET', '/help/categories', body: const []);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Browse by Topic'), findsOneWidget);
      expect(
        find.textContaining('No help topics have been published'),
        findsOneWidget,
      );
      // And the way to a human is still there, which is the point of saying it.
      expect(find.text('Submit a Ticket'), findsOneWidget);
    });

    testWidgets('a search asks the server and reports an empty answer', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'refund');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      final search = api.calls.where((c) => c.path.contains('/help/articles'));
      expect(search, isNotEmpty);
      expect(search.last.query['search'], 'refund');
      expect(find.textContaining('Nothing found'), findsOneWidget);
    });

    testWidgets('a topic opens what is filed under it', (tester) async {
      api.on(
        'GET',
        '/help/articles',
        body: const [
          {
            'id': 'a1',
            'slug': 'where-is-my-order',
            'title': 'Where is my order?',
            'summary': 'Tracking a parcel.',
          },
        ],
      );
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Orders and delivery'));
      await tester.pumpAndSettle();

      expect(find.text('Where is my order?'), findsOneWidget);
      final sent = api.calls.last;
      expect(sent.query['category_slug'], 'orders');
    });

    testWidgets('a topic failure offers a retry rather than an empty page', (
      tester,
    ) async {
      api.on('GET', '/help/categories', status: 500, body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Submit a Ticket'), findsOneWidget);
    });
  });
}

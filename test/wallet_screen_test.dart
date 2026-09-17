import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/home/widgets/product_rail.dart'
    show formatGrouped;
import 'package:gtradea_amazon/features/wallet/data/coin_balance_store.dart';
import 'package:gtradea_amazon/features/wallet/presentation/wallet_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

late FakeApi api;

Widget _wrap() =>
    MaterialApp(theme: AppTheme.light, home: const WalletScreen());

Map<String, dynamic> _entry(
  int i, {
  num amount = 100,
  String? status,
  String? order,
}) => {
  'id': 't$i',
  'amount': amount,
  'description': 'Movement $i',
  'created_at': '2026-09-0${(i % 9) + 1}T10:00:00Z',
  'status': ?status,
  'order_number': ?order,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    AuthStore.instance.resetForTest();
    CoinBalanceStore.instance.resetForTest();
    CoinBalanceStore.instance.bindToAuth();
  });

  tearDown(clearApiStub);

  group('the coins page', () {
    testWidgets('shows the account balance, counted rather than priced', (
      tester,
    ) async {
      // The bug this pins: the page printed the balance through the rupee
      // formatter, so a thousand coins read "Rs. 1,000" -- a different claim
      // about a different thing.
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 2450});
      api.on('GET', '/wallet/transactions', body: const {'transactions': []});

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('2,450'), findsOneWidget);
      expect(find.text('My Coins'), findsOneWidget);
      // The balance itself, named exactly. This was once a blanket "no 'Rs.'
      // anywhere on the page", which was the right rule aimed at the wrong
      // scope: the placeholder rewards below quote real discounts in rupees,
      // which is what a reward worth Rs. 100 is actually denominated in. What
      // must never be priced is the coin balance.
      expect(find.text('Rs. 2,450'), findsNothing);
    });

    testWidgets('lists the real movements the server reported', (tester) async {
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 2450});
      api.on(
        'GET',
        '/wallet/transactions',
        body: {
          'transactions': [
            _entry(1, amount: 500, status: 'Completed', order: 'GT-1001'),
            _entry(2, amount: -120),
          ],
        },
      );

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Movement 1'), findsOneWidget);
      expect(find.text('+500'), findsOneWidget);
      expect(find.text('-120'), findsOneWidget);

      // The status and the order are the server's, and they are shown because
      // it sent them -- the second movement carries neither and gets neither.
      expect(find.textContaining('Order GT-1001'), findsOneWidget);
      expect(find.textContaining('Completed'), findsOneWidget);
    });

    testWidgets('reveals history a page at a time rather than all at once', (
      tester,
    ) async {
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 2450});
      api.on(
        'GET',
        '/wallet/transactions',
        body: {
          'transactions': [for (var i = 1; i <= 25; i++) _entry(i)],
        },
      );

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Movement 1'), findsOneWidget);
      expect(find.text('Movement 11'), findsNothing);

      // Scrolled to first: ten rows put the button below the fold on the
      // default test viewport, and a tap on an off-screen widget never lands.
      final more = find.textContaining('Show more');
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(find.text('Movement 11'), findsOneWidget);
    });

    testWidgets('says so when the history could not be read', (tester) async {
      // It used to fall back to an empty list on any failure, so a history that
      // could not be loaded looked exactly like an account that had never
      // earned anything.
      signInForTest();
      ApiClient.overrideDio = api.dio();
      api.on('GET', '/wallet', body: const {'balance': 2450});
      api.on(
        'GET',
        '/wallet/transactions',
        status: 500,
        body: const {'error': 'Wallet history is unavailable.'},
      );

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Nothing has moved in or out yet.'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      // And the balance is still on screen: one section failing does not take
      // the figure the shopper came for with it.
      expect(find.text('2,450'), findsOneWidget);
    });

    testWidgets('an account with no movements says that plainly', (
      tester,
    ) async {
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 0});
      api.on('GET', '/wallet/transactions', body: const {'transactions': []});

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Nothing has moved in or out yet.'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('a guest is asked to sign in, not shown a stand-in', (
      tester,
    ) async {
      // The fallback figure belongs in the header chip, where it stands for
      // "not known yet". On the page about the balance it would be a claim.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(
        find.text(formatGrouped(CoinBalanceStore.fallbackBalance)),
        findsNothing,
      );
      expect(
        api.calls.where((c) => c.path == '/wallet'),
        isEmpty,
        reason: 'a guest has no wallet to ask about',
      );
    });

    testWidgets('the redesigned page: rewards, learn more, banner', (
      tester,
    ) async {
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 1000});
      api.on('GET', '/wallet/transactions', body: const {'transactions': []});
      tester.view.physicalSize = const Size(412 * 2, 2400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('coins-balance-card')), findsOneWidget);
      expect(find.text('Your Coins'), findsOneWidget);
      expect(find.text('≈ NPR 100'), findsOneWidget);
      expect(find.text('Redeem Your Coins'), findsOneWidget);
      for (final name in [
        'Rs. 100 Off',
        'Free Delivery',
        'Rs. 250 Off',
        'Product Voucher',
        'Exclusive Brand Deals',
        'Partner Store Voucher',
        'Cashback',
        'Premium Gift',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.byKey(const ValueKey('coins-bottom-banner')), findsOneWidget);

      // A reward never pretends to redeem.
      await tester.tap(find.byKey(const ValueKey('reward-Cashback')));
      await tester.pump();
      expect(
        find.text('Redeeming coins is not available yet.'),
        findsOneWidget,
      );
      expect(find.text('1,000'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('coins-learn-more')));
      await tester.pumpAndSettle();
      expect(find.text('How coins work'), findsOneWidget);
    });

    testWidgets('lays out on a phone, a tablet and a desktop window', (
      tester,
    ) async {
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 2450});
      api.on(
        'GET',
        '/wallet/transactions',
        body: {
          'transactions': [for (var i = 1; i <= 3; i++) _entry(i)],
        },
      );

      for (final width in [320.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width * 2, 1600);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: '${width}dp');
        expect(find.text('2,450'), findsOneWidget, reason: '${width}dp');
        expect(find.text('Movement 1'), findsOneWidget, reason: '${width}dp');
      }
    });
  });
}

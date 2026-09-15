import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/address/presentation/delivery_location_button.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/support/presentation/support_button.dart';
import 'package:gtradea_amazon/features/support/presentation/support_tickets_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/product_rail.dart'
    show formatGrouped;
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notifications_screen.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_tracker_button.dart';
import 'package:gtradea_amazon/features/wallet/data/coin_balance_store.dart';
import 'package:gtradea_amazon/features/wallet/presentation/coin_balance_button.dart';
import 'package:gtradea_amazon/features/wallet/presentation/wallet_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

late FakeApi api;

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpHeader(WidgetTester tester) async {
  _phone(tester);
  await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
  // Settled, not pumped once: a signed-in header fetches the coin balance on
  // its first frame.
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    AuthStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    CoinBalanceStore.instance.resetForTest();
    CoinBalanceStore.instance.bindToAuth();
  });

  tearDown(clearApiStub);

  group('the chrome row', () {
    testWidgets('groups where the parcel goes apart from where to go', (
      tester,
    ) async {
      // Two blocks: what this account is (address, coins) on the left, and
      // three destinations on the right. The reference draws them as separate
      // rounded fields, and the split is the point -- one side answers a
      // question, the other side takes you somewhere.
      await _pumpHeader(tester);

      final address = tester.getRect(find.byType(DeliveryLocationButton));
      final orders = tester.getRect(find.byType(OrderTrackerButton));

      expect(address.right, lessThanOrEqualTo(orders.left));
    });

    testWidgets('the third action is messages, not the cart', (tester) async {
      // Swapped by request. The cart is still on the bottom bar and still the
      // same count from the same store -- it is this slot in the header that
      // now belongs to messages.
      CartStore.instance.add(
        const CartLine(
          productId: 'p-1',
          title: 'Quick-drying polo',
          unitPrice: 554,
          quantity: 2,
        ),
      );

      await _pumpHeader(tester);

      expect(find.byType(SupportButton), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byIcon(Icons.shopping_cart), findsNothing);
      expect(find.byIcon(Icons.shopping_cart_outlined), findsNothing);
      // And no count where the cart's used to be: this endpoint has no unread
      // figure, so there is nothing honest to badge.
      expect(find.text('2'), findsNothing);
    });

    testWidgets('and it opens the conversations', (tester) async {
      signInForTest();
      api.on('GET', '/support/tickets', body: const []);

      await _pumpHeader(tester);

      await tester.tap(find.byType(SupportButton));
      await tester.pumpAndSettle();

      expect(find.byType(SupportTicketsScreen), findsOneWidget);
    });
  });

  group('the coin chip', () {
    testWidgets('shows the account balance the server reports', (tester) async {
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 2450});

      await _pumpHeader(tester);

      // The figure is the server's, grouped the way every other figure in the
      // app is but without the `Rs.`: the coin beside it says what it counts,
      // and the prefix cost the address the room it needs to name a place.
      // The wallet screen this opens still prints the full rupee formatting.
      expect(find.text('2,450'), findsOneWidget);
      expect(find.byType(CoinBalanceButton), findsOneWidget);
    });

    testWidgets('opens the same wallet the balance came from', (tester) async {
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 2450});
      api.on('GET', '/wallet/transactions', body: const {'transactions': []});

      await _pumpHeader(tester);
      await tester.tap(find.byType(CoinBalanceButton));
      await tester.pumpAndSettle();

      expect(find.byType(WalletScreen), findsOneWidget);
    });

    testWidgets('falls back rather than vanishing for a guest', (tester) async {
      // This used to assert the opposite: no chip at all for a guest, on the
      // grounds that a zero reads as "you have none" rather than "you are not
      // signed in". The balance now falls back to a stated figure instead of
      // going quiet -- by request -- so the chip is always there and always
      // has something in it. The old rule is recorded here rather than
      // deleted, because it was a deliberate choice and this reverses it.
      await _pumpHeader(tester);

      expect(find.byType(CoinBalanceButton), findsOneWidget);
      expect(
        find.text(formatGrouped(CoinBalanceStore.fallbackBalance)),
        findsOneWidget,
        reason: 'the stand-in figure, not a blank',
      );
    });

    testWidgets('and the server figure beats the fallback', (tester) async {
      // The half of this that matters: the fallback is for when there is no
      // answer, never instead of one. A real balance must win the moment it
      // lands, or the chip is decoration.
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 2450});

      await _pumpHeader(tester);

      expect(find.text('2,450'), findsOneWidget);
      expect(
        find.text(formatGrouped(CoinBalanceStore.fallbackBalance)),
        findsNothing,
        reason: 'the stand-in is gone once the server has spoken',
      );
      expect(CoinBalanceStore.instance.fetchedBalance, 2450);
    });

    testWidgets('a guest is never asked about, but still sees the chip', (
      tester,
    ) async {
      // The store short-circuits before the repository for a signed-out
      // shopper, so nothing is fetched -- and the chip draws the stand-in
      // rather than disappearing, which is the change from the old rule.
      await _pumpHeader(tester);

      expect(
        api.calls.where((c) => c.path == '/wallet'),
        isEmpty,
        reason: 'a guest has no wallet to ask about',
      );
      expect(find.byType(CoinBalanceButton), findsOneWidget);
    });

    testWidgets('a failed read still shows the stand-in', (tester) async {
      // Blanking on failure was tried and reverted: this account's `/wallet`
      // is refused by the server, so the chip disappeared on the very device
      // the balance had to be visible on.
      //
      // The trade is real and recorded here rather than hidden -- a signed-in
      // shopper whose balance cannot be read sees the stand-in rather than
      // their own figure. `fetchedBalance` and `readFailed` are what tell the
      // two apart for anything that needs to.
      signInForTest();
      ApiClient.overrideDio = api.dio();
      api.on('GET', '/wallet', status: 500, body: const {});

      await _pumpHeader(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(CoinBalanceButton), findsOneWidget);
      expect(
        CoinBalanceStore.instance.fetchedBalance,
        isNull,
        reason: 'nothing real was read, and the store still says so',
      );
      expect(CoinBalanceStore.instance.readFailed, isTrue);
    });

    testWidgets('leaves the address the room it needs beside it', (
      tester,
    ) async {
      // The bug this guards: the chip took a share of the block whether or not
      // it had anything in it, and the delivery line read "Deliv / Ja...".
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 2450});
      AddressStore.instance.add(
        label: AddressLabel.home,
        fullName: 'Rabi',
        phone: '9800000000',
        province: 'Bagmati',
        city: 'Lalitpur',
        area: 'Jawalakhel',
        makeDefault: true,
      );

      await _pumpHeader(tester);

      final chip = tester.getRect(find.byType(CoinBalanceButton));

      // The chip is capped, so what is left of the block belongs to the
      // address -- and the address names the city rather than a line cut off
      // mid-word.
      expect(chip.width, lessThanOrEqualTo(112));
      expect(find.text('Lalitpur'), findsOneWidget);
      expect(find.text('Jawalakhel, Lalitpur, Bagmati'), findsNothing);
    });

    testWidgets('a zero balance is still the truth, and is shown', (
      tester,
    ) async {
      // Nothing invented in either direction: the server said zero, so the
      // chip says zero rather than hiding what the account actually holds --
      // and rather than falling back to the stand-in, which would turn a real
      // empty balance into a made-up one.
      signInForTest();
      api.on('GET', '/wallet', body: const {'balance': 0});

      await _pumpHeader(tester);

      expect(find.text('0'), findsOneWidget);
      expect(CoinBalanceStore.instance.fetchedBalance, 0);
    });
  });

  group('the labels', () {
    testWidgets('name every action in the group', (tester) async {
      await _pumpHeader(tester);

      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Cart'), findsNothing, reason: 'the slot it took over');
    });

    testWidgets('and the destinations behind them did not change', (
      tester,
    ) async {
      await _pumpHeader(tester);

      await tester.tap(find.byType(NotificationBell));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../account/presentation/account_screen.dart';
import '../address/data/address_store.dart';
import '../auth/data/auth_store.dart';
import '../cart/data/cart_store.dart';
import '../cart/presentation/cart_screen.dart';
import '../catalog/data/catalog_store.dart';
import '../catalog/presentation/browse_screen.dart';
import '../notifications/data/notification_store.dart';
import '../orders/data/order_store.dart';
import '../promo/data/coupon_store.dart';
import '../search/presentation/search_entry_screen.dart';
import '../wishlist/data/wishlist_store.dart';
import '../wishlist/presentation/wishlist_screen.dart';
import 'home_feed.dart';
import 'widgets/search_header.dart';

/// Storefront home: pinned search, a promo strip, then alternating category
/// blocks, a recommendation rail and the full department grid.
///
/// Content comes from [HomeContent]; this widget only decides the order and
/// the furniture around it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  @override
  void initState() {
    super.initState();
    WishlistStore.instance.load();
    LanguageStore.instance.load();
    AuthStore.instance.load();
    // Bound before the load so a sign-in that lands mid-startup still moves
    // the cart to the right identity.
    CartStore.instance.bindToAuth();
    CouponStore.instance.bindToAuth();
    CouponStore.instance.load();
    OrderStore.instance.bindToAuth();
    NotificationStore.instance.bindToAuth();
    AddressStore.instance.bindToAuth();
    AddressStore.instance.load();
    OrderStore.instance.load();
    CartStore.instance.load();

    // The feed catches up at startup: orders progress on a clock, so anything
    // that happened while the app was closed still has to be announced.
    unawaited(_catchUpNotifications());

    // Sign-in and sign-out are the account events worth telling someone about,
    // and this is the one place that watches identity for the whole app.
    AuthStore.instance.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final account = AuthStore.instance.account;
    if (account == null) return;
    NotificationStore.instance.recordAccountEvent(
      // Keyed on the session so signing in again later is a new entry, but a
      // rebuild is not.
      id: 'signin:${account.email}:${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
      title: 'Signed in',
      body: 'You are signed in as ${account.email}.',
    );
  }

  Future<void> _catchUpNotifications() async {
    await NotificationSettings.instance.load();
    await NotificationStore.instance.load();
    await OrderStore.instance.load();
    if (!mounted) return;

    NotificationStore.instance.syncFromOrders(OrderStore.instance.orders);

    // Campaigns the storefront is actually running: the same banners the feed
    // shows, which an admin set and which expire on their own.
    await CatalogStore.instance.banners.load();
    if (!mounted) return;
    for (final banner in CatalogStore.instance.banners.value ?? const []) {
      if (banner.promoCode == null) continue;
      NotificationStore.instance.recordPromotion(
        id: banner.id,
        title: banner.title,
        body: banner.subtitle ??
            'Use code  at checkout.',
      );
    }
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }


  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchEntryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Outside the scroll view on purpose: search stays reachable no
          // matter how far down the feed the customer is.
          SearchHeader(
            onTap: () => _openSearch(context),
            onImageSearch: () => _openSearch(context),
          ),
          const Expanded(child: HomeFeed()),
        ],
      ),
      // Listening to both stores: the saved badge and the account wording each
      // have to change the moment their store does, without waiting for a
      // navigation to rebuild the bar.
      bottomNavigationBar: ListenableBuilder(
        listenable: Listenable.merge([
          WishlistStore.instance,
          AuthStore.instance,
          CartStore.instance,
          LanguageStore.instance,
        ]),
        // Home is the shell and every other destination opens on top of it, so
        // the selected index is always Home. The bar is a row of shortcuts
        // rather than a tab controller; tracking a selection would leave a
        // destination highlighted for a page that had since been popped.
        builder: (context, _) => AppBottomNav(
          currentIndex: 0,
          strings: LanguageStore.instance.strings,
          savedCount: WishlistStore.instance.count,
          cartCount: CartStore.instance.count,
          isSignedIn: AuthStore.instance.isSignedIn,
          onSelected: (i) => switch (i) {
            1 => _openPage(context, const WishlistScreen()),
            2 => _openPage(context, const AccountScreen()),
            3 => _openPage(context, const CartScreen()),
            4 => _openPage(context, const BrowseScreen()),
            _ => null,
          },
        ),
      ),
    );
  }
}

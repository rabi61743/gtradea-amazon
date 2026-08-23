import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../account/presentation/account_screen.dart';
import '../address/data/address_store.dart';
import '../auth/data/auth_store.dart';
import '../cart/data/cart_store.dart';
import '../cart/presentation/cart_screen.dart';
import '../catalog/presentation/browse_screen.dart';
import '../notifications/data/notification_store.dart';
import '../orders/data/order_store.dart';
import '../search/presentation/search_entry_screen.dart';
import '../wishlist/data/wishlist_store.dart';
import '../wishlist/presentation/wishlist_screen.dart';
import 'home_content.dart';
import 'widgets/category_section.dart';
import 'widgets/deal_group.dart';
import 'widgets/hero_banner.dart';
import 'widgets/department_grid.dart';
import 'widgets/product_rail.dart';
import 'widgets/promo_rail.dart';
import 'widgets/search_header.dart';
import 'widgets/spotlight_rail.dart';

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
    // Offers the storefront is actually running, rather than invented ones:
    // these are the same promos the home feed shows.
    for (final promo in HomeContent.promos) {
      NotificationStore.instance.recordPromotion(
        id: promo.headline,
        title: promo.headline,
        body: promo.caption,
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const SizedBox(height: 14),
                const HeroBanner(items: HomeContent.banners),
                const PromoRail(items: HomeContent.promos),
                CategorySection(
                  title: 'Electronics',
                  leadingIcon: Icons.memory,
                  entries: HomeContent.electronics,
                  onSeeAll: () {},
                ),
                ProductRail(
                  title: 'Recommended for you',
                  leadingIcon: Icons.auto_awesome,
                  items: HomeContent.topPicks,
                  onSeeAll: () {},
                ),
                SpotlightRail(
                  title: 'Featured brands',
                  leadingIcon: Icons.local_offer,
                  items: HomeContent.spotlight,
                  onSeeAll: () {},
                ),
                CategorySection(
                  title: 'Computing',
                  leadingIcon: Icons.laptop_chromebook,
                  entries: HomeContent.computing,
                  onSeeAll: () {},
                ),
                CategorySection(
                  title: 'Gaming gear',
                  leadingIcon: Icons.sports_esports,
                  entries: HomeContent.gaming,
                  onSeeAll: () {},
                ),
                DealGroup(
                  title: 'Also popular',
                  subtitle: 'What other shoppers are browsing',
                  items: HomeContent.alsoPopular,
                  tint: const Color(0xFFF59E0B),
                ),
                CategorySection(
                  title: 'Home and living',
                  leadingIcon: Icons.chair,
                  entries: HomeContent.homeGoods,
                  onSeeAll: () {},
                ),
                // A price cap is the point of this block, so it belongs in the
                // header rather than buried in the tiles. In rupees, because
                // this storefront sells in NPR.
                CategorySection(
                  title: 'Shoes',
                  subtitle: 'Under Rs. 5,000',
                  leadingIcon: Icons.checkroom,
                  entries: HomeContent.shoes,
                  onSeeAll: () {},
                ),
                CategorySection(
                  title: 'For your pets',
                  leadingIcon: Icons.pets,
                  entries: HomeContent.pets,
                  onSeeAll: () {},
                ),
                CategorySection(
                  title: 'Family and toys',
                  leadingIcon: Icons.family_restroom,
                  entries: HomeContent.family,
                  onSeeAll: () {},
                ),
                DealGroup(
                  title: 'Dashain specials',
                  subtitle: 'Gifting picks for the season',
                  items: HomeContent.festival,
                  tint: const Color(0xFFE84326),
                ),
                DepartmentGrid(
                  title: 'Shop by category',
                  leadingIcon: Icons.grid_view,
                  entries: HomeContent.departments,
                  // The full tree, rather than a link that goes nowhere.
                  onSeeAll: () => _openPage(context, const BrowseScreen()),
                ),
              ],
            ),
          ),
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

import 'package:flutter/material.dart';

import '../../shared/widgets/app_bottom_nav.dart';
import '../account/presentation/account_screen.dart';
import '../auth/data/auth_store.dart';
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
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WishlistStore.instance.load();
    AuthStore.instance.load();
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
                  onSeeAll: () {},
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
        ]),
        builder: (context, _) => AppBottomNav(
          currentIndex: _tab,
          savedCount: WishlistStore.instance.count,
          isSignedIn: AuthStore.instance.isSignedIn,
          onSelected: (i) {
            // Saved and Account are pages, not tabs this shell hosts, so they
            // open on top and the nav selection stays where it was.
            if (i == 1) {
              _openPage(context, const WishlistScreen());
              return;
            }
            if (i == 2) {
              _openPage(context, const AccountScreen());
              return;
            }
            setState(() => _tab = i);
          },
        ),
      ),
    );
  }
}

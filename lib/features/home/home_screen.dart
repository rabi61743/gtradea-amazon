import 'package:flutter/material.dart';

import '../../shared/widgets/app_bottom_nav.dart';
import 'home_content.dart';
import 'widgets/category_section.dart';
import 'widgets/department_grid.dart';
import 'widgets/product_rail.dart';
import 'widgets/promo_rail.dart';
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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Outside the scroll view on purpose: search stays reachable no
          // matter how far down the feed the customer is.
          SearchHeader(onTap: () {}, onImageSearch: () {}),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
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
      bottomNavigationBar: AppBottomNav(
        currentIndex: _tab,
        onSelected: (i) => setState(() => _tab = i),
      ),
    );
  }
}

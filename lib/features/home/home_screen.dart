import 'package:flutter/material.dart';

import '../../shared/widgets/app_bottom_nav.dart';
import 'widgets/category_section.dart';
import 'widgets/promo_rail.dart';
import 'widgets/search_header.dart';

/// Storefront home: pinned search, a promo strip, then category blocks.
///
/// The content is hardcoded placeholder data. It exists to fix the layout and
/// the visual language; swapping it for API results should not move any of
/// this widget's structure.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _promos = [
    PromoItem(
      headline: 'Up to 40% off',
      caption: 'Everyday electronics, this week only',
      tint: Color(0xFFF97316),
    ),
    PromoItem(
      headline: 'Free delivery',
      caption: 'On hand-picked items across Nepal',
      tint: Color(0xFF0EA5E9),
    ),
    PromoItem(
      headline: 'New arrivals',
      caption: 'Fresh stock added daily',
      tint: Color(0xFF059669),
    ),
  ];

  static const _electronics = [
    CategoryEntry(
      label: 'Headphones',
      icon: Icons.headphones,
      tint: Color(0xFF6366F1),
    ),
    CategoryEntry(
      label: 'Tablets',
      icon: Icons.tablet_mac,
      tint: Color(0xFF0EA5E9),
    ),
    CategoryEntry(
      label: 'Gaming',
      icon: Icons.sports_esports,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Speakers',
      icon: Icons.speaker,
      tint: Color(0xFFF97316),
    ),
  ];

  static const _computing = [
    CategoryEntry(
      label: 'Desktops',
      icon: Icons.desktop_windows,
      tint: Color(0xFF0891B2),
    ),
    CategoryEntry(
      label: 'Laptops',
      icon: Icons.laptop_mac,
      tint: Color(0xFF2563EB),
    ),
    CategoryEntry(
      label: 'Monitors',
      icon: Icons.monitor,
      tint: Color(0xFF059669),
    ),
    CategoryEntry(
      label: 'Accessories',
      icon: Icons.keyboard,
      tint: Color(0xFFE84326),
    ),
  ];

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
                const PromoRail(items: _promos),
                CategorySection(
                  title: 'Plug in with our electronics',
                  entries: _electronics,
                  onShopMore: () {},
                ),
                CategorySection(
                  title: 'Score the top PCs & accessories',
                  entries: _computing,
                  onShopMore: () {},
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

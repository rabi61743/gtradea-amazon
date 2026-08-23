import 'package:flutter/material.dart';

import '../../shared/widgets/app_bottom_nav.dart';
import 'widgets/category_section.dart';
import 'widgets/department_grid.dart';
import 'widgets/product_rail.dart';
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

  static const _topPicks = [
    ProductItem(
      title: 'Wireless over-ear headphones, 40h battery',
      price: 8990,
      listPrice: 12500,
      rating: 4.5,
      reviewCount: 128,
      icon: Icons.headphones,
      tint: Color(0xFF6366F1),
    ),
    ProductItem(
      title: 'Portable bluetooth speaker, waterproof',
      price: 4250,
      listPrice: 5600,
      rating: 4.0,
      reviewCount: 64,
      icon: Icons.speaker,
      tint: Color(0xFFF97316),
    ),
    ProductItem(
      title: 'Mechanical keyboard, hot-swappable switches',
      price: 6750,
      rating: 5.0,
      reviewCount: 12,
      icon: Icons.keyboard,
      tint: Color(0xFFE84326),
    ),
    ProductItem(
      title: '10-inch tablet with folio case',
      price: 21900,
      listPrice: 24500,
      rating: 3.5,
      reviewCount: 41,
      icon: Icons.tablet_mac,
      tint: Color(0xFF0EA5E9),
    ),
  ];

  static const _departments = [
    DepartmentEntry(label: 'Beauty', icon: Icons.brush, tint: Color(0xFFEC4899)),
    DepartmentEntry(
      label: 'Home and kitchen',
      icon: Icons.chair,
      tint: Color(0xFF0891B2),
    ),
    DepartmentEntry(
      label: 'Sports and outdoors',
      icon: Icons.sports_baseball,
      tint: Color(0xFF059669),
    ),
    DepartmentEntry(
      label: 'Electronics',
      icon: Icons.memory,
      tint: Color(0xFF6366F1),
    ),
    DepartmentEntry(
      label: 'Outdoor clothing',
      icon: Icons.backpack,
      tint: Color(0xFFF59E0B),
    ),
    DepartmentEntry(
      label: 'Pet supplies',
      icon: Icons.pets,
      tint: Color(0xFFA855F7),
    ),
  ];

  static const _homeGoods = [
    CategoryEntry(label: 'Bedsheets', icon: Icons.bed, tint: Color(0xFF0891B2)),
    CategoryEntry(
      label: 'Pillows',
      icon: Icons.airline_seat_individual_suite,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Duvet covers',
      icon: Icons.king_bed,
      tint: Color(0xFFF59E0B),
    ),
    CategoryEntry(
      label: 'Throws and blankets',
      icon: Icons.dry_cleaning,
      tint: Color(0xFF059669),
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
                  title: 'Electronics',
                  leadingIcon: Icons.memory,
                  entries: _electronics,
                  onSeeAll: () {},
                ),
                ProductRail(
                  title: 'Recommended for you',
                  leadingIcon: Icons.auto_awesome,
                  items: _topPicks,
                  onSeeAll: () {},
                ),
                CategorySection(
                  title: 'Computing',
                  leadingIcon: Icons.laptop_chromebook,
                  entries: _computing,
                  onSeeAll: () {},
                ),
                CategorySection(
                  title: 'Home and living',
                  leadingIcon: Icons.chair,
                  entries: _homeGoods,
                  onSeeAll: () {},
                ),
                DepartmentGrid(
                  title: 'Shop by category',
                  leadingIcon: Icons.grid_view,
                  entries: _departments,
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

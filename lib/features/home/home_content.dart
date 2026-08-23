import 'package:flutter/material.dart';

import 'widgets/category_section.dart';
import 'widgets/department_grid.dart';
import 'widgets/deal_group.dart';
import 'widgets/promo_rail.dart';
import 'widgets/spotlight_rail.dart';
import 'widgets/product_rail.dart';

/// Placeholder content for the home feed.
///
/// Split out of the screen so the widget stays about layout. Every list here is
/// stand-in data with the same shape an API would return, so wiring a backend
/// later replaces this file and touches nothing else.
class HomeContent {
  HomeContent._();

  static const promos = [
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

  static const electronics = [
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

  static const computing = [
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

  static const homeGoods = [
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

  /// Generic console categories rather than brand names: this is placeholder
  /// data, and naming a manufacturer implies stock we have not modelled.
  static const gaming = [
    CategoryEntry(
      label: 'Controllers',
      icon: Icons.sports_esports,
      tint: Color(0xFF6366F1),
    ),
    CategoryEntry(
      label: 'Handhelds',
      icon: Icons.videogame_asset,
      tint: Color(0xFFE84326),
    ),
    CategoryEntry(
      label: 'VR headsets',
      icon: Icons.vrpano,
      tint: Color(0xFF0891B2),
    ),
    CategoryEntry(
      label: 'Console accessories',
      icon: Icons.cable,
      tint: Color(0xFFF59E0B),
    ),
  ];

  static const family = [
    CategoryEntry(
      label: 'Outdoor play',
      icon: Icons.park,
      tint: Color(0xFF059669),
    ),
    CategoryEntry(
      label: 'Building blocks',
      icon: Icons.extension,
      tint: Color(0xFFF97316),
    ),
    CategoryEntry(
      label: 'Board games',
      icon: Icons.casino,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Learning toys',
      icon: Icons.school,
      tint: Color(0xFF0EA5E9),
    ),
  ];

  static const shoes = [
    CategoryEntry(
      label: "Women's",
      icon: Icons.woman,
      tint: Color(0xFFEC4899),
    ),
    CategoryEntry(label: "Men's", icon: Icons.man, tint: Color(0xFF2563EB)),
    CategoryEntry(
      label: "Girls'",
      icon: Icons.child_care,
      tint: Color(0xFF059669),
    ),
    CategoryEntry(
      label: "Boys'",
      icon: Icons.child_friendly,
      tint: Color(0xFF0EA5E9),
    ),
  ];

  static const pets = [
    CategoryEntry(label: 'Dog supplies', icon: Icons.pets, tint: Color(0xFFF59E0B)),
    CategoryEntry(
      label: 'Cat supplies',
      icon: Icons.cruelty_free,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Grooming',
      icon: Icons.content_cut,
      tint: Color(0xFF0891B2),
    ),
    CategoryEntry(
      label: 'Beds and crates',
      icon: Icons.night_shelter,
      tint: Color(0xFF059669),
    ),
  ];

  static const departments = [
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

  static const topPicks = [
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

  /// Price bands, not prices: these are marketing framings and are stored as
  /// written rather than run through formatRupees.
  static const alsoPopular = [
    DealItem(
      label: 'Water bottles and flasks',
      teaser: 'From Rs. 350',
      icon: Icons.local_drink,
      tint: Color(0xFF0891B2),
    ),
    DealItem(
      label: 'Vehicle lighting',
      teaser: 'From Rs. 450',
      icon: Icons.light_mode,
      tint: Color(0xFFF59E0B),
    ),
    DealItem(
      label: 'Kurta sets',
      teaser: 'From Rs. 1,200',
      icon: Icons.checkroom,
      tint: Color(0xFF0EA5E9),
    ),
    DealItem(
      label: 'Saris',
      teaser: 'Under Rs. 2,000',
      icon: Icons.woman,
      tint: Color(0xFFEC4899),
    ),
  ];

  /// Seasonal placeholder. Dashain is the Nepali festival this storefront
  /// would actually merchandise around; a real build would drive both the
  /// title and the tint from a campaign the admin schedules.
  static const festival = [
    DealItem(
      label: 'Sweets and hampers',
      teaser: 'From Rs. 299',
      icon: Icons.card_giftcard,
      tint: Color(0xFFE84326),
    ),
    DealItem(
      label: 'Skincare sets',
      teaser: 'Up to 60% off',
      icon: Icons.spa,
      tint: Color(0xFFA855F7),
    ),
    DealItem(
      label: 'Jewellery',
      teaser: 'Under Rs. 1,500',
      icon: Icons.diamond,
      tint: Color(0xFFF59E0B),
    ),
    DealItem(
      label: 'Home decor',
      teaser: 'From Rs. 199',
      icon: Icons.emoji_objects,
      tint: Color(0xFF059669),
    ),
  ];

  static const spotlight = [
    SpotlightItem(
      offer: 'From Rs. 1,099',
      caption: 'Watches',
      icon: Icons.watch,
      tint: Color(0xFF6366F1),
    ),
    SpotlightItem(
      offer: 'Min. 65% off',
      caption: 'Running shoes',
      icon: Icons.directions_run,
      tint: Color(0xFF059669),
    ),
    SpotlightItem(
      offer: 'Up to 80% off',
      caption: 'Earbuds',
      icon: Icons.earbuds,
      tint: Color(0xFF0EA5E9),
    ),
    SpotlightItem(
      offer: 'From Rs. 799',
      caption: 'Backpacks',
      icon: Icons.backpack,
      tint: Color(0xFFF97316),
    ),
  ];
}

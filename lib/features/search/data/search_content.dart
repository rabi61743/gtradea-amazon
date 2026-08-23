import 'package:flutter/material.dart';

/// A query the storefront is promoting, with a thumbnail.
class TrendingSearch {
  const TrendingSearch({
    required this.query,
    required this.icon,
    required this.tint,
    this.imageUrl,
  });

  final String query;
  final IconData icon;
  final Color tint;
  final String? imageUrl;
}

/// One result row.
///
/// Richer than the home rail's ProductItem: results carry the facts a shopper
/// compares on -- specs, savings, delivery -- which a browse tile does not.
class SearchResult {
  const SearchResult({
    required this.title,
    required this.price,
    required this.rating,
    required this.reviewCount,
    required this.icon,
    required this.tint,
    this.listPrice,
    this.specs = const [],
    this.imageUrl,
    this.freeDelivery = false,
    this.sponsored = false,
  });

  final String title;
  final num price;
  final num? listPrice;
  final double rating;
  final int reviewCount;
  final IconData icon;
  final Color tint;

  /// Short factual chips, e.g. "25 L", "5 star". Not marketing copy.
  final List<String> specs;

  final String? imageUrl;
  final bool freeDelivery;

  /// Paid placement. Labelled in the UI because not labelling it would be
  /// the deceptive choice.
  final bool sponsored;

  /// Whole-percent saving, or null when there is nothing to claim.
  int? get discountPercent {
    final list = listPrice;
    if (list == null || list <= price) return null;
    return (((list - price) / list) * 100).round();
  }
}

/// A filter the results can be narrowed by.
class FilterGroup {
  const FilterGroup({required this.label, required this.options});

  final String label;
  final List<String> options;
}

class SearchContent {
  SearchContent._();

  static const trending = [
    TrendingSearch(
      query: 'Water geysers',
      icon: Icons.water_drop,
      tint: Color(0xFF0891B2),
      imageUrl: 'https://loremflickr.com/200/200/waterheater?lock=101',
    ),
    TrendingSearch(
      query: 'Running shoes',
      icon: Icons.directions_run,
      tint: Color(0xFF059669),
      imageUrl: 'https://loremflickr.com/200/200/running,shoes?lock=102',
    ),
    TrendingSearch(
      query: 'Rice 5 kg',
      icon: Icons.rice_bowl,
      tint: Color(0xFFF59E0B),
      imageUrl: 'https://loremflickr.com/200/200/rice,sack?lock=103',
    ),
    TrendingSearch(
      query: 'Wireless earbuds',
      icon: Icons.earbuds,
      tint: Color(0xFF6366F1),
      imageUrl: 'https://loremflickr.com/200/200/earbuds?lock=104',
    ),
    TrendingSearch(
      query: 'Winter jackets',
      icon: Icons.checkroom,
      tint: Color(0xFFA855F7),
      imageUrl: 'https://loremflickr.com/200/200/winter,jacket?lock=105',
    ),
    TrendingSearch(
      query: 'Pressure cookers',
      icon: Icons.soup_kitchen,
      tint: Color(0xFFE84326),
      imageUrl: 'https://loremflickr.com/200/200/pressure,cooker?lock=106',
    ),
  ];

  static const recent = [
    'metal chopsticks',
    'kids fashion',
    'wardrobe',
    'shoes',
  ];

  static const filters = [
    FilterGroup(
      label: 'Customer rating',
      options: ['4★ and above', '3★ and above', '2★ and above', 'Unrated'],
    ),
    FilterGroup(
      label: 'Price',
      options: [
        'Under Rs. 2,000',
        'Rs. 2,000 - 5,000',
        'Rs. 5,000 - 10,000',
        'Above Rs. 10,000',
      ],
    ),
    FilterGroup(
      label: 'Capacity',
      options: ['10 L', '15 L', '25 L', '35 L'],
    ),
    FilterGroup(
      label: 'Delivery',
      options: ['Free delivery', 'Delivered in 3 days'],
    ),
  ];

  static const results = [
    SearchResult(
      title: 'Atlantis Pro 25 L storage water geyser, 5 star',
      price: 3559,
      listPrice: 9990,
      rating: 4.5,
      reviewCount: 58,
      icon: Icons.water_drop,
      tint: Color(0xFF0891B2),
      specs: ['25 L', '5 star', '6.5 bar', '2 yr warranty'],
      imageUrl: 'https://loremflickr.com/400/400/waterheater?lock=201',
      freeDelivery: true,
      sponsored: true,
    ),
    SearchResult(
      title: 'Instant 10 L water heater, copper tank',
      price: 5240,
      listPrice: 7800,
      rating: 4.0,
      reviewCount: 214,
      icon: Icons.hot_tub,
      tint: Color(0xFFF97316),
      specs: ['10 L', '4 star', '8 bar'],
      imageUrl: 'https://loremflickr.com/400/400/boiler?lock=202',
    ),
    SearchResult(
      title: 'Slim 15 L geyser with digital display',
      price: 7990,
      rating: 3.5,
      reviewCount: 41,
      icon: Icons.thermostat,
      tint: Color(0xFF6366F1),
      specs: ['15 L', '4 star', 'Digital'],
      imageUrl: 'https://loremflickr.com/400/400/waterheater,tank?lock=203',
      freeDelivery: true,
    ),
    SearchResult(
      title: 'Compact 6 L instant heater for kitchens',
      price: 2450,
      listPrice: 3100,
      rating: 4.0,
      reviewCount: 96,
      icon: Icons.kitchen,
      tint: Color(0xFF059669),
      specs: ['6 L', '3 star'],
      imageUrl: 'https://loremflickr.com/400/400/geyser?lock=204',
    ),
  ];
}

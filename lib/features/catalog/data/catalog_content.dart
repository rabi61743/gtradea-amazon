import 'package:flutter/material.dart';

import '../../home/home_content.dart';
import '../../home/widgets/category_section.dart' show CategoryEntry;

/// A named block of subcategories inside a department.
class CatalogGroup {
  const CatalogGroup({required this.title, required this.entries});

  final String title;
  final List<CategoryEntry> entries;
}

/// A top-level department, as the browse rail lists it.
class Department {
  const Department({
    required this.label,
    required this.icon,
    required this.tint,
    required this.tagline,
    required this.groups,
    this.imageUrl,
  });

  final String label;
  final IconData icon;
  final Color tint;

  /// One line under the department name. Says what is actually in here, so the
  /// header is worth its height rather than repeating the name in a bigger font.
  final String tagline;

  final List<CatalogGroup> groups;

  /// The one photograph in a department's block. Null falls back to the
  /// tinted glyph, which is what the tiles below use anyway.
  final String? imageUrl;

  int get entryCount =>
      groups.fold(0, (sum, group) => sum + group.entries.length);

  /// The handful surfaced above the groups. Taken from the front of each group
  /// in turn rather than the first group only, so the strip is a sample of the
  /// whole department instead of a duplicate of the first section.
  List<CategoryEntry> get popular {
    final picks = <CategoryEntry>[];
    for (var depth = 0; depth < 2; depth++) {
      for (final group in groups) {
        if (group.entries.length > depth) picks.add(group.entries[depth]);
        if (picks.length == 6) return picks;
      }
    }
    return picks;
  }
}

/// The browse tree.
///
/// Built on the same [CategoryEntry] lists the home feed already renders, so
/// the storefront cannot show a department on the home page and a different
/// one under browse. Only the grouping is new here.
class CatalogContent {
  const CatalogContent._();

  static const departments = <Department>[
    Department(
      label: 'Electronics',
      icon: Icons.memory,
      tint: Color(0xFF6366F1),
      tagline: 'Audio, computing and everything that plugs in',
      imageUrl: 'https://loremflickr.com/400/400/electronics?lock=25',
      groups: [
        CatalogGroup(title: 'Audio and devices', entries: HomeContent.electronics),
        CatalogGroup(title: 'Computing', entries: HomeContent.computing),
        CatalogGroup(title: 'Gaming gear', entries: HomeContent.gaming),
      ],
    ),
    Department(
      label: 'Home and kitchen',
      icon: Icons.chair,
      tint: Color(0xFF0891B2),
      tagline: 'Furnish it, light it, and cook in it',
      imageUrl: 'https://loremflickr.com/400/400/kitchen?lock=23',
      groups: [
        CatalogGroup(title: 'Living and dining', entries: HomeContent.homeGoods),
        CatalogGroup(title: 'Kitchen', entries: _kitchen),
        CatalogGroup(title: 'Storage', entries: _storage),
      ],
    ),
    Department(
      label: 'Fashion',
      icon: Icons.checkroom,
      tint: Color(0xFFF59E0B),
      tagline: 'Everyday wear, footwear and the bits that finish it',
      imageUrl: 'https://loremflickr.com/400/400/outdoor,jacket?lock=26',
      groups: [
        CatalogGroup(title: 'Footwear', entries: HomeContent.shoes),
        CatalogGroup(title: 'Clothing', entries: _clothing),
      ],
    ),
    Department(
      label: 'Beauty',
      icon: Icons.brush,
      tint: Color(0xFFEC4899),
      tagline: 'Skin, hair and colour',
      groups: [CatalogGroup(title: 'Skin and hair', entries: _beauty)],
    ),
    Department(
      label: 'Sports and outdoors',
      icon: Icons.sports_baseball,
      tint: Color(0xFF059669),
      tagline: 'Training at home and days out of it',
      imageUrl: 'https://loremflickr.com/400/400/sports?lock=24',
      groups: [CatalogGroup(title: 'Training and outdoors', entries: _sports)],
    ),
    Department(
      label: 'Family and toys',
      icon: Icons.family_restroom,
      tint: Color(0xFFEF4444),
      tagline: 'For the children, and for the whole house',
      groups: [CatalogGroup(title: 'Toys and family', entries: HomeContent.family)],
    ),
    Department(
      label: 'Pet supplies',
      icon: Icons.pets,
      tint: Color(0xFFA855F7),
      tagline: 'Food, bedding and things to chew',
      imageUrl: 'https://loremflickr.com/400/400/pets?lock=27',
      groups: [CatalogGroup(title: 'For your pets', entries: HomeContent.pets)],
    ),
  ];

  // Placeholder rows, in the same shape and with the same keyword-matched
  // photography as the home feed's lists.
  static const _kitchen = [
    CategoryEntry(
      label: 'Cookware',
      imageUrl: 'https://loremflickr.com/400/400/cookware,pan?lock=61',
      icon: Icons.soup_kitchen,
      tint: Color(0xFFF97316),
    ),
    CategoryEntry(
      label: 'Small appliances',
      imageUrl: 'https://loremflickr.com/400/400/blender,kitchen?lock=62',
      icon: Icons.blender,
      tint: Color(0xFF0EA5E9),
    ),
    CategoryEntry(
      label: 'Tableware',
      imageUrl: 'https://loremflickr.com/400/400/plates,tableware?lock=63',
      icon: Icons.dinner_dining,
      tint: Color(0xFF059669),
    ),
  ];

  static const _storage = [
    CategoryEntry(
      label: 'Shelving',
      imageUrl: 'https://loremflickr.com/400/400/shelf,bookcase?lock=64',
      icon: Icons.shelves,
      tint: Color(0xFF8B5CF6),
    ),
    CategoryEntry(
      label: 'Wardrobes',
      imageUrl: 'https://loremflickr.com/400/400/wardrobe,closet?lock=65',
      icon: Icons.door_sliding,
      tint: Color(0xFFB45309),
    ),
    CategoryEntry(
      label: 'Boxes and baskets',
      imageUrl: 'https://loremflickr.com/400/400/storage,basket?lock=66',
      icon: Icons.inventory_2,
      tint: Color(0xFF0891B2),
    ),
  ];

  static const _clothing = [
    CategoryEntry(
      label: 'Jackets',
      imageUrl: 'https://loremflickr.com/400/400/jacket,coat?lock=67',
      icon: Icons.checkroom,
      tint: Color(0xFF2563EB),
    ),
    CategoryEntry(
      label: 'Dresses',
      imageUrl: 'https://loremflickr.com/400/400/dress?lock=68',
      icon: Icons.woman,
      tint: Color(0xFFEC4899),
    ),
    CategoryEntry(
      label: 'Bags',
      imageUrl: 'https://loremflickr.com/400/400/handbag?lock=69',
      icon: Icons.shopping_bag,
      tint: Color(0xFFB45309),
    ),
    CategoryEntry(
      label: 'Watches',
      imageUrl: 'https://loremflickr.com/400/400/wristwatch?lock=70',
      icon: Icons.watch,
      tint: Color(0xFF334155),
    ),
  ];

  static const _beauty = [
    CategoryEntry(
      label: 'Skincare',
      imageUrl: 'https://loremflickr.com/400/400/skincare,cosmetics?lock=71',
      icon: Icons.face_retouching_natural,
      tint: Color(0xFFEC4899),
    ),
    CategoryEntry(
      label: 'Hair care',
      imageUrl: 'https://loremflickr.com/400/400/shampoo,haircare?lock=72',
      icon: Icons.content_cut,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Fragrance',
      imageUrl: 'https://loremflickr.com/400/400/perfume,bottle?lock=73',
      icon: Icons.local_florist,
      tint: Color(0xFFF59E0B),
    ),
  ];

  static const _sports = [
    CategoryEntry(
      label: 'Home gym',
      imageUrl: 'https://loremflickr.com/400/400/dumbbell,gym?lock=74',
      icon: Icons.fitness_center,
      tint: Color(0xFF059669),
    ),
    CategoryEntry(
      label: 'Cycling',
      imageUrl: 'https://loremflickr.com/400/400/bicycle?lock=75',
      icon: Icons.pedal_bike,
      tint: Color(0xFF0EA5E9),
    ),
    CategoryEntry(
      label: 'Camping',
      imageUrl: 'https://loremflickr.com/400/400/tent,camping?lock=76',
      icon: Icons.forest,
      tint: Color(0xFF16A34A),
    ),
  ];
}

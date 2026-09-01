import 'package:flutter/material.dart';

/// A banner to show when the server cannot supply one.
class FallbackBanner {
  const FallbackBanner({
    required this.eyebrow,
    required this.headline,
    required this.caption,
    required this.cta,
    required this.colors,
    required this.icon,
    this.query = '',
  });

  final String eyebrow;
  final String headline;
  final String caption;
  final String cta;

  /// The gradient behind it. Two stops, dark enough at the left for white text
  /// to sit on without a scrim.
  final List<Color> colors;

  /// A large, faint glyph in the corner. Standing in for artwork rather than
  /// pretending to be a photograph.
  final IconData icon;

  /// What tapping it searches for. Empty opens the catalogue.
  final String query;
}

/// The banners shown when `/hero-banners` is empty or unreachable.
///
/// **Deliberately imageless.** The case these exist for is the server being
/// unreachable, and a device that cannot reach the API usually cannot reach a
/// CDN either -- so fallbacks that referenced remote artwork would be blank
/// in exactly the situation they were written for. Gradients and a glyph render
/// from the binary and always work.
///
/// **Deliberately free of offers.** Every one is an invitation to browse
/// something that genuinely exists in the catalogue. None of them names a
/// discount, a price or a deadline: these appear when the server is silent,
/// which is precisely when nothing can confirm such a claim, and a made-up
/// "50% off everything" would still be on screen for a shopper who then found
/// no such thing.
const kFallbackBanners = <FallbackBanner>[
  FallbackBanner(
    eyebrow: 'Welcome to GtradeA',
    headline: 'Everything, from one place',
    caption: 'Thousands of products across dozens of departments',
    cta: 'Start browsing',
    colors: [Color(0xFF1B5D6B), Color(0xFF2E9AAF)],
    icon: Icons.storefront_outlined,
  ),
  FallbackBanner(
    eyebrow: 'Fashion',
    headline: 'Dress the season',
    caption: 'Womenswear, menswear, footwear and more',
    cta: 'Shop fashion',
    colors: [Color(0xFF8E2A5C), Color(0xFFD4568F)],
    icon: Icons.checkroom,
    query: 'fashion',
  ),
  FallbackBanner(
    eyebrow: 'Home and living',
    headline: 'Make room for better',
    caption: 'Furniture, textiles and things for the kitchen',
    cta: 'Shop home',
    colors: [Color(0xFF7A4A12), Color(0xFFD08A2C)],
    icon: Icons.chair_outlined,
    query: 'home',
  ),
  FallbackBanner(
    eyebrow: 'Electronics',
    headline: 'Gear worth plugging in',
    caption: 'Audio, computing, phones and accessories',
    cta: 'Shop electronics',
    colors: [Color(0xFF23346B), Color(0xFF4C6FD1)],
    icon: Icons.memory,
    query: 'electronics',
  ),
];

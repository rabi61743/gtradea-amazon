import 'package:flutter/material.dart';

import '../../home/widgets/product_rail.dart';

/// A selectable variant, e.g. a colourway.
class ProductVariant {
  const ProductVariant({
    required this.label,
    required this.imageUrl,
    this.inStock = true,
  });

  final String label;
  final String imageUrl;

  /// Out-of-stock variants stay visible but unselectable. Hiding them makes a
  /// shopper think the option never existed and hunt for it elsewhere.
  final bool inStock;
}

/// One row of the specification table.
class ProductSpec {
  const ProductSpec(this.label, this.value);
  final String label;
  final String value;
}

/// A named guarantee, e.g. returns or payment on delivery.
class Assurance {
  const Assurance({
    required this.label,
    required this.icon,
    required this.detail,
  });

  final String label;
  final IconData icon;

  /// What the guarantee actually means, in a sentence. The reference shows
  /// these as chevrons; a promise the shopper cannot read is not a promise.
  final String detail;
}

/// One review, as written.
class ProductReview {
  const ProductReview({
    required this.author,
    required this.rating,
    required this.when,
    required this.body,
    this.verified = true,
  });

  final String author;
  final double rating;
  final String when;
  final String body;
  final bool verified;
}

/// Ratings in aggregate.
///
/// Carries the whole distribution, not just the mean: a 4.3 built from steady
/// fours reads very differently from one built of fives and ones, and the
/// average alone hides which it is.
class RatingSummary {
  const RatingSummary({
    required this.average,
    required this.total,
    required this.distribution,
    required this.verifiedShare,
  });

  final double average;
  final int total;

  /// Counts for five stars down to one, in that order.
  final List<int> distribution;

  /// Share of ratings from confirmed purchases, 0 to 1.
  final double verifiedShare;

  int get verifiedCount => (total * verifiedShare).round();

  /// Plain-language read of the average, so the number is not the only cue.
  String get verdict {
    if (average >= 4.5) return 'Excellent';
    if (average >= 4.0) return 'Very good';
    if (average >= 3.0) return 'Mixed';
    return 'Poor';
  }
}

class ProductDetail {
  const ProductDetail({
    required this.title,
    required this.price,
    required this.rating,
    required this.reviewCount,
    required this.images,
    required this.variants,
    required this.specs,
    required this.description,
    this.listPrice,
    this.minOrder = 1,
    this.soldCount,
    this.freeDelivery = false,
    this.highlights = const [],
    this.assurances = const [],
    this.reviews = const [],
    this.similar = const [],
    this.ratingSummary,
  });

  final String title;
  final num price;
  final num? listPrice;
  final double rating;
  final int reviewCount;
  final List<String> images;
  final List<ProductVariant> variants;
  final List<ProductSpec> specs;
  final String description;
  final int minOrder;
  final int? soldCount;
  final bool freeDelivery;

  /// The handful of facts a shopper checks before anything else. Separate from
  /// [specs], which is the exhaustive table.
  final List<ProductSpec> highlights;

  final List<Assurance> assurances;
  final List<ProductReview> reviews;
  final List<ProductItem> similar;
  final RatingSummary? ratingSummary;

  /// Whole-percent saving, or null when there is nothing honest to claim.
  int? get discountPercent {
    final list = listPrice;
    if (list == null || list <= price) return null;
    return (((list - price) / list) * 100).round();
  }

  /// VAT already inside the shown price, back-solved at 13% the way both
  /// GtradeA storefronts do it. Null when it rounds away to nothing.
  int? get vatIncluded {
    if (price <= 0) return null;
    final derived = (price * 13 / 113).round();
    return derived > 0 ? derived : null;
  }

  /// Placeholder detail built on a real catalogue row: the title, price and
  /// lead photograph come from /api/v1/feed/trending-products. The extra
  /// gallery shots, variants, specs and reviews are invented -- that endpoint
  /// returns one image and no attributes.
  static const sample = ProductDetail(
    title: 'Ice Silk Sun Protection Clothing for Women, summer 2026',
    price: 1130,
    listPrice: 1568,
    rating: 4.3,
    reviewCount: 128,
    soldCount: 2031,
    freeDelivery: true,
    images: [
      'https://cbu01.alicdn.com/img/ibank/'
          'O1CN01iXcpl126fA5yFMZ2a_!!2222450237688-0-cib.jpg',
      'https://loremflickr.com/800/800/jacket,women?lock=301',
      'https://loremflickr.com/800/800/hoodie?lock=302',
      'https://loremflickr.com/800/800/sportswear?lock=303',
    ],
    variants: [
      ProductVariant(
        label: 'Blush pink',
        imageUrl: 'https://cbu01.alicdn.com/img/ibank/'
            'O1CN01iXcpl126fA5yFMZ2a_!!2222450237688-0-cib.jpg',
      ),
      ProductVariant(
        label: 'Ivory',
        imageUrl: 'https://loremflickr.com/200/200/white,jacket?lock=304',
      ),
      ProductVariant(
        label: 'Slate blue',
        imageUrl: 'https://loremflickr.com/200/200/blue,jacket?lock=305',
      ),
      ProductVariant(
        label: 'Charcoal',
        imageUrl: 'https://loremflickr.com/200/200/black,jacket?lock=306',
        inStock: false,
      ),
    ],
    highlights: [
      ProductSpec('Pack of', '1 jacket'),
      ProductSpec('Sun protection', 'UPF 50+'),
      ProductSpec('Material', 'Ice silk blend'),
      ProductSpec('Fit', 'Loose, cropped'),
      ProductSpec('Sizes', 'S to XXL'),
      ProductSpec('Weight', '210 g'),
    ],
    assurances: [
      Assurance(
        label: '7-day returns',
        icon: Icons.assignment_return_outlined,
        detail:
            'Send it back within 7 days of delivery for a full refund, as long '
            'as tags are attached and it is unworn.',
      ),
      Assurance(
        label: 'Cash on delivery',
        icon: Icons.payments_outlined,
        detail:
            'Pay the courier when it arrives. Available across Nepal on orders '
            'under Rs. 25,000.',
      ),
      Assurance(
        label: 'Quality checked',
        icon: Icons.verified_outlined,
        detail:
            'Inspected at our Kathmandu warehouse before dispatch. Anything '
            'damaged or mismatched is replaced at no cost.',
      ),
    ],
    specs: [
      ProductSpec('Material', 'Ice silk blend'),
      ProductSpec('Fit', 'Loose, cropped'),
      ProductSpec('Sun protection', 'UPF 50+'),
      ProductSpec('Closure', 'Full zip with hood'),
      ProductSpec('Care', 'Machine wash cold'),
      ProductSpec('Sizes', 'S to XXL'),
    ],
    ratingSummary: RatingSummary(
      average: 4.3,
      total: 128,
      distribution: [74, 31, 12, 6, 5],
      verifiedShare: 0.86,
    ),
    reviews: [
      ProductReview(
        author: 'Sunita R.',
        rating: 5,
        when: '2 weeks ago',
        body:
            'Light enough to wear on the bike in the sun and it does not trap '
            'heat. The hood is deeper than it looks in the photos.',
      ),
      ProductReview(
        author: 'Bikash T.',
        rating: 4,
        when: 'last month',
        body:
            'Good fabric for the price. Runs a size large, so order down if '
            'you want it fitted.',
      ),
      ProductReview(
        author: 'Anonymous',
        rating: 3,
        when: 'last month',
        verified: false,
        body: 'Colour is slightly paler than the listing photo.',
      ),
    ],
    similar: [
      ProductItem(
        title: 'Khaki culottes, elastic high waist',
        price: 1921,
        listPrice: 2760,
        rating: 4.0,
        reviewCount: 64,
        icon: Icons.checkroom,
        tint: Color(0xFFF97316),
        imageUrl: 'https://cbu01.alicdn.com/img/ibank/'
            'O1CN01Bni0Xe1tkZgUKE65i_!!2204179815940-0-cib.jpg',
      ),
      ProductItem(
        title: 'Ballet-style suspender dress',
        price: 1808,
        rating: 5.0,
        reviewCount: 12,
        icon: Icons.woman,
        tint: Color(0xFFEC4899),
        imageUrl: 'https://cbu01.alicdn.com/img/ibank/'
            'O1CN01iBIpGB25c7r5El11d_!!2220252547546-0-cib.jpg',
      ),
      ProductItem(
        title: 'Retro lace-up collar top',
        price: 1808,
        listPrice: 2545,
        rating: 3.5,
        reviewCount: 41,
        icon: Icons.checkroom,
        tint: Color(0xFF0EA5E9),
        imageUrl: 'https://cbu01.alicdn.com/img/ibank/'
            'O1CN01kprFtD2LEnXBsp37y_!!2220883829661-0-cib.jpg',
      ),
    ],
    description:
        'Lightweight ice-silk jacket cut loose for airflow, with a full zip '
        'and a drawstring hood. Rated UPF 50+, so it blocks the sun without '
        'trapping heat -- meant for commuting and outdoor work in warm '
        'weather rather than for warmth.',
  );
}

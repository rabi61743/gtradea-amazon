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

  /// Whole-percent saving, or null when there is nothing honest to claim.
  int? get discountPercent {
    final list = listPrice;
    if (list == null || list <= price) return null;
    return (((list - price) / list) * 100).round();
  }

  /// VAT already inside the shown price, back-solved at 13% the way both
  /// GtradeA storefronts do it. Null under a rupee, where the figure would
  /// round to nothing and say less than it implies.
  int? get vatIncluded {
    if (price <= 0) return null;
    final derived = (price * 13 / 113).round();
    return derived > 0 ? derived : null;
  }

  /// Placeholder detail built on a real catalogue row: the title, price and
  /// lead photograph come from /api/v1/feed/trending-products. The extra
  /// gallery shots, variants and specs are invented -- that endpoint returns
  /// one image and no attributes.
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
    specs: [
      ProductSpec('Material', 'Ice silk blend'),
      ProductSpec('Fit', 'Loose, cropped'),
      ProductSpec('Sun protection', 'UPF 50+'),
      ProductSpec('Closure', 'Full zip with hood'),
      ProductSpec('Care', 'Machine wash cold'),
      ProductSpec('Sizes', 'S to XXL'),
    ],
    description:
        'Lightweight ice-silk jacket cut loose for airflow, with a full zip '
        'and a drawstring hood. Rated UPF 50+, so it blocks the sun without '
        'trapping heat -- meant for commuting and outdoor work in warm '
        'weather rather than for warmth.',
  );
}

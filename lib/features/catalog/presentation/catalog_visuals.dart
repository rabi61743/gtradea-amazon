import 'package:flutter/material.dart';

import '../../flash_sale/presentation/product_deal_banner.dart';
import '../../home/widgets/category_section.dart';
import '../../search/data/search_models.dart';
import '../../home/widgets/department_grid.dart';
import '../../home/widgets/product_rail.dart';
import '../data/catalog_repository.dart';
import '../../product/presentation/product_detail_screen.dart';
import '../data/product.dart';

/// Icons and colours for catalogue rows.
///
/// The server sends names and photographs, not artwork -- so the icon behind a
/// missing image and the accent on a tile are chosen here. Both are derived
/// from the row's own name and id, which means they are stable: a department
/// keeps the same colour between sessions and between devices, rather than
/// flickering to a new one on every load.
///
/// This is decoration standing in for a missing picture. Nothing a shopper
/// could mistake for information -- price, stock, rating -- is ever invented
/// this way.
IconData iconForCategory(String? name) {
  final n = (name ?? '').toLowerCase();
  for (final (icon, words) in _iconKeywords) {
    for (final word in words) {
      if (n.contains(word)) return icon;
    }
  }
  return Icons.category_outlined;
}

const _iconKeywords = <(IconData, List<String>)>[
  // Order is significant, and these four are first for it. The catalogue's
  // busiest departments are Women, Men, Kidswear and Toys, and they used to
  // collapse onto two glyphs -- a hanger for the first two and a toy car for
  // the second two -- so four adjacent tiles in the picker read as two.
  //
  // "women" has to be tested before "men", or every women's department matches
  // the substring in its own name and comes back as the men's icon.
  (Icons.woman, ['women', 'ladies', 'lingerie']),
  (Icons.man, ['men', 'gentlemen']),
  (Icons.child_care, ['kid', 'child', 'baby', 'infant', 'mother', 'maternal']),
  (Icons.toys_outlined, ['toy']),
  (Icons.checkroom, ['apparel', 'clothing', 'dress', 'shirt', 'wear']),
  (Icons.watch, ['watch', 'jewel', 'accessor']),
  (Icons.memory, ['electronic', 'digital', 'computer', 'phone', 'audio']),
  (Icons.chair_outlined, ['home', 'furniture', 'living', 'kitchen', 'garden']),
  (Icons.sports_soccer, ['sport', 'outdoor', 'fitness']),
  (Icons.face_retouching_natural, ['beauty', 'cosmetic', 'personal care']),
  (Icons.directions_car_outlined, ['auto', 'car', 'motor', 'vehicle']),
  (Icons.build_outlined, ['tool', 'hardware', 'industrial', 'machine']),
  (Icons.pets, ['pet', 'animal']),
  (Icons.local_grocery_store_outlined, ['food', 'grocer', 'snack', 'drink']),
  (Icons.backpack_outlined, ['bag', 'luggage', 'shoe', 'footwear']),
  (Icons.brush_outlined, ['craft', 'stationery', 'office', 'art']),
  (Icons.medical_services_outlined, ['health', 'medical', 'care']),
];

/// A stable accent for a row.
///
/// Keyed on the id rather than the position, so inserting a new department
/// does not recolour every one after it.
Color tintForCategory(String key) {
  if (key.isEmpty) return _palette.first;
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _palette[hash % _palette.length];
}

const _palette = [
  Color(0xFF6366F1),
  Color(0xFF0EA5E9),
  Color(0xFF059669),
  Color(0xFFF97316),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFFEF4444),
  Color(0xFF0891B2),
];

/// A catalogue row as a rail card.
ProductItem toProductItem(Product product, {VoidCallback? onTap}) =>
    ProductItem(
      onTap: onTap,
      // Units sold, which is the only popularity signal this catalogue has.
      footnote: product.salesLabel,
      title: product.title,
      price: product.displayPrice ?? 0,
      // No strike-through: the server publishes one price, and inventing a
      // "was" figure from a markup nobody publishes is a false saving.
      listPrice: null,
      // No ratings exist for this catalogue. Zero renders as no stars rather
      // than as a bad score.
      rating: product.rating ?? 0,
      reviewCount: 0,
      icon: iconForCategory(product.categoryName ?? product.parentCategoryName),
      tint: tintForCategory(product.categoryCid ?? product.numIid),
      imageUrl: product.imageUrl,
    );

CategoryEntry toCategoryEntry(Category category) => CategoryEntry(
  label: category.name,
  icon: iconForCategory(category.name),
  tint: tintForCategory(category.cid),
  imageUrl: category.imageUrl,
);

DepartmentEntry toDepartmentEntry(Category category) => DepartmentEntry(
  label: category.name,
  icon: iconForCategory(category.name),
  tint: tintForCategory(category.cid),
  imageUrl: category.imageUrl,
);

/// Opens the product page for a catalogue row.
///
/// One helper rather than the same MaterialPageRoute in six files -- and it is
/// the place that guarantees the page is always given the row it is about,
/// instead of whatever product happened to be the default.
/// [deal] is set only by the surfaces that opened it from an offer -- the flash
/// sale block and the deals page -- so the page can carry the discount, the
/// deadline and the "was" price through with it. Every other caller passes
/// nothing and gets the page exactly as it has always been.
void openProduct(BuildContext context, Product product, {ProductDeal? deal}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProductDetailScreen(product: product, deal: deal),
    ),
  );
}

/// A rail of catalogue rows, each card opening its own product.
List<ProductItem> toProductItems(
  BuildContext context,
  List<Product> products,
) => products
    .map((p) => toProductItem(p, onTap: () => openProduct(context, p)))
    .toList(growable: false);

/// A catalogue row as a search result row.
SearchResult toSearchResult(Product product) => SearchResult(
  title: product.title,
  price: product.displayPrice ?? 0,
  rating: product.rating ?? 0,
  reviewCount: 0,
  icon: iconForCategory(product.categoryName ?? product.parentCategoryName),
  tint: tintForCategory(product.categoryCid ?? product.numIid),
  imageUrl: product.imageUrl,
  // Facts the row actually carries, rather than invented chips: which
  // department it sits in, how many have sold, and the minimum order for
  // the wholesale lines where that is the surprise.
  specs: [
    if (product.categoryName != null) product.categoryName!,
    if (product.salesLabel != null) product.salesLabel!,
    if (product.minOrder > 1) 'Min ${product.minOrder}',
    if (product.sellerBadge != null) product.sellerBadge!,
  ],
);

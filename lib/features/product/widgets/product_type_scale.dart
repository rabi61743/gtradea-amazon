import 'package:flutter/material.dart';

/// The type scale the product page is set in.
///
/// One place for it, because the page is assembled from a dozen widgets in
/// four files and the same role -- a section heading, an attribute label --
/// was being spelt out separately in each. Spelt out once, a heading cannot
/// drift a point away from the heading two cards below it.
///
/// The colours are named for the brand's own roles rather than taken raw:
/// slate is the foreground, muted grey the held-back foreground, and Trust
/// Blue the primary. That keeps the scale honest in either theme.
class ProductType {
  ProductType._();

  /// The product name. Three lines at most -- see where it is used.
  static TextStyle title(ThemeData theme) => _base(theme).copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
    height: 1.3,
  );

  /// Sold counts, the supplier's name, the tax line: fact, not headline.
  static TextStyle meta(ThemeData theme) => _base(theme).copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: theme.colorScheme.onSurfaceVariant,
  );

  /// The figure itself.
  static TextStyle price(ThemeData theme) => _base(theme).copyWith(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: theme.colorScheme.primary,
    height: 1.15,
  );

  /// "Rs.", set a step down from the number it introduces so the digits lead.
  static TextStyle currency(ThemeData theme) => _base(theme).copyWith(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: theme.colorScheme.primary,
    height: 1.15,
  );

  static TextStyle quantityLabel(ThemeData theme) => _base(theme).copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
  );

  static TextStyle quantityValue(ThemeData theme) => _base(theme).copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
  );

  /// "Min. order:", beside the price. It names the figure rather than being
  /// it, so it stays the quieter half of the pair.
  static TextStyle minOrder(ThemeData theme) => _base(theme).copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: theme.colorScheme.onSurfaceVariant,
  );

  /// "500 pcs": the same size, a step heavier and in the foreground, so the
  /// figure leads without the pill growing.
  static TextStyle minOrderValue(ThemeData theme) => _base(theme).copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
  );

  static TextStyle logisticsTitle(ThemeData theme) => _base(theme).copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
    height: 1.2,
  );

  /// "Guaranteed delivery:" -- it names the dates rather than being them, so
  /// it is held back to the muted foreground while they keep the blue.
  static TextStyle deliveryLabel(ThemeData theme) => _base(theme).copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: theme.colorScheme.onSurfaceVariant,
    height: 1.3,
  );

  static TextStyle deliveryDate(ThemeData theme) => _base(theme).copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.primary,
    height: 1.3,
  );

  /// Returns, COD, Quality Checked.
  static TextStyle benefit(ThemeData theme) => _base(theme).copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: theme.colorScheme.onSurface,
    height: 1.25,
  );

  /// "Highlights", "Description".
  static TextStyle sectionHeading(ThemeData theme) => _base(theme).copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: theme.colorScheme.onSurface,
  );

  /// What a fact is called.
  static TextStyle attributeLabel(ThemeData theme) => _base(theme).copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: theme.colorScheme.onSurfaceVariant,
    height: 1.2,
  );

  /// The fact itself.
  static TextStyle attributeValue(ThemeData theme) => _base(theme).copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
    height: 1.25,
  );

  /// Long-form copy, which is the one place on the page that is read rather
  /// than scanned -- hence the looser line.
  static TextStyle description(ThemeData theme) => _base(theme).copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: theme.colorScheme.onSurface,
    height: 1.45,
  );

  /// The heading on a panel that opens: Specifications, Detail images.
  static TextStyle accordionLabel(ThemeData theme) => _base(theme).copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
  );

  /// Add to cart, Buy.
  static TextStyle cta(ThemeData theme) =>
      _base(theme).copyWith(fontSize: 15, fontWeight: FontWeight.w700);

  /// The page's own body style, so the family, letter spacing and any text
  /// scaling the theme sets are inherited rather than re-declared.
  static TextStyle _base(ThemeData theme) =>
      theme.textTheme.bodyMedium ?? const TextStyle();
}

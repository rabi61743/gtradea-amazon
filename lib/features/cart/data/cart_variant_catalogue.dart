import '../../product/data/product_detail_content.dart';
import '../../product/data/product_repository.dart';

/// The options a product in the cart can be had in, fetched from the catalogue.
///
/// The cart line records which variant was chosen -- its label, its SKU -- but
/// not what else was on offer, and it should not: a cart is a list of decisions,
/// not a copy of the catalogue. To offer a shopper a different colour the page
/// has to ask the catalogue what the colours are, which is what this does.
///
/// [ProductRepository.detail] is the one call, cached and de-duplicated there
/// already, so a cart of six lines makes at most six requests and none of them
/// twice. What is added here is the parse: turning the envelope into
/// [ProductVariant]s is not free, and a list that rebuilds on every stepper tap
/// would do it over and over.
///
/// Nothing is invented. A product whose feed carries no variants yields an empty
/// list, and the pickers then draw nothing.
class CartVariantCatalogue {
  CartVariantCatalogue._();

  static final instance = CartVariantCatalogue._();

  final Map<String, List<ProductVariant>> _parsed = {};
  final Map<String, Future<List<ProductVariant>>> _inflight = {};

  /// What is already known, without asking. Null means "not fetched yet",
  /// which is not the same as "none" -- see [variantsFor].
  List<ProductVariant>? cached(String productId) => _parsed[productId];

  /// The variants the catalogue publishes for [productId].
  ///
  /// Throws whatever the repository throws. The caller is a widget on the cart
  /// page and says so where the shopper can see it, rather than the cart
  /// quietly offering no choices because a request failed.
  Future<List<ProductVariant>> variantsFor(String productId) {
    final known = _parsed[productId];
    if (known != null) return Future.value(known);

    return _inflight[productId] ??= _fetch(productId).whenComplete(() {
      _inflight.remove(productId);
    });
  }

  Future<List<ProductVariant>> _fetch(String productId) async {
    final body = await ProductRepository.instance.detail(productId);
    final detail = ProductDetail.fromApi(
      body,
      // No catalogue row to fall back on here: the cart line is not a
      // [Product], and a fabricated one would put its own title and price into
      // the detail this parses.
      fallback: null,
    );
    return _parsed[productId] = detail.variants;
  }

  /// Forgets everything. For tests, and for a shopper signing out.
  void clear() {
    _parsed.clear();
    _inflight.clear();
  }
}

/// One axis of choice on a product: its name, and the values on it.
///
/// Built from the variants rather than declared anywhere: the feed names its
/// own axes -- "Color", "Size", "尺码" -- and this app has no business deciding
/// what a seller is allowed to call them.
class VariantAxis {
  const VariantAxis({
    required this.index,
    required this.name,
    required this.values,
  });

  /// Which position this axis takes in [ProductVariant.axisValues].
  final int index;

  /// What the seller calls it, capitalised the way the product page does it.
  final String name;

  /// Every value published on this axis, in the order the feed gave them.
  final List<String> values;
}

/// The axes across a set of variants, in feed order.
///
/// Only axes with something to choose between: a "Color" that is only ever
/// "Black" is not a choice, and a dropdown with one entry is a control that
/// cannot be used for anything.
List<VariantAxis> axesOf(List<ProductVariant> variants) {
  if (variants.isEmpty) return const [];

  final names = variants.first.axisNames;
  final depth = variants
      .map((v) => v.axisValues.length)
      .fold<int>(0, (a, b) => a > b ? a : b);

  final axes = <VariantAxis>[];
  for (var i = 0; i < depth; i++) {
    final values = <String>[];
    for (final variant in variants) {
      if (i >= variant.axisValues.length) continue;
      final value = variant.axisValues[i];
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
    }
    if (values.length < 2) continue;
    axes.add(VariantAxis(index: i, name: _axisName(names, i), values: values));
  }
  return axes;
}

/// The variant sitting at exactly [values], or null if the seller never
/// published that combination.
///
/// This is what stops an invalid pairing being offered: a shopper who picks a
/// colour the size they are on does not come in should not be able to reach it.
ProductVariant? variantAt(List<ProductVariant> variants, List<String> values) {
  for (final variant in variants) {
    if (variant.axisValues.length != values.length) continue;
    var same = true;
    for (var i = 0; i < values.length; i++) {
      if (variant.axisValues[i] != values[i]) {
        same = false;
        break;
      }
    }
    if (same) return variant;
  }
  return null;
}

/// The variant a cart line stands for, as far as the catalogue can tell.
///
/// By SKU first, which is what the order is actually placed against, and by
/// label second for a line saved before the SKU was recorded. Null when the
/// line's variant is no longer in the feed at all -- a seller can withdraw a
/// colourway, and the cart should not pretend otherwise.
ProductVariant? variantForLine(
  List<ProductVariant> variants, {
  String? skuId,
  String? label,
}) {
  if (skuId != null && skuId.isNotEmpty) {
    for (final variant in variants) {
      if (variant.skuId == skuId) return variant;
    }
  }
  if (label != null && label.isNotEmpty) {
    for (final variant in variants) {
      if (variant.label == label) return variant;
    }
  }
  return null;
}

/// The seller's own name for an axis, tidied the way the product page tidies it.
///
/// Sellers write these both ways -- "Color" on one listing, "color" on the next
/// -- and a label that is capitalised on one line of the cart and not on the
/// next reads as a rendering bug.
String _axisName(List<String> names, int index) {
  final raw = index < names.length ? names[index].trim() : '';
  if (raw.isEmpty) return index == 0 ? 'Option' : 'Variant';
  return raw[0].toUpperCase() + raw.substring(1);
}

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../catalog/data/product.dart';
import '../../product/data/product_detail_content.dart';
import '../../product/data/product_repository.dart';
import '../data/cart_store.dart';
import '../data/cart_variant_catalogue.dart';
import 'add_to_cart_sheet.dart';
import 'cart_flight.dart';

/// What the cart button on a card does, now that it asks first.
///
/// A shirt sold in four colours and five sizes has a choice to make, and the
/// options sheet makes it. A product sold one way has nothing to ask about,
/// and a sheet that offers a single answer is a door with one room behind it
/// -- so that one goes straight into the cart and flies there.
///
/// Which of the two it is comes from the catalogue, never from a guess:
/// [axesOf] keeps only the axes with more than one value on them, so "no axes"
/// means the seller published nothing to choose between.
enum QuickAdd {
  /// Added outright, because there was nothing to ask.
  added,

  /// The sheet was opened; what happened next is the sheet's business.
  asked,

  /// Nothing happened: the record would not load, or the one variant it has is
  /// sold out. Nothing was added and nothing was claimed.
  failed,
}

/// Adds [product] from a card, or opens the options sheet if it needs one.
///
/// [source] is the cart button itself -- the flight leaves from wherever it
/// really is on screen.
Future<QuickAdd> quickAddToCart(
  BuildContext context,
  Product product, {
  BuildContext? source,
}) async {
  if (!product.hasPrice) return QuickAdd.failed;

  final ProductDetail detail;
  try {
    detail = await _detailFor(product);
  } on ApiError {
    // The catalogue would not answer. Rather than add a line built on a
    // listing row -- no SKU, no real minimum -- let the sheet try, and say so
    // where the shopper can see it.
    if (!context.mounted) return QuickAdd.failed;
    await AddToCartSheet.show(context, product);
    return QuickAdd.asked;
  }
  if (!context.mounted) return QuickAdd.failed;

  // Anything left to choose is the sheet's job, untouched.
  if (axesOf(detail.variants).isNotEmpty) {
    await AddToCartSheet.show(context, product);
    return QuickAdd.asked;
  }

  // One published option, or none at all. Either way there is no question to
  // put to the shopper.
  final variant = detail.variants.isEmpty
      ? null
      : detail.variants.firstWhere(
          (v) => v.inStock,
          orElse: () => detail.variants.first,
        );
  if (variant != null && !variant.inStock) return QuickAdd.failed;

  final quantity = detail.minOrder > 0 ? detail.minOrder : 1;
  final line = CartLine(
    productId: detail.numIid,
    title: detail.title,
    // The variant's own price where it has one, the quantity ladder where it
    // does not -- the product page's rule, not a second one.
    unitPrice: variant?.price ?? detail.priceAt(quantity),
    variantLabel: variant?.label,
    imageUrl: (variant?.imageUrl.isNotEmpty ?? false)
        ? variant!.imageUrl
        : (detail.images.isNotEmpty
              ? detail.images.first
              : product.imageUrl),
    quantity: quantity,
    minOrder: quantity,
    freeDelivery: detail.freeDelivery,
    category: detail.category ?? product.categoryName,
    categoryCid: product.categoryCid,
    source: '1688',
    skuId: variant?.skuId,
    specId: variant?.specId,
    tiers: variant?.price == null ? detail.tiers : const [],
  );

  try {
    CartStore.instance.add(line);
  } catch (_) {
    // The count is the store's and it did not move, so nothing is shown that
    // would say otherwise.
    return QuickAdd.failed;
  }

  if (!context.mounted) return QuickAdd.added;
  // Only now, with the line really in the cart, does anything fly.
  await CartFlight.launch(
    source ?? context,
    reducedMotion: MediaQuery.of(context).disableAnimations,
    imageUrl: line.imageUrl,
  );
  return QuickAdd.added;
}

/// The record, from the five-minute cache when it is warm.
Future<ProductDetail> _detailFor(Product product) async {
  final cached = ProductRepository.instance.cachedDetail(product.numIid);
  if (cached != null) {
    return ProductDetail.fromApi(cached, fallback: product);
  }
  final body = await ProductRepository.instance.detail(product.numIid);
  return ProductDetail.fromApi(body, fallback: product);
}

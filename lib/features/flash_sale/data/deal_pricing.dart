import '../../catalog/data/product.dart';
import 'flash_sale.dart';
import 'flash_sale_placeholder.dart' as placeholder;

/// What a catalogue row costs when it is on offer.
///
/// One definition, shared by the flash sale section and the deals page. They
/// show the same products and must agree about the price of them -- a shopper
/// who sees Rs. 2,999 on the home page and Rs. 3,400 one tap later has been
/// told two different things about the same item.
///
/// The product and its price are always the server's. Whether there is a
/// discount at all, and how big, is the banner's when it published one and
/// invented otherwise -- see [placeholder], which is where every made-up figure
/// in this app lives.
FlashSaleItem dealPricing(Product product, {int? headlinePercent}) {
  final price = product.displayPrice ?? 0;

  if (headlinePercent != null && headlinePercent > 0) {
    // A real promotion: the catalogue price is genuinely the "was", and the
    // sale price is genuinely below it.
    final sale = (price * (100 - headlinePercent) / 100).roundToDouble();
    return FlashSaleItem(
      product: product,
      listPrice: price,
      salePrice: sale,
      discountPercent: headlinePercent,
    );
  }

  if (!placeholder.enabled) {
    // Nothing to discount by, so nothing is claimed: the real price, no badge,
    // no strike-through, no meter.
    return FlashSaleItem(
      product: product,
      listPrice: price,
      salePrice: price,
      discountPercent: 0,
    );
  }

  final discount = placeholder.discountFor(product.numIid);
  return FlashSaleItem(
    product: product,
    salePrice: price,
    listPrice: placeholder.listPriceFor(price, discount),
    discountPercent: discount,
    stock: placeholder.stockFor(product.numIid),
    soldPercent: placeholder.soldPercentFor(product.numIid),
  );
}

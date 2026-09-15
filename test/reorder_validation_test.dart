import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/reorder_validation.dart';

/// Reordering asks the catalogue about every line before anything is bought.
///
/// The order is the record of a purchase, not evidence about what is for sale
/// today. These tests pin the one rule the old reorder broke: nothing from an
/// old order reaches the cart unchecked, and nothing is *claimed* about a
/// product that the catalogue did not actually say.

/// A product record in the shape `GET /api/1688/product` returns.
Map<String, dynamic> detailJson({
  String numIid = 'p-1',
  String title = 'Ice silk jacket',
  num price = 1130,
  int minOrder = 1,
  List<Map<String, dynamic>> skus = const [],
  List<Map<String, dynamic>> tiers = const [],

  /// Whether the seller prices each SKU in its own right.
  ///
  /// It decides which price governs: a SKU with its own figure is charged at
  /// that figure and is not on the bulk ladder, exactly as the product page
  /// has it. Both cases are real and both are pinned below.
  bool pricePerSku = true,
}) => {
  'success': true,
  'item': {
    'num_iid': numIid,
    'title': title,
    'min_order_quantity': minOrder,
    'pic_url': 'https://example.invalid/$numIid.jpg',
    'images': ['https://example.invalid/$numIid.jpg'],
    'skus': skus,
  },
  'pricing': {
    'displayPrice': price,
    'skuPrices': {
      if (pricePerSku)
        for (final sku in skus) sku['sku_id']: {'displayPrice': price},
    },
    'quantityTiers': tiers,
  },
};

/// One purchasable combination, with the live count the seller publishes.
Map<String, dynamic> skuJson({
  required String skuId,
  required String colour,
  String size = 'S',
  int? quantity,
  String specId = 'spec-1',
}) => {
  'sku_id': skuId,
  'spec_id': specId,
  'quantity': quantity,
  'image_url': 'https://example.invalid/$skuId.jpg',
  'variant_parts': [
    {'name': 'Color', 'value': colour},
    {'name': 'Size', 'value': size},
  ],
};

/// A line as an old order carries it: a label, never a SKU.
///
/// `ServerOrderItem` has no SKU column, so this is exactly as lossy as the
/// real thing -- which is the point of validating by label.
const _jacket = CartLine(
  productId: 'p-1',
  variantLabel: 'Blush pink / S',
  title: 'Ice silk jacket',
  unitPrice: 1130,
  quantity: 2,
);

/// Points the validator at a fixed set of records.
void stubDetails(Map<String, Map<String, dynamic>> byId, {List<String>? asked}) {
  ReorderValidator.instance.fetch = (id) async {
    asked?.add(id);
    final body = byId[id];
    if (body == null) {
      throw const ApiError(statusCode: 404, message: 'not found');
    }
    return body;
  };
}

void main() {
  tearDown(() {
    ReorderValidator.instance.fetch = (_) async => const {};
  });

  group('a line that is still for sale', () {
    test('is available, and carries the SKU the order never had', () async {
      stubDetails({
        'p-1': detailJson(
          skus: [
            skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 40),
          ],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.available);
      expect(item.isBuyable, isTrue);
      // Recovered from today's catalogue. Without it the server has a colour
      // name and nothing it can actually order upstream.
      expect(item.line!.skuId, 'sku-9');
      expect(item.line!.specId, 'spec-1');
      expect(item.line!.quantity, 2, reason: 'the quantity that was ordered');
      expect(item.needsAttention, isFalse);
    });

    test('the ordered line itself is never what reaches the cart', () async {
      stubDetails({
        'p-1': detailJson(
          price: 1130,
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 40)],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      // Same product, same variant, but a different object: the one built from
      // the live record. The old reorder added `order.lines` directly, which
      // is how a month-old price got into a new cart.
      expect(identical(item.line, item.ordered), isFalse);
      expect(item.ordered.skuId, isNull, reason: 'the order had none');
    });
  });

  group('a price that moved', () {
    test('is reported with both figures', () async {
      stubDetails({
        'p-1': detailJson(
          price: 1260,
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 40)],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.priceChanged);
      expect(item.orderedPrice, 1130);
      expect(item.currentPrice, 1260);
      expect(item.priceDelta, 130);
      // Still buyable. A price rise is something to see, not a refusal.
      expect(item.isBuyable, isTrue);
    });

    test('counts when it fell, too', () async {
      stubDetails({
        'p-1': detailJson(
          price: 900,
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 40)],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.priceChanged);
      expect(item.priceDelta, -230);
    });

    test('the ladder is re-read, so a bulk quantity reprices', () async {
      stubDetails({
        'p-1': detailJson(
          price: 1130,
          // Not priced SKU by SKU, so the bulk ladder is what governs.
          pricePerSku: false,
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 900)],
          tiers: [
            {'min_quantity': 1, 'displayPrice': 1130},
            {'min_quantity': 50, 'displayPrice': 980},
          ],
        ),
      });

      const bulk = CartLine(
        productId: 'p-1',
        variantLabel: 'Blush pink / S',
        title: 'Ice silk jacket',
        unitPrice: 1130,
        quantity: 60,
      );

      final [item] = await ReorderValidator.instance.validate([bulk]);

      // The rung the quantity reaches, from today's ladder.
      expect(item.line!.unitPrice, 980);
      expect(item.line!.appliedTierFrom, 50);
    });

    test('a variant priced on its own is charged that, not the ladder', () async {
      // The product page's rule, carried over rather than reinvented: a SKU
      // the seller prices individually is charged at its own figure and does
      // not step down the bulk ladder. A reordered line and one added by hand
      // from the product page must agree about this, or the same goods cost
      // two different amounts depending on how they reached the cart.
      stubDetails({
        'p-1': detailJson(
          price: 1130,
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 900)],
          tiers: [
            {'min_quantity': 1, 'displayPrice': 1130},
            {'min_quantity': 50, 'displayPrice': 980},
          ],
        ),
      });

      const bulk = CartLine(
        productId: 'p-1',
        variantLabel: 'Blush pink / S',
        title: 'Ice silk jacket',
        unitPrice: 1130,
        quantity: 60,
      );

      final [item] = await ReorderValidator.instance.validate([bulk]);

      expect(item.line!.unitPrice, 1130, reason: 'the SKU\'s own price');
      expect(item.line!.tiers, isEmpty, reason: 'not on the ladder');
    });
  });

  group('stock', () {
    test('a withdrawn colourway is out of stock, not unavailable', () async {
      stubDetails({
        'p-1': detailJson(
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 0)],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.outOfStock);
      expect(item.isBuyable, isFalse);
    });

    test('fewer left than were ordered offers what is left', () async {
      stubDetails({
        'p-1': detailJson(
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 1)],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.outOfStock);
      expect(item.available, 1);
      // Two were ordered and one is left: the one is still buyable, and saying
      // so is more use than refusing the line outright.
      expect(item.line!.quantity, 1);
    });

    test('a seller who publishes no count is not treated as empty', () async {
      // Null stock is "they did not say". Reading it as zero would refuse
      // every listing that omits the field.
      stubDetails({
        'p-1': detailJson(
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink')],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.available);
      expect(item.available, isNull);
    });
  });

  group('what is no longer there', () {
    test('a 404 means the listing is gone', () async {
      stubDetails(const {});

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.unavailable);
      expect(item.isBuyable, isFalse);
    });

    test('a 200 carrying success:false also means gone', () async {
      // The 1688 service reports a missing product both ways. The envelope
      // decodes tolerantly, so without the explicit check this became a record
      // full of defaults and read as available.
      ReorderValidator.instance.fetch = (_) async => const {
        'success': false,
        'error': 'item not found',
      };

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.unavailable);
    });

    test('a network failure is unknown, never discontinued', () async {
      // The distinction this whole enum exists for. Telling somebody their
      // goods no longer exist because the wifi dropped is the worst answer
      // this screen can give.
      ReorderValidator.instance.fetch = (_) async =>
          throw const ApiError(statusCode: null, message: 'no connection');

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.unknown);
      expect(item.needsAttention, isFalse, reason: 'nothing was established');
    });

    test('a variant that is gone leaves the product alone', () async {
      stubDetails({
        'p-1': detailJson(
          skus: [skuJson(skuId: 'sku-2', colour: 'Ivory', quantity: 40)],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.status, ReorderStatus.variantGone);
      // Never silently swapped for the ivory. A different colourway is a
      // different physical good, and substituting one is the thing the spec
      // forbids without the shop's own replacement logic.
      expect(item.isBuyable, isFalse);
    });
  });

  group('the seller\'s minimum', () {
    test('a raised floor lifts the quantity rather than failing', () async {
      stubDetails({
        'p-1': detailJson(
          minOrder: 10,
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 500)],
        ),
      });

      final [item] = await ReorderValidator.instance.validate([_jacket]);

      expect(item.line!.quantity, 10, reason: 'two is below the new floor');
      expect(item.line!.minOrder, 10);
    });
  });

  group('a whole order', () {
    test('one product is asked about once, however many lines', () async {
      final asked = <String>[];
      stubDetails({
        'p-1': detailJson(
          skus: [
            skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 40),
            skuJson(skuId: 'sku-8', colour: 'Ivory', quantity: 40),
          ],
        ),
      }, asked: asked);

      await ReorderValidator.instance.validate([
        _jacket,
        const CartLine(
          productId: 'p-1',
          variantLabel: 'Ivory / S',
          title: 'Ice silk jacket',
          unitPrice: 1130,
        ),
      ]);

      expect(asked, ['p-1'], reason: 'two variants of one listing, one fetch');
    });

    test('one dead line does not take the others down', () async {
      stubDetails({
        'p-1': detailJson(
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 40)],
        ),
      });

      final items = await ReorderValidator.instance.validate([
        _jacket,
        const CartLine(productId: 'gone', title: 'Suspender dress', unitPrice: 1808),
      ]);

      expect(items, hasLength(2));
      expect(items[0].status, ReorderStatus.available);
      expect(items[1].status, ReorderStatus.unavailable);
    });

    test('results come back in the order the lines were given', () async {
      stubDetails({
        'p-1': detailJson(
          skus: [skuJson(skuId: 'sku-9', colour: 'Blush pink', quantity: 40)],
        ),
        'p-2': detailJson(numIid: 'p-2', title: 'Suspender dress', price: 1808),
      });

      final items = await ReorderValidator.instance.validate([
        const CartLine(productId: 'p-2', title: 'Suspender dress', unitPrice: 1808),
        _jacket,
      ]);

      expect(items[0].ordered.productId, 'p-2');
      expect(items[1].ordered.productId, 'p-1');
    });
  });
}

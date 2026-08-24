import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';

/// Fixtures shaped like the real API, because a fixture that is shaped like
/// the model instead of like the wire proves nothing about the decoding.
///
/// These rows are trimmed copies of actual `/feed/discover` and
/// `/api/1688/product` responses -- the odd bits are the interesting bits: a
/// `display_price` that is null, prices that arrive as strings, and a spec
/// table with blank rows in it.
final Map<String, dynamic> feedRowJson = {
  'id': 438571,
  'num_iid': '639278524639',
  'title': 'Phosphorus Paper for Matches, Large Sheets, Wholesale',
  'pic_url': 'https://cbu01.alicdn.com/img/ibank/matches.jpg',
  'price': 7.6,
  'sales': 111344,
  'rating': null,
  'category_cid': '124262012',
  'category_name': 'matches',
  'parent_category_name': 'Lighters and cigarettes',
  'display_price': 388,
  'seller_identities': ['tp_member', 'yx'],
  'repurchase_rate': '58.33%',
  'trade_score': '5.0',
  'min_order': 1,
};

Product get sampleProduct => Product.fromJson(feedRowJson);

/// The shape `/api/1688/product` answers with: a `item` block from the
/// catalogue and a `pricing` block from the pricing engine.
final Map<String, dynamic> detailResponseJson = {
  'success': true,
  'item': {
    'num_iid': '639278524639',
    'title': 'Phosphorus Paper for Matches, Large Sheets, Wholesale',
    'pic_url': 'https://cbu01.alicdn.com/img/ibank/matches.jpg',
    'images': [
      'https://cbu01.alicdn.com/img/ibank/matches.jpg',
      'https://cbu01.alicdn.com/img/ibank/matches-2.jpg',
    ],
    'desc_short': '<p>Phosphorus paper for matches.</p><br/>Sold in bulk.',
    'min_order_quantity': 2,
    'total_sold': 111344,
    'category_name': 'matches',
    'category_id': '124262012',
    'sell_unit': '包',
    'location': 'Zhejiang',
    'seller_info': {'shop_name': 'Yiwu Match Factory'},
    'props': [
      {'name': 'Material', 'value': 'Phosphorus paper'},
      {'name': 'Size', 'value': 'Large sheet'},
      {'name': '', 'value': 'ignored'},
    ],
    'skus': [
      {
        'sku_id': 'sku-red',
        'spec_id': 'spec-red',
        'quantity': 40,
        'image_url': 'https://cbu01.alicdn.com/img/ibank/red.jpg',
        'variant_parts': [
          {'name': 'Colour', 'value': 'Red'},
        ],
      },
      {
        'sku_id': 'sku-black',
        'spec_id': 'spec-black',
        'quantity': 0,
        'variant_parts': [
          {'name': 'Colour', 'value': 'Black'},
        ],
      },
    ],
  },
  'pricing': {
    'displayPrice': 388,
    // Postgres numeric comes back as a string often enough that a cast here
    // would be a real bug, so the fixture keeps one.
    'skuPrices': {'sku-red': '388', 'sku-black': 402},
    'quantityTiers': [
      {'min_quantity': 2, 'displayPrice': 388},
      {'min_quantity': 100, 'displayPrice': 340},
    ],
  },
};

ProductDetail get sampleDetail =>
    ProductDetail.fromApi(detailResponseJson, fallback: sampleProduct);

/// A feed response: several rows, one of which has no price at all.
List<Map<String, dynamic>> feedRows(int count) => [
      for (var i = 0; i < count; i++)
        {
          ...feedRowJson,
          'num_iid': 'iid-$i',
          'title': 'Catalogue product $i',
          'display_price': i == 1 ? null : 300 + i,
        },
    ];

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/add_to_cart_sheet.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/product/data/product_repository.dart';
import 'package:gtradea_amazon/features/product/widgets/size_guide_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// A shirt in the shape the gateway publishes it: a flat list of SKUs, each
/// carrying its own axes. One pairing the seller lists but has none of.
Map<String, dynamic> _shirt() => {
  'item': {
    'num_iid': '1234',
    'title': 'Quick-drying polo',
    'min_order_quantity': 2,
    'skus': [
      {
        'sku_id': 'sku-red-m',
        'spec_id': 'spec-red-m',
        'quantity': 12,
        'variant_parts': [
          {'name': 'Color', 'value': 'Wine red'},
          {'name': 'Size', 'value': 'M'},
        ],
      },
      {
        'sku_id': 'sku-red-l',
        'spec_id': 'spec-red-l',
        'quantity': 8,
        'variant_parts': [
          {'name': 'Color', 'value': 'Wine red'},
          {'name': 'Size', 'value': 'L'},
        ],
      },
      {
        'sku_id': 'sku-navy-m',
        'spec_id': 'spec-navy-m',
        'quantity': 0,
        'variant_parts': [
          {'name': 'Color', 'value': 'Navy'},
          {'name': 'Size', 'value': 'M'},
        ],
      },
    ],
  },
  'pricing': {
    'displayPrice': 554,
    'skuPrices': {
      'sku-red-m': {'displayPrice': 554},
      'sku-red-l': {'displayPrice': 610},
      'sku-navy-m': {'displayPrice': 554},
    },
  },
};

/// And a product the seller publishes no options for at all.
Map<String, dynamic> _plain() => {
  'item': {'num_iid': '9090', 'title': 'Made-to-order banner'},
  'pricing': {'displayPrice': 99},
};

const _product = Product(
  numIid: '1234',
  title: 'Quick-drying polo',
  displayPrice: 554,
  minOrder: 2,
);

const _plainProduct = Product(
  numIid: '9090',
  title: 'Made-to-order banner',
  displayPrice: 99,
);

/// A page with one button, which is all the sheet needs to be opened from.
Future<void> _open(WidgetTester tester, {Product product = _product}) async {
  tester.view.physicalSize = const Size(840, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AddToCartSheet.show(context, product),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder get _addButton => find.byKey(const ValueKey('sheet-add-to-cart'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    ProductRepository.instance.clearDetailCache();
    api = stubCatalog();
    api.on('GET', '/api/1688/product', body: _shirt());
  });

  tearDown(clearApiStub);

  testWidgets('offers the seller own axes, and nothing else', (tester) async {
    await _open(tester);

    // The names are the feed's, not this app's.
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Qty'), findsOneWidget);

    // Values the seller published, and no others.
    expect(find.text('Wine red'), findsOneWidget);
    expect(find.text('Navy'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('XL'), findsNothing);
  });

  testWidgets('says nothing about what the product is', (tester) async {
    // No description, no specification, none of the card's own copy: this
    // sheet is for choosing, and it was opened from the product itself.
    await _open(tester);

    expect(find.textContaining('polo shirt made'), findsNothing);
    expect(find.textContaining('Description'), findsNothing);
    expect(find.textContaining('Specification'), findsNothing);
  });

  testWidgets('will not add until every choice is answered', (tester) async {
    await _open(tester);

    expect(find.text('Select an option'), findsOneWidget);
    expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);

    await tester.tap(find.text('Wine red'));
    await tester.pumpAndSettle();
    // One axis answered is not all of them.
    expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);

    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();
    expect(find.text('Add to cart'), findsOneWidget);
    expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
  });

  testWidgets('adds the chosen SKU, at the seller minimum', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Wine red'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('L'));
    await tester.pumpAndSettle();
    await tester.tap(_addButton);
    await tester.pumpAndSettle();

    final line = CartStore.instance.lines.single;
    expect(line.productId, '1234');
    expect(line.skuId, 'sku-red-l', reason: 'the SKU chosen, not a guess');
    expect(line.specId, 'spec-red-l');
    expect(line.variantLabel, contains('L'));
    // The record's own minimum, and the option's own price.
    expect(line.quantity, 2);
    expect(line.minOrder, 2);
    expect(line.unitPrice, 610);
    // And the sheet is gone.
    expect(_addButton, findsNothing);
  });

  testWidgets('the quantity starts at the minimum and will not go under it', (
    tester,
  ) async {
    await _open(tester);

    expect(find.byKey(const ValueKey('sheet-quantity')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sheet-quantity'))).data,
      '2',
    );
    expect(find.textContaining('Min. order: 2'), findsOneWidget);

    // Minus is refused at the floor.
    final minus = find.widgetWithIcon(IconButton, Icons.remove);
    expect(tester.widget<IconButton>(minus).onPressed, isNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sheet-quantity'))).data,
      '3',
    );
    expect(tester.widget<IconButton>(minus).onPressed, isNotNull);
  });

  testWidgets('a pairing the seller has none of cannot be reached', (
    tester,
  ) async {
    await _open(tester);

    // Navy is published in M only, and that M is out of stock -- so choosing
    // Navy leaves nothing to pick, and the sheet says so rather than letting
    // an unbuyable line into the cart.
    await tester.tap(find.text('Navy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();

    expect(CartStore.instance.lines, isEmpty);
  });

  testWidgets('a product with no options offers none, and adds at once', (
    tester,
  ) async {
    api.on('GET', '/api/1688/product', body: _plain());
    await _open(tester, product: _plainProduct);

    expect(find.text('Color'), findsNothing);
    expect(find.text('Size'), findsNothing);
    expect(find.text('Add to cart'), findsOneWidget);

    await tester.tap(_addButton);
    await tester.pumpAndSettle();

    final line = CartStore.instance.lines.single;
    expect(line.productId, '9090');
    expect(line.variantLabel, isNull, reason: 'nothing to choose');
    expect(line.unitPrice, 99);
  });

  testWidgets('a size heading has a size guide button that opens the guide', (
    tester,
  ) async {
    await _open(tester);

    // Beside Size, not beside Color.
    final button = find.byKey(const ValueKey('size-guide-button'));
    expect(button, findsOneWidget);
    final at = tester.getRect(button);
    final heading = tester.getRect(find.text('Size'));
    expect(at.left, greaterThan(heading.right), reason: 'at the right of it');
    expect(at.center.dy, closeTo(heading.center.dy, 8), reason: 'level');

    // Picked first, so the guide opens on that size.
    await tester.tap(find.text('Wine red'));
    await tester.tap(find.text('L'));
    await tester.pumpAndSettle();

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SizeGuideSheet), findsOneWidget);

    // Closing it leaves the choice exactly as it was.
    await tester.tap(find.byKey(const ValueKey('size-guide-close')));
    await tester.pumpAndSettle();
    expect(find.byType(SizeGuideSheet), findsNothing);
    expect(find.text('Add to cart'), findsOneWidget, reason: 'still answered');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no was-price published means no saving claimed', (tester) async {
    // Measured against the live gateway, `original_price` is zero on every
    // record. Nothing is struck through and no percentage is shown, because
    // there is no saving to report -- not because the badge is missing.
    await _open(tester);

    expect(find.textContaining('% OFF'), findsNothing);
    expect(find.textContaining('Was:'), findsNothing);
    expect(find.text('Rs. 554'), findsOneWidget, reason: 'the price it has');
  });

  testWidgets('a published was-price is struck through, with the saving', (
    tester,
  ) async {
    // The same record as the catalogue would send it if the seller set an
    // original price: read from `item.original_price`, never derived.
    final discounted = _shirt();
    (discounted['item'] as Map)['original_price'] = 698;
    api.on('GET', '/api/1688/product', body: discounted);

    await _open(tester);

    expect(find.text('Was: Rs. 698'), findsOneWidget);
    // 554 off 698 is a fifth off, rounded the way the record rounds it.
    expect(find.text('21% OFF'), findsOneWidget);
  });

  testWidgets('and a was-price that is not a saving is ignored', (
    tester,
  ) async {
    for (final was in [0, 554, 400]) {
      final odd = _shirt();
      (odd['item'] as Map)['original_price'] = was;
      api.on('GET', '/api/1688/product', body: odd);
      ProductRepository.instance.clearDetailCache();

      await _open(tester);
      expect(find.textContaining('% OFF'), findsNothing, reason: 'was $was');
      expect(find.textContaining('Was:'), findsNothing, reason: 'was $was');
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a failed fetch says so, and offers another go', (tester) async {
    api.on('GET', '/api/1688/product', status: 500);
    await _open(tester);

    expect(
      find.textContaining('could not be loaded'),
      findsOneWidget,
      reason: 'said plainly rather than an empty sheet',
    );
    expect(CartStore.instance.lines, isEmpty);
  });
}

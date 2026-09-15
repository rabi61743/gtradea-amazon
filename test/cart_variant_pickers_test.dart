import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_variant_catalogue.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/cart/widgets/cart_variant_pickers.dart';
import 'package:gtradea_amazon/features/product/data/product_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// A product with two axes, in the shape the gateway publishes: `skus` is a
/// flat list and each entry carries its `variant_parts`, one per axis.
///
/// One combination is out of stock, which is what an unreachable pairing looks
/// like in real data -- the seller lists it and has none.
Map<String, dynamic> _detailWithVariants() => {
  'item': {
    'num_iid': '5566778899',
    'title': 'Quick-drying polo',
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
        'sku_id': 'sku-blue-m',
        'spec_id': 'spec-blue-m',
        'quantity': 5,
        'variant_parts': [
          {'name': 'Color', 'value': 'Navy'},
          {'name': 'Size', 'value': 'M'},
        ],
      },
      {
        'sku_id': 'sku-blue-l',
        'spec_id': 'spec-blue-l',
        'quantity': 0,
        'variant_parts': [
          {'name': 'Color', 'value': 'Navy'},
          {'name': 'Size', 'value': 'L'},
        ],
      },
    ],
  },
  // The seller prices the larger size apart, which the line has to pick up.
  'pricing': {
    'displayPrice': 554,
    'skuPrices': {
      'sku-red-m': {'displayPrice': 554},
      'sku-red-l': {'displayPrice': 610},
      'sku-blue-m': {'displayPrice': 554},
      'sku-blue-l': {'displayPrice': 610},
    },
  },
};

/// And one with no options at all.
Map<String, dynamic> _detailWithout() => {
  'item': {'num_iid': '9090909090', 'title': 'Made-to-order banner'},
  'pricing': {'displayPrice': 99},
};

const _polo = CartLine(
  productId: '5566778899',
  title: 'Quick-drying polo',
  unitPrice: 554,
  variantLabel: 'Wine red / M',
  skuId: 'sku-red-m',
  specId: 'spec-red-m',
  quantity: 2,
);

const _plain = CartLine(
  productId: '9090909090',
  title: 'Made-to-order banner',
  unitPrice: 99,
  quantity: 1,
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(840, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const CartScreen()),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    CartVariantCatalogue.instance.clear();
    ProductRepository.instance.clearDetailCache();
    api = stubCatalog();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/cart', body: const {'items': []});
    api.onCall('POST', '/cart', (call) => reply({...call.json, 'id': 'c-1'}));
    api.on('GET', '/wishlist', body: const {'items': []});
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  /// The dropdown for one axis.
  Finder picker(String label) =>
      find.widgetWithText(DropdownButtonFormField<String>, label);

  group('the variant pickers', () {
    testWidgets('offer the axes the seller published, and no others', (
      tester,
    ) async {
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(_polo);

      await _pump(tester);

      // Named by the feed, not by this app: these two come out of
      // `properties_name`.
      expect(picker('Color'), findsOneWidget);
      expect(picker('Size'), findsOneWidget);
    });

    testWidgets('and show what the line is currently on', (tester) async {
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(_polo);

      await _pump(tester);

      // The line carries sku-red-m, so that is what the two read.
      final colour = tester.widget<DropdownButtonFormField<String>>(
        picker('Color'),
      );
      final size = tester.widget<DropdownButtonFormField<String>>(
        picker('Size'),
      );
      expect(colour.initialValue, 'Wine red');
      expect(size.initialValue, 'M');
    });

    testWidgets('draw nothing for a product with no variants', (tester) async {
      api.on('GET', '/api/1688/product', body: _detailWithout());
      CartStore.instance.add(_plain);

      await _pump(tester);

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('and nothing when the catalogue will not answer', (
      tester,
    ) async {
      // No options invented from a failed request, and the shopper is told
      // rather than left with a line that quietly cannot be changed.
      api.on('GET', '/api/1688/product', status: 500, body: const {});
      CartStore.instance.add(_polo);

      await _pump(tester);

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Options unavailable just now.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('names options the seller wrote around a common prefix', (
    tester,
  ) async {
    // Measured on a live listing: its colours are all written "Polo【...】", and
    // the catalogue's short form cuts every one of them to "Polo". Shortening
    // is a convenience; telling the options apart is the job.
    api.on(
      'GET',
      '/api/1688/product',
      body: {
        'item': {
          'num_iid': '5566778899',
          'title': 'Quick-drying polo',
          'skus': [
            for (final colour in ['Polo【white】', 'Polo【navy】'])
              {
                'sku_id': 'sku-$colour',
                'quantity': 4,
                'variant_parts': [
                  {'name': 'Color', 'value': colour},
                ],
              },
          ],
        },
        'pricing': {'displayPrice': 554},
      },
    );
    CartStore.instance.add(
      const CartLine(
        productId: '5566778899',
        title: 'Quick-drying polo',
        unitPrice: 554,
      ),
    );

    await _pump(tester);

    await tester.tap(picker('Color'));
    await tester.pumpAndSettle();

    expect(find.text('Polo【white】'), findsWidgets);
    expect(find.text('Polo【navy】'), findsWidgets);
    expect(find.text('Polo'), findsNothing);
  });

  group('a line with nothing chosen yet', () {
    /// The same product, added without picking anything -- which is what a
    /// quick add from a rail leaves in the cart, and most of a real basket.
    const bare = CartLine(
      productId: '5566778899',
      title: 'Quick-drying polo',
      unitPrice: 554,
      quantity: 1,
    );

    testWidgets('still gets the pickers, empty', (tester) async {
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(bare);

      await _pump(tester);

      expect(picker('Color'), findsOneWidget);
      expect(picker('Size'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(picker('Color'))
            .initialValue,
        isNull,
        reason: 'nothing has been chosen',
      );
    });

    testWidgets('and waits for the whole set before touching the cart', (
      tester,
    ) async {
      // Half a choice cannot name a SKU. Guessing the other half is a decision
      // for the shopper, and guessing it wrong changes what they pay.
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(bare);

      await _pump(tester);

      await tester.tap(picker('Color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Navy').last);
      await tester.pumpAndSettle();

      expect(CartStore.instance.lines.single.skuId, isNull);
      expect(CartStore.instance.lines.single.unitPrice, 554);

      await tester.tap(picker('Size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('M').last);
      await tester.pumpAndSettle();

      // Both said: now there is a SKU to put in the basket.
      expect(CartStore.instance.lines.single.skuId, 'sku-blue-m');
      expect(CartStore.instance.lines.single.variantLabel, 'Navy / M');
      expect(CartStore.instance.lines.single.quantity, 1);
    });
  });

  group('compact, with a swatch beside each colour', () {
    test('a colour name finds its plain colour, and only a plain one', () {
      expect(colourNamed('Wine red'), const Color(0xFF7B1E3A));
      expect(colourNamed('Navy'), const Color(0xFF1F2A44));
      expect(colourNamed('Polo【black】'), const Color(0xFF212121));
      expect(colourNamed('深蓝色'), const Color(0xFF1E88E5));
      // No colour word: no indicator, rather than a guessed one.
      expect(colourNamed('M'), isNull);
      expect(colourNamed('Lanolin soap*1'), isNull);
      // A word inside another word is not that colour.
      expect(colourNamed('Bluetooth'), isNull);
    });

    testWidgets('each selector is one line, not a labelled box', (
      tester,
    ) async {
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(_polo);

      await _pump(tester);

      for (final axis in ['Color', 'Size']) {
        final height = tester.getSize(picker(axis)).height;
        expect(height, lessThanOrEqualTo(40), reason: '$axis is $height tall');
        // Still big enough to hit.
        expect(height, greaterThanOrEqualTo(32), reason: axis);
      }
    });

    testWidgets('the colour has a swatch and the size does not', (
      tester,
    ) async {
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(_polo);

      await _pump(tester);

      // The chosen colour, in the closed control.
      expect(find.byKey(const ValueKey('swatch:Wine red')), findsOneWidget);
      expect(find.byKey(const ValueKey('swatch:M')), findsNothing);

      await tester.tap(picker('Color'));
      await tester.pumpAndSettle();

      // And beside every colour in the open list, named in the seller's words.
      expect(find.byKey(const ValueKey('swatch:Navy')), findsWidgets);
      expect(find.text('Navy'), findsWidgets);
    });

    /// The polo, with a photograph on every SKU and its colours renamed.
    Map<String, dynamic> photographed({required Map<String, String> names}) {
      final detail = _detailWithVariants();
      final item = detail['item'] as Map<String, dynamic>;
      for (final sku in (item['skus'] as List).cast<Map<String, dynamic>>()) {
        final part = (sku['variant_parts'] as List).first as Map;
        final original = part['value'] as String;
        part['value'] = names[original] ?? original;
        sku['image_url'] =
            'https://cbu01.alicdn.com/img/${original == 'Navy' ? 'navy' : 'red'}.jpg';
      }
      return detail;
    }

    testWidgets('uses the SKU photograph for a name with no colour in it', (
      tester,
    ) async {
      api.on(
        'GET',
        '/api/1688/product',
        body: photographed(
          names: {'Wine red': 'Floral print', 'Navy': 'Striped print'},
        ),
      );
      CartStore.instance.add(
        const CartLine(
          productId: '5566778899',
          title: 'Quick-drying polo',
          unitPrice: 554,
          skuId: 'sku-red-m',
          specId: 'spec-red-m',
        ),
      );

      await _pump(tester);

      final swatch = find.byKey(const ValueKey('swatch:Floral print'));
      expect(swatch, findsOneWidget);
      expect(
        find.descendant(of: swatch, matching: find.byType(Image)),
        findsOneWidget,
        reason: 'the picture, since the name says no colour',
      );
    });

    testWidgets('but a colour name gets a plain dot even with a photo', (
      tester,
    ) async {
      // Sellers often photograph every colourway together and crop it per
      // SKU; at 14pt those crops look alike, and the dot is what tells "Wine
      // red" from "Navy".
      api.on('GET', '/api/1688/product', body: photographed(names: const {}));
      CartStore.instance.add(_polo);

      await _pump(tester);

      final swatch = find.byKey(const ValueKey('swatch:Wine red'));
      expect(swatch, findsOneWidget);
      expect(
        find.descendant(of: swatch, matching: find.byType(Image)),
        findsNothing,
        reason: 'a dot, not the photo',
      );
    });
  });

  group('choosing one', () {
    testWidgets('swaps the line and keeps the quantity', (tester) async {
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(_polo);

      await _pump(tester);

      await tester.tap(picker('Size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('L').last);
      await tester.pumpAndSettle();

      final line = CartStore.instance.lines.single;
      expect(line.skuId, 'sku-red-l');
      expect(line.specId, 'spec-red-l');
      expect(line.variantLabel, contains('L'));
      // The variant's own price, which the feed prices apart.
      expect(line.unitPrice, 610);
      // What the shopper chose was which one, not how many.
      expect(line.quantity, 2);
      expect(CartStore.instance.lines, hasLength(1));
    });

    testWidgets('writes it to the account', (tester) async {
      signInForTest();
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(_polo);

      await _pump(tester);
      api.calls.clear();

      await tester.tap(picker('Color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Navy').last);
      await tester.pumpAndSettle();

      // A new row for the new SKU: the old colourway is a different good, not
      // an edit of this one.
      final posted = api.calls.where(
        (c) => c.method == 'POST' && c.path == '/cart',
      );
      expect(posted, isNotEmpty);
      expect(CartStore.instance.lines.single.skuId, 'sku-blue-m');
    });

    testWidgets('refuses a combination the seller does not stock', (
      tester,
    ) async {
      // Navy exists and L exists; Navy in L has none left. The pairing is
      // shown so the shopper can see it is a real option, and cannot be taken.
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      CartStore.instance.add(
        const CartLine(
          productId: '5566778899',
          title: 'Quick-drying polo',
          unitPrice: 554,
          variantLabel: 'Navy / M',
          skuId: 'sku-blue-m',
          specId: 'spec-blue-m',
        ),
      );

      await _pump(tester);

      await tester.tap(picker('Size'));
      await tester.pumpAndSettle();

      final large = tester
          .widgetList<DropdownMenuItem<String>>(
            find.byType(DropdownMenuItem<String>),
          )
          .where((item) => item.value == 'L');
      expect(large, isNotEmpty);
      expect(
        large.every((item) => !item.enabled),
        isTrue,
        reason: 'out of stock in this colour',
      );
    });

    testWidgets('says so when the account will not take the change', (
      tester,
    ) async {
      // The row for the new SKU is refused. The choice still stands on the
      // device -- it is the account's copy that did not land -- and the picker
      // says so where the change was made rather than only in the page banner.
      signInForTest();
      api.on('GET', '/api/1688/product', body: _detailWithVariants());
      api.on('POST', '/cart', status: 500, body: const {'message': 'nope'});
      CartStore.instance.add(_polo);

      await _pump(tester);

      await tester.tap(picker('Size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('L').last);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(CartVariantPickers),
          matching: find.textContaining('Not saved to your account'),
        ),
        findsOneWidget,
      );
      expect(CartStore.instance.lines.single.skuId, 'sku-red-l');
    });
  });
}

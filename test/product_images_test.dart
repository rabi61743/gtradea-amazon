import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/product_detail_images.dart';
import 'package:gtradea_amazon/features/product/widgets/product_gallery.dart';
import 'package:gtradea_amazon/features/product/widgets/product_section_panel.dart';

import 'support/catalog.dart';

Map<String, dynamic> get _liveBody => jsonDecode(
  File('test/fixtures/real_two_axis_product.json').readAsStringSync(),
) as Map<String, dynamic>;

/// A response shaped like the live one, with the image fields under test
/// substituted. Everything else is the real payload.
/// The live listing, with a specification table added: the real payload
/// carries none, and the specification panel is about showing one.
ProductDetail _withSpecs() => _detailWith(
  props: const [
    {'name': 'Brand', 'value': 'Other/other'},
    {'name': 'Model', 'value': 'T50'},
  ],
);

ProductDetail _detailWith({
  List<String>? images,
  List<String>? descImages,
  String? description,
  List<Map<String, String>>? props,
}) {
  final body = _liveBody;
  final item = Map<String, dynamic>.from(body['item'] as Map);
  if (images != null) {
    item['images'] = images;
    item['pic_url'] = images.isEmpty ? null : images.first;
  }
  if (descImages != null) item['desc_images'] = descImages;
  // This payload happens to carry no specifications, so a test about the
  // specification panel has to put some in.
  if (props != null) item['props'] = props;
  if (description != null) item['description'] = description;
  return ProductDetail.fromApi({
    ...body,
    'item': item,
  }, fallback: sampleProduct);
}

Future<void> _pumpPage(WidgetTester tester, ProductDetail detail) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(product: sampleProduct, detail: detail),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
  });

  group('detail images, from the record', () {
    test('reads every picture out of the seller\'s description markup', () {
      // The live listing carries 21 of them in <img src="..."> tags inside the
      // very blurb this page renders as text -- pictures the page was
      // throwing away.
      final detail = ProductDetail.fromApi(_liveBody, fallback: sampleProduct);

      expect(detail.detailImages, hasLength(21));
      expect(
        detail.detailImages.every((u) => u.startsWith('https://')),
        isTrue,
      );
    });

    test('prefers desc_images, which is the field meant for it', () {
      // Measured empty on every product sampled, so the markup is what
      // actually works today -- but this is the right field, and it wins the
      // moment the service starts filling it.
      final detail = _detailWith(
        descImages: const ['https://cdn.invalid/published-1.jpg'],
      );

      expect(detail.detailImages, ['https://cdn.invalid/published-1.jpg']);
    });

    test('never repeats a photograph the gallery is already showing', () {
      const shared = 'https://cdn.invalid/shared.jpg';
      final detail = _detailWith(
        images: const [shared],
        descImages: const [shared, 'https://cdn.invalid/extra.jpg'],
      );

      expect(detail.images, contains(shared));
      expect(detail.detailImages, ['https://cdn.invalid/extra.jpg']);
    });

    test('a listing with no detail photography gets an empty list', () {
      final detail = _detailWith(descImages: const [], description: 'No tags.');
      expect(detail.detailImages, isEmpty);
    });

    test('ignores a src that is not a fetchable URL', () {
      // Vendor markup carries data: URIs and protocol-relative paths, and a
      // gallery entry the app cannot load is a blank panel.
      final detail = _detailWith(
        descImages: const [],
        description:
            '<img src="data:image/gif;base64,R0lGOD"/>'
            '<img src="//cdn.invalid/protocol-relative.jpg"/>'
            '<img src="https://cdn.invalid/real.jpg"/>',
      );

      expect(detail.detailImages, ['https://cdn.invalid/real.jpg']);
    });
  });

  group('the gallery', () {
    testWidgets('offers a thumbnail for every photograph the seller sent', (
      tester,
    ) async {
      final detail = ProductDetail.fromApi(_liveBody, fallback: sampleProduct);
      await _pumpPage(tester, detail);

      // Five gallery photographs, which is what this backend returns for every
      // product sampled.
      expect(detail.images, hasLength(5));
      expect(
        find.descendant(
          of: find.byKey(galleryThumbnailsKey),
          matching: find.byType(InkWell),
        ),
        findsNWidgets(5),
      );
      expect(find.text('Photos 1/5'), findsOneWidget);
    });

    testWidgets('tapping a thumbnail brings that photograph forward', (
      tester,
    ) async {
      await _pumpPage(tester, _withSpecs());

      await tester.tap(
        find
            .descendant(
              of: find.byKey(galleryThumbnailsKey),
              matching: find.byType(InkWell),
            )
            .at(2),
      );
      // Two pumps: one to start the 220ms slide and one to land it, both well
      // short of the four-second auto-advance. Settling instead would wait out
      // the rotation the tap restarts -- that is the intended behaviour and is
      // asserted directly in the gallery's own suite; this test is about the
      // tap reaching the right photograph.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Photos 3/5'), findsOneWidget);
    });

    testWidgets('a single photograph gets no strip at all', (tester) async {
      // One thumbnail under one picture is a control that cannot change
      // anything.
      await _pumpPage(
        tester,
        _detailWith(images: const ['https://cdn.invalid/only.jpg']),
      );

      // Asserted on the strip itself rather than on "no tappable thing in the
      // gallery": the search-this-image control is also an InkWell, and it is
      // offered on a single photograph as much as on twenty.
      expect(find.byKey(galleryThumbnailsKey), findsNothing);
      expect(find.text('Photos 1/1'), findsNothing);
    });
  });

  group('the specification and detail-image panels', () {
    /// Scrolls the panel heading into view.
    Future<void> reveal(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        400,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 60,
      );
      await tester.pump();
    }

    testWidgets('both are panels, and both start closed', (tester) async {
      await _pumpPage(tester, _withSpecs());

      await reveal(tester, find.text('Specifications'));

      expect(find.byType(ProductSectionPanel), findsNWidgets(2));
      expect(find.text('Specifications'), findsOneWidget);
      expect(find.text('Detail images'), findsOneWidget);
      // The count is the seller's, so a shopper knows how much there is to
      // look at before opening it.
      expect(find.text('21'), findsOneWidget);
      // Closed: neither body is built.
      expect(find.byType(ProductDetailImages), findsNothing);
    });

    testWidgets('opening Specifications shows the seller own table', (
      tester,
    ) async {
      await _pumpPage(tester, _withSpecs());

      await reveal(tester, find.text('Specifications'));
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();

      // Scoped to the panel: the page also shows a summary of the same
      // specifications higher up, which an unscoped finder would match.
      expect(
        find.descendant(
          of: find.byType(ProductSectionPanel),
          matching: find.text('T50'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('opening Detail images shows them', (tester) async {
      await _pumpPage(tester, _withSpecs());

      await reveal(tester, find.text('Detail images'));
      await tester.ensureVisible(find.text('Detail images'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detail images'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailImages), findsOneWidget);
    });

    testWidgets('the two open independently of each other', (tester) async {
      // Panels, not tabs: opening one no longer closes the other.
      await _pumpPage(tester, _withSpecs());

      await reveal(tester, find.text('Specifications'));
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();

      // The open specification table pushed the second heading past the end
      // of what is built, so it has to be scrolled to again.
      await reveal(tester, find.text('Detail images'));
      await tester.ensureVisible(find.text('Detail images'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detail images'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailImages), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ProductSectionPanel),
          matching: find.text('T50'),
        ),
        findsOneWidget,
        reason: 'the specification panel is still open',
      );
    });

    testWidgets('a panel left open is still open when scrolled back to', (
      tester,
    ) async {
      // The product page is a lazy list: it destroys a section once it has
      // been scrolled well past, and an ExpansionTile keeps its open/closed
      // state in a controller it builds and disposes with itself. Without
      // somewhere outside the tile to remember, the panel a shopper opened is
      // shut again by the time they scroll back to it -- which reads as the
      // dropdown simply not working.
      //
      // Driven here rather than through the whole page so the tile is really
      // destroyed: `cacheExtent: 0` leaves nothing built off screen, which is
      // the condition the page reaches once a listing is long enough.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              children: const [
                ProductSectionPanel(
                  title: 'Specifications',
                  child: Text('T50'),
                ),
                SizedBox(height: 4000),
                Text('the foot of the page'),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();
      expect(find.text('T50'), findsOneWidget, reason: 'opened to begin with');

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(
        find.text('Specifications'),
        findsNothing,
        reason: 'scrolled past, so the tile is destroyed',
      );

      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();

      expect(
        find.text('T50'),
        findsOneWidget,
        reason: 'the panel the shopper opened is still open',
      );
    });

    testWidgets('a listing with no detail images gets no second panel', (
      tester,
    ) async {
      // A panel that opens onto nothing is a control with nowhere to go.
      await _pumpPage(
        tester,
        _detailWith(
          descImages: const [],
          description: 'No tags.',
          props: const [
            {'name': 'Model', 'value': 'T50'},
          ],
        ),
      );

      await reveal(tester, find.text('Specifications'));

      expect(find.byType(ProductSectionPanel), findsOneWidget);
      expect(find.text('Detail images'), findsNothing);
    });
  });
}

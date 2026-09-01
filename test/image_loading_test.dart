import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/images/app_images.dart';
import 'package:gtradea_amazon/core/images/image_urls.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/widgets/product_gallery.dart';
import 'package:gtradea_amazon/shared/widgets/artwork_panel.dart';

/// The shapes the live backend actually serves, copied from what it returned
/// rather than invented. Asserting against a made-up URL would prove only that
/// the function works on made-up URLs.
const _product =
    'https://cbu01.alicdn.com/img/ibank/O1CN011tXI4H21QQq8Ihh1g_!!953856979-0-cib.jpg';
const _pexels =
    'https://images.pexels.com/photos/1536619/pexels-photo-1536619.jpeg'
    '?auto=compress&cs=tinysrgb&w=300';
const _banner =
    'https://go.gtradea.com/media/banners/1783419622849032825-71iioj.png';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

/// Every network URL a rendered tree is asking for.
List<String> _requested(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((i) => AppImages.urlOf(i.image))
    .whereType<String>()
    .toList();

void main() {
  group('asking the CDN for a size', () {
    test('picks the smallest variant that covers the drawn width', () {
      // A subcategory circle is 68pt, which is about 204 physical pixels on a
      // 3x phone -- the 250 rung. A product card is 170pt, about 510 -- the
      // 600 rung. Measured on one real image: 320,428 bytes becomes 15,322 and
      // 59,852 respectively.
      expect(
        sizedImageUrl(_product, width: 204),
        '${_product}_250x250q75.jpg_.webp',
      );
      expect(
        sizedImageUrl(_product, width: 510),
        '${_product}_600x600q80.jpg_.webp',
      );
    });

    test('an exact rung takes that rung, not the next one up', () {
      expect(sizedImageUrl(_product, width: 250), contains('_250x250'));
      expect(sizedImageUrl(_product, width: 251), contains('_400x400'));
    });

    test('past the largest rung it asks for the original', () {
      // The gallery and the zoom viewer. A downscaled variant is the wrong
      // answer on the one surface where somebody is looking closely.
      expect(sizedImageUrl(_product, width: 4000), _product);
    });

    test('hosts that publish no transform are left alone', () {
      // Pexels already serves a 9 KB thumbnail, and the banner host is a plain
      // file server that returns the identical 1.9 MB PNG whatever query is
      // appended. Rewriting either would be guessing at a contract that is not
      // there -- and a guess turns a working picture into a 404.
      expect(sizedImageUrl(_pexels, width: 204), _pexels);
      expect(sizedImageUrl(_banner, width: 1200), _banner);
    });

    test('a URL that already carries a size is not sized twice', () {
      const sized = '${_product}_400x400.jpg';
      expect(sizedImageUrl(sized, width: 204), sized);
    });

    test('nonsense in, the same thing out', () {
      expect(sizedImageUrl('', width: 200), '');
      expect(sizedImageUrl(_product, width: 0), _product);
      expect(sizedImageUrl(_product, width: -5), _product);
      expect(sizedImageUrl('not a url at all', width: 200), 'not a url at all');
    });
  });

  group('the provider', () {
    test('bounds the decode as well as the download', () {
      final provider = AppImages.of(_product, width: 100, devicePixelRatio: 3);

      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, 300);
      expect(AppImages.urlOf(provider), contains('_400x400'));
    });

    test('sized:false asks for the original but still decodes small', () {
      // The retry path. Dropping the width instead of the suffix would fix a
      // broken picture by loading a full-resolution bitmap into a 100pt tile,
      // which trades one bug for a worse one.
      final provider = AppImages.of(
        _product,
        width: 100,
        devicePixelRatio: 3,
        sized: false,
      );

      expect(AppImages.urlOf(provider), _product);
      expect((provider as ResizeImage).width, 300);
    });

    test('no width means the original, undecoded', () {
      final provider = AppImages.of(_product);

      expect(provider, isNot(isA<ResizeImage>()));
      expect(AppImages.urlOf(provider), _product);
    });
  });

  group('what each surface asks for', () {
    testWidgets('a tile asks for a variant sized to itself', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Center(
            child: SizedBox(
              width: 68,
              height: 68,
              child: ArtworkPanel(
                icon: Icons.category,
                tint: Color(0xFF267488),
                imageUrl: _product,
                knownWidth: 68,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_requested(tester).single, contains('_250x250'));
    });

    testWidgets('the gallery asks for the original', (tester) async {
      // The assertion that stops a well-meaning optimisation downscaling the
      // one surface a shopper opens in order to look closely.
      await tester.pumpWidget(_wrap(const ProductGallery(images: [_product])));
      await tester.pump();

      expect(_requested(tester).single, _product);
    });

    testWidgets('a failed variant retries the original before giving up', (
      tester,
    ) async {
      // Under the test binding every network image fails, which is exactly the
      // condition this guards: the CDN changing its suffix format must not
      // turn every product photo in the app into a coloured panel.
      await tester.pumpWidget(
        _wrap(
          const Center(
            child: SizedBox(
              width: 68,
              height: 68,
              child: ArtworkPanel(
                icon: Icons.category,
                tint: Color(0xFF267488),
                imageUrl: _product,
                knownWidth: 68,
              ),
            ),
          ),
        ),
      );

      // First attempt: the small variant.
      await tester.pump();
      expect(_requested(tester).single, contains('_250x250'));

      // It fails, and the panel asks again for the file it knows exists.
      await tester.pump();
      await tester.pump();
      expect(_requested(tester).single, _product);
    });
  });

  test('the suite is not talking to the real disk cache', () {
    // flutter_test_config.dart installs this for every file. Without it the
    // cache would be reaching for platform channels the test binding does not
    // provide, and every image would fail for a reason unrelated to the widget
    // under test.
    expect(AppImages.providerOverride, isNotNull);
  });
}

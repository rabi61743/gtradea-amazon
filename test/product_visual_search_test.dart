import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/product_gallery.dart';
import 'package:gtradea_amazon/features/search/data/visual_search_repository.dart';
import 'package:gtradea_amazon/features/search/data/visual_search_store.dart';
import 'package:gtradea_amazon/features/search/presentation/visual_search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

Map<String, dynamic> _match(int i) => {
  'num_iid': 'match-$i',
  'title': 'Similar product $i',
  'pic_url': 'https://cdn.invalid/m$i.jpg',
  'price': 120 + i,
};

void main() {
  late FakeApi api;
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('product_visual_search');
    // path_provider is a platform channel with no implementation in a test,
    // so without this the history's documents directory throws and every
    // entry silently fails to save.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // A temp directory the OS clears anyway is not worth failing over.
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    VisualSearchStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on(
      'POST',
      '/api/1688/image-search',
      body: {
        'products': [_match(1), _match(2)],
        'totalResults': 2,
        'page': 1,
        'pageCount': 1,
      },
    );
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductDetailScreen(product: sampleProduct, detail: sampleDetail),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('the icon over the photograph', () {
    testWidgets('is offered on the product page', (tester) async {
      await pumpPage(tester);

      expect(
        find.descendant(
          of: find.byType(ProductGallery),
          matching: find.byIcon(Icons.center_focus_weak),
        ),
        findsOneWidget,
      );
    });

    testWidgets('is left off when nothing can search with it', (tester) async {
      // The gallery is used elsewhere without a handler; the control must not
      // appear where it would do nothing.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProductGallery(images: sampleDetail.images),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.center_focus_weak), findsNothing);
    });
  });

  group('searching with the picture on screen', () {
    testWidgets('sends the catalogue address, not an upload', (tester) async {
      // The service fetches the photograph itself, so nothing is downloaded
      // here and pushed back up as base64.
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.center_focus_weak));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final call = api.calls.firstWhere(
        (c) => c.path.contains('/api/1688/image-search'),
      );
      final body = call.body! as Map;
      expect(body['imageUrl'], sampleDetail.images.first);
      expect(
        body.containsKey('image'),
        isFalse,
        reason: 'the URL half of the contract, not the base64 half',
      );
    });

    testWidgets('shows what came back, as product cards', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.center_focus_weak));
      await tester.pumpAndSettle();

      expect(find.byType(VisualSearchScreen), findsOneWidget);
      expect(find.text('Similar product 1'), findsOneWidget);
      expect(find.text('Similar product 2'), findsOneWidget);
    });

    testWidgets('says so plainly when nothing matches', (tester) async {
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {'products': const [], 'totalResults': 0},
      );
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.center_focus_weak));
      await tester.pumpAndSettle();

      expect(find.textContaining('No'), findsWidgets);
      expect(find.text('Similar product 1'), findsNothing);
    });

    testWidgets('a failure is reported rather than left blank', (tester) async {
      api.on('POST', '/api/1688/image-search', status: 500, body: const {});
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.center_focus_weak));
      await tester.pumpAndSettle();

      expect(find.byType(VisualSearchScreen), findsOneWidget);
      expect(find.text('Similar product 1'), findsNothing);
    });

    testWidgets('tapping twice does not run two searches', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.center_focus_weak));
      await tester.pump();
      // A second tap while the first is opening.
      await tester.tap(
        find.byIcon(Icons.center_focus_weak),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path.contains('/api/1688/image-search')),
        hasLength(1),
      );
    });
  });

  group('it goes into Recent photo searches', () {
    // A 1x1 PNG, standing in for the catalogue photograph the app fetches to
    // keep as the history thumbnail.
    final picture = Uint8List.fromList(const [
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, //
      0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, //
      68, 65, 84, 120, 218, 99, 100, 96, 96, 0, 0, 0, 5, 0, 1, 127, 253, //
      13, 90, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
    ]);

    testWidgets('the searched picture is fetched to keep', (tester) async {
      // It used to be dropped: the history keeps files and this search had
      // only an address, so nothing was written down. Asserted on the fetch
      // rather than on the saved file, because the write is real disk IO that
      // outlives the widget test's clock.
      api.on('GET', sampleDetail.images.first, body: picture);
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.center_focus_weak));
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path.endsWith('matches.jpg')),
        isNotEmpty,
        reason: 'the photograph is collected for the history thumbnail',
      );
    });

    testWidgets('and it is fetched after the results, not before', (
      tester,
    ) async {
      // A thumbnail is worth nothing if it delays what was asked for.
      api.on('GET', sampleDetail.images.first, body: picture);
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.center_focus_weak));
      await tester.pumpAndSettle();

      final paths = api.calls.map((c) => c.path).toList();
      final searched = paths.indexWhere((p) => p.contains('image-search'));
      final fetched = paths.indexWhere((p) => p.endsWith('matches.jpg'));
      expect(searched, isNonNegative);
      expect(fetched, greaterThan(searched));
    });

    testWidgets('a picture that cannot be fetched costs no results', (
      tester,
    ) async {
      // The history is the least important thing on screen.
      api.on('GET', sampleDetail.images.first, status: 404, body: const {});
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.center_focus_weak));
      await tester.pumpAndSettle();

      expect(find.text('Similar product 1'), findsOneWidget);
      expect(VisualSearchStore.instance.items, isEmpty);
    });

    test('recordBytes keeps a file-backed entry, like any other', () async {
      // Every entry is a file so the thumbnail shows without the network and
      // the search can be re-run by handing that file back.
      VisualSearchStore.instance.resetForTest();

      final entry = await VisualSearchStore.instance.recordBytes(
        picture,
        resultCount: 7,
      );

      expect(entry, isNotNull);
      expect(entry!.resultCount, 7);
      expect(entry.imagePath, endsWith('.jpg'));
      expect(File(entry.imagePath).existsSync(), isTrue);
      expect(VisualSearchStore.instance.items.single.id, entry.id);
    });

    test('the newest is first, beside searches from the camera', () async {
      VisualSearchStore.instance.resetForTest();

      final older = await VisualSearchStore.instance.recordBytes(picture);
      final newer = await VisualSearchStore.instance.recordBytes(picture);

      expect(VisualSearchStore.instance.items.map((e) => e.id), [
        newer!.id,
        older!.id,
      ]);
    });
  });

  group('the repository', () {
    test('searchByUrl asks for the address it was given', () async {
      final matches = await VisualSearchRepository.instance.searchByUrl(
        'https://cdn.invalid/thing.jpg',
      );

      final call = api.calls.single;
      final body = call.body! as Map;
      expect(body['imageUrl'], 'https://cdn.invalid/thing.jpg');
      expect(body['page'], 1);
      expect(matches.products, hasLength(2));
      expect(matches.total, 2);
    });

    test('a throttled search says so rather than reporting no matches', () {
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {'rate_limited': true, 'products': const []},
      );

      expect(
        VisualSearchRepository.instance.searchByUrl(
          'https://cdn.invalid/a.jpg',
        ),
        throwsA(isA<Object>()),
      );
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/search/data/image_source_picker.dart';
import 'package:gtradea_amazon/features/search/data/visual_search_repository.dart';
import 'package:gtradea_amazon/features/search/data/visual_search_store.dart';
import 'package:gtradea_amazon/features/search/presentation/visual_search_screen.dart';
import 'package:gtradea_amazon/features/search/widgets/result_card.dart';
import 'package:gtradea_amazon/features/search/widgets/visual_search_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

late FakeApi api;
late Directory tempDir;

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// A real file on disk, because the screen reads and encodes one.
///
/// Synchronous on purpose. `testWidgets` runs its body in a fake-async zone
/// where awaited file I/O never completes, so an async helper here hangs the
/// test before the widget is even pumped -- and a hang reads as a broken suite
/// rather than a failing assertion.
File photo(String name) {
  final file = File('${tempDir.path}/$name');
  // A one-pixel PNG. Small, but genuinely decodable, so Image.file works.
  file.writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
      'hQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  );
  return file;
}

List<Map<String, dynamic>> matchRows(int count) => [
  for (var i = 0; i < count; i++)
    {
      'num_iid': 'match-$i',
      'title': 'Matched product $i',
      'pic_url': 'https://example.invalid/m$i.jpg',
      'display_price': 500 + i,
      'sales': 100,
      // The image-search service names it differently from every other
      // endpoint in the app.
      'min_order_quantity': 5,
    },
];

/// Waits for fire-and-forget deletes to actually land.
Future<void> untilGone(List<File> files) async {
  for (var i = 0; i < 50; i++) {
    if (files.every((f) => !f.existsSync())) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A picker that hands back whatever the test says.
class FakePicker extends ImageSourcePicker {
  FakePicker(this.outcome);
  final PhotoOutcome outcome;
  PhotoSource? asked;

  @override
  Future<PhotoOutcome> pick(PhotoSource source) async {
    asked = source;
    return outcome;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('visual_search_test');

    // path_provider is a platform channel with no implementation in a test, so
    // without this the store's documents directory throws and every history
    // entry silently fails to save.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    // Best effort: Windows keeps a handle on a file the image cache decoded,
    // so the delete can lose a race with the runner shutting down. A temp
    // directory the OS will clear anyway is not worth failing a suite over.
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VisualSearchStore.instance.resetForTest();
    api = stubCatalog();
  });

  tearDown(() => ImageSourcePicker.instance = PlatformImageSourcePicker());

  group('talking to the real service', () {
    test('posts the image to the 1688 endpoint, not /api/v1', () async {
      // The service lives outside the versioned API. Sending this to
      // /api/v1/image-search is a 404 that looks like a missing feature.
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {
          'products': matchRows(3),
          'totalResults': 660,
          'page': 1,
          'pageCount': 33,
          'from_cache': false,
        },
      );

      final result = await VisualSearchRepository.instance.search(
        'BASE64',
        pageSize: 20,
      );

      final call = api.calls.last;
      expect(call.path, '/api/1688/image-search');
      expect(call.json['image'], 'BASE64');
      expect(call.json['page'], 1);
      expect(call.json['pageSize'], 20);

      expect(result.products, hasLength(3));
      expect(result.total, 660);
      expect(result.hasMore, isTrue);
    });

    test('carries the minimum order across the naming difference', () async {
      // `min_order_quantity` here, `min_order` everywhere else. Missing it puts
      // a five-unit wholesale line in the cart as a single item.
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {'products': matchRows(1)},
      );

      final result = await VisualSearchRepository.instance.search('x');
      expect(result.products.single.minOrder, 5);
    });

    test(
      'drops rows with no id or no title rather than rendering blanks',
      () async {
        api.on(
          'POST',
          '/api/1688/image-search',
          body: {
            'products': [
              ...matchRows(1),
              {'num_iid': '', 'title': 'No id'},
              {'num_iid': 'x', 'title': ''},
            ],
          },
        );

        final result = await VisualSearchRepository.instance.search('x');
        expect(result.products.map((p) => p.numIid), ['match-0']);
      },
    );

    test(
      'a throttled search says so rather than reporting no matches',
      () async {
        // Told "nothing matched", a shopper simply tries again and is throttled
        // harder.
        api.on(
          'POST',
          '/api/1688/image-search',
          body: {'products': const [], 'rate_limited': true},
        );

        await expectLater(
          VisualSearchRepository.instance.search('x'),
          throwsA(isA<ApiError>()),
        );
      },
    );

    test('an empty answer is no matches, not a failure', () async {
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {'products': const [], 'totalResults': 0},
      );

      final result = await VisualSearchRepository.instance.search('x');
      expect(result.products, isEmpty);
      expect(result.hasMore, isFalse);
    });
  });

  /// Mounts the screen and lets its search actually run.
  ///
  /// The `pumpWidget` has to happen inside `runAsync` too, not just the wait.
  /// `initState` starts a file read and an HTTP call, and a future created
  /// inside the fake-async zone belongs to that zone forever -- so pumping
  /// outside and waiting inside leaves the screen on its spinner no matter how
  /// long the wait is.
  Future<void> pumpSearch(WidgetTester tester, File image) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(VisualSearchScreen(image: image, record: false)),
      );
      // Polled rather than a fixed sleep: the chain is a file read, an encode
      // and a round trip, and guessing the total is how a test turns flaky on
      // a slower machine.
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (find.text('Matching your photo').evaluate().isEmpty) break;
      }
    });
    await tester.pump();
  }

  group('the results screen', () {
    testWidgets('shows the photo it searched with, and the matches', (
      tester,
    ) async {
      _tall(tester);
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {'products': matchRows(4), 'totalResults': 660},
      );

      await pumpSearch(tester, photo('a.png'));

      // The query is a picture, not a word, so it stays on screen to judge the
      // results against.
      expect(find.byType(Image), findsWidgets);
      expect(find.textContaining('660 similar'), findsOneWidget);
      expect(find.byType(ResultCard), findsNWidgets(4));
    });

    testWidgets('says it is working while the service thinks', (tester) async {
      _tall(tester);
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {'products': matchRows(1)},
      );

      await tester.pumpWidget(
        _wrap(VisualSearchScreen(image: photo('b.png'), record: false)),
      );
      await tester.pump();

      // Recognition takes a few seconds against production, which is long
      // enough that an unexplained spinner reads as a hang.
      expect(find.text('Matching your photo'), findsOneWidget);
    });

    testWidgets('a photo that matched nothing offers a way forward', (
      tester,
    ) async {
      _tall(tester);
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {'products': const [], 'totalResults': 0},
      );

      await pumpSearch(tester, photo('c.png'));

      expect(find.text('Nothing matched this photo'), findsOneWidget);
      expect(find.text('Try another photo'), findsOneWidget);
    });

    testWidgets('a failed search says why and offers a retry', (tester) async {
      _tall(tester);
      api.on(
        'POST',
        '/api/1688/image-search',
        status: 500,
        body: {'error': 'recognition is down'},
      );

      await pumpSearch(tester, photo('d.png'));

      expect(find.text('recognition is down'), findsOneWidget);
      expect(find.text('Try again'), findsWidgets);
    });
  });

  group('the history', () {
    test('keeps a copy of the picture, not the picker\'s file', () async {
      // image_picker hands back something in a cache directory the OS may
      // clear whenever it likes, so a history pointing at those would show
      // broken thumbnails within days.
      api.on(
        'POST',
        '/api/1688/image-search',
        body: {'products': matchRows(2)},
      );

      final source = photo('e.png');
      final entry = await VisualSearchStore.instance.record(
        source,
        resultCount: 2,
      );

      expect(entry, isNotNull);
      expect(entry!.imagePath, isNot(source.path));
      expect(entry.file.existsSync(), isTrue);
      expect(entry.resultCount, 2);
    });

    test('survives a restart', () async {
      final entry = await VisualSearchStore.instance.record(photo('f.png'));
      expect(entry, isNotNull);
      await Future<void>.delayed(Duration.zero);

      VisualSearchStore.instance.resetForTest();
      await VisualSearchStore.instance.load();

      expect(VisualSearchStore.instance.items, hasLength(1));
      expect(VisualSearchStore.instance.items.single.id, entry!.id);
    });

    test(
      'an entry whose picture has gone is dropped, not shown broken',
      () async {
        final entry = await VisualSearchStore.instance.record(photo('g.png'));
        await Future<void>.delayed(Duration.zero);
        await entry!.file.delete();

        VisualSearchStore.instance.resetForTest();
        await VisualSearchStore.instance.load();

        expect(VisualSearchStore.instance.items, isEmpty);
      },
    );

    test('removing one deletes its picture too', () async {
      final entry = await VisualSearchStore.instance.record(photo('h.png'));
      final file = entry!.file;
      expect(file.existsSync(), isTrue);

      await VisualSearchStore.instance.remove(entry.id);
      await untilGone([file]);

      expect(VisualSearchStore.instance.items, isEmpty);
      expect(file.existsSync(), isFalse);
    });

    test('clearing removes every picture', () async {
      final a = await VisualSearchStore.instance.record(photo('i.png'));
      final b = await VisualSearchStore.instance.record(photo('j.png'));

      await VisualSearchStore.instance.clear();
      // The deletes are fire-and-forget so clearing does not block the UI, so
      // this waits for the effect rather than for a fixed moment -- a single
      // zero-delay passed alone and lost the race under a full-suite run.
      await untilGone([a!.file, b!.file]);

      expect(VisualSearchStore.instance.items, isEmpty);
      expect(a.file.existsSync(), isFalse);
      expect(b.file.existsSync(), isFalse);
    });

    test(
      'old entries fall off the end, and take their files with them',
      () async {
        final files = <File>[];
        for (var i = 0; i < VisualSearchStore.limit + 2; i++) {
          final entry = await VisualSearchStore.instance.record(
            photo('k$i.png'),
          );
          files.add(entry!.file);
        }
        await Future<void>.delayed(Duration.zero);

        await untilGone([files.first]);
        expect(
          VisualSearchStore.instance.items,
          hasLength(VisualSearchStore.limit),
        );
        // Otherwise the directory grows without bound behind a list of twelve.
        expect(files.first.existsSync(), isFalse);
        expect(files.last.existsSync(), isTrue);
      },
    );
  });

  group('choosing a source', () {
    testWidgets('offers the camera and the gallery', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const Scaffold(body: VisualSearchSheet())));
      await tester.pumpAndSettle();

      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });

    testWidgets('asks the picker for the source that was tapped', (
      tester,
    ) async {
      _tall(tester);
      final picker = FakePicker(const PhotoCancelled());
      ImageSourcePicker.instance = picker;

      await tester.pumpWidget(_wrap(const Scaffold(body: VisualSearchSheet())));
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(picker.asked, PhotoSource.gallery);
    });

    testWidgets('a refused camera explains and offers settings', (
      tester,
    ) async {
      _tall(tester);
      ImageSourcePicker.instance = FakePicker(
        const PhotoPermissionDenied(
          source: PhotoSource.camera,
          permanently: false,
        ),
      );

      await tester.pumpWidget(_wrap(const Scaffold(body: VisualSearchSheet())));
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('camera is off for this app'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('backing out of the camera says nothing at all', (
      tester,
    ) async {
      // Cancelling is not a failure and must not be reported as one.
      _tall(tester);
      ImageSourcePicker.instance = FakePicker(const PhotoCancelled());

      await tester.pumpWidget(_wrap(const Scaffold(body: VisualSearchSheet())));
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(find.text('Open settings'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('a device with no camera says so and leaves the gallery', (
      tester,
    ) async {
      _tall(tester);
      ImageSourcePicker.instance = FakePicker(const PhotoNoCamera());

      await tester.pumpWidget(_wrap(const Scaffold(body: VisualSearchSheet())));
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no camera available'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });
  });
}

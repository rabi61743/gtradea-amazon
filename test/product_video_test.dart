import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/widgets/product_gallery.dart';
import 'package:gtradea_amazon/features/product/widgets/product_video.dart';

import 'support/catalog.dart';

Map<String, dynamic> get _liveBody => jsonDecode(
  File('test/fixtures/real_two_axis_product.json').readAsStringSync(),
) as Map<String, dynamic>;

/// The live payload with the video fields substituted, everything else real.
ProductDetail _detailWith({Object? hasVideo, Object? videoUrl}) {
  final body = _liveBody;
  final item = Map<String, dynamic>.from(body['item'] as Map);
  item['has_video'] = hasVideo;
  item['video_url'] = videoUrl;
  return ProductDetail.fromApi({
    ...body,
    'item': item,
  }, fallback: sampleProduct);
}

const _url = 'https://cloud.video.taobao.com/play/u/1/p/1/e/6/t/1/123.mp4';

/// Records what the gallery asked for.
///
/// The controller itself is the real one -- it is what carries the headers the
/// CDN demands, and faking it would fake away the thing most worth asserting.
/// What is faked is the *platform* beneath it, below.
class _FakeControllers extends VideoControllers {
  _FakeControllers();

  final requested = <String>[];
  Map<String, String> headers = const {};

  @override
  VideoPlayerController create(String url) {
    requested.add(url);
    final controller = PlatformVideoControllers().create(url);
    headers = controller.httpHeaders;
    return controller;
  }
}

/// A video platform that answers instead of a device.
///
/// `flutter_test` has no video plugin, so without this every controller fails
/// to initialise -- which the gallery correctly reads as "no video" and drops
/// the slide. That is the right behaviour and is asserted on its own; this
/// exists so the *present* video can be tested too.
///
/// It reports a ready 4:3 clip of ten seconds and does nothing else, which is
/// all the widget reads.
class _FakePlatform extends VideoPlayerPlatform {
  final _events = StreamController<VideoEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => 1;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    // Announced on the next turn, because the controller subscribes to the
    // stream after this returns.
    scheduleMicrotask(
      () => _events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(640, 480),
        ),
      ),
    );
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events.stream;

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();
}

Widget _wrap(ProductDetail detail) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      child: ProductGallery(images: detail.images, videoUrl: detail.videoUrl),
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeControllers controllers;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    VideoPlayerPlatform.instance = _FakePlatform();
    controllers = _FakeControllers();
    VideoControllers.instance = controllers;
  });

  tearDown(() => VideoControllers.instance = const PlatformVideoControllers());

  group('reading the video off the record', () {
    test('is taken when the server says there is one and where', () {
      final detail = _detailWith(hasVideo: true, videoUrl: _url);
      expect(detail.videoUrl, _url);
    });

    test('the flag alone is not enough', () {
      // A listing claiming a video with no address is a slide that could only
      // fail, so it is not offered.
      expect(_detailWith(hasVideo: true, videoUrl: null).videoUrl, isNull);
      expect(_detailWith(hasVideo: true, videoUrl: '').videoUrl, isNull);
    });

    test('and neither is an address without the flag', () {
      expect(_detailWith(hasVideo: false, videoUrl: _url).videoUrl, isNull);
      expect(_detailWith(hasVideo: null, videoUrl: _url).videoUrl, isNull);
    });

    test('something that is not a URL is refused', () {
      // The same guard every other address on this page goes through: a player
      // pointed at a non-address fails slowly, with a black rectangle.
      expect(
        _detailWith(hasVideo: true, videoUrl: 'coming soon').videoUrl,
        isNull,
      );
    });

    test('the live fixture carries no video, and says so', () {
      // The product this fixture was taken from genuinely has none, which is
      // the ordinary case -- roughly six listings in ten.
      final detail = ProductDetail.fromApi(_liveBody, fallback: sampleProduct);
      expect(detail.videoUrl, isNull);
    });
  });

  group('the request the player makes', () {
    testWidgets('carries the User-Agent the CDN demands', (tester) async {
      // The assertion that keeps the video working. `cloud.video.taobao.com`
      // answers a plain request with HTTP 490 and refuses; with a browser
      // User-Agent it redirects to a signed CDN address that serves the file.
      // ExoPlayer's own default gets the 490, so dropping this header would
      // silently take every product video away.
      _phone(tester);
      final detail = _detailWith(hasVideo: true, videoUrl: _url);
      await tester.pumpWidget(_wrap(detail));
      await tester.pump();

      // The video has its own tab now, so it has to be opened before the
      // player is built and the request goes out.
      await tester.tap(find.text('Video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(controllers.requested, [_url]);
      expect(controllers.headers['User-Agent'], isNotNull);
      expect(controllers.headers['User-Agent'], contains('Mozilla/5.0'));
    });
  });

  group('the video tab', () {
    /// Moves to the video half of the media area.
    Future<void> openVideo(WidgetTester tester) async {
      await tester.tap(find.text('Video'));
      // Explicit pumps, not pumpAndSettle: the player keeps a spinner turning
      // while it loads, and settling would wait for an animation that never
      // ends.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('the photographs are only photographs', (tester) async {
      // The video used to ride along as the last slide. It has its own tab
      // now, so the count on the Photos tab is the seller's image count and
      // nothing is pushed along.
      _phone(tester);
      final detail = _detailWith(hasVideo: true, videoUrl: _url);
      await tester.pumpWidget(_wrap(detail));
      await tester.pump();

      expect(find.text('Photos 1/${detail.images.length}'), findsOneWidget);
      expect(
        find.byType(ProductVideo),
        findsNothing,
        reason: 'the gallery opens on a photograph, not the player',
      );
    });

    testWidgets('both tabs are offered when there is a video', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(_detailWith(hasVideo: true, videoUrl: _url)),
      );
      await tester.pump();

      expect(find.textContaining('Photos'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
    });

    testWidgets('choosing Video plays the seller own file', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(_detailWith(hasVideo: true, videoUrl: _url)),
      );
      await tester.pump();

      await openVideo(tester);

      expect(find.byType(ProductVideo), findsOneWidget);
      expect(controllers.requested, [
        _url,
      ], reason: 'the URL the server gave, not a stand-in');
    });

    testWidgets('and choosing Photos comes back to them', (tester) async {
      _phone(tester);
      final detail = _detailWith(hasVideo: true, videoUrl: _url);
      await tester.pumpWidget(_wrap(detail));
      await tester.pump();

      await openVideo(tester);
      expect(find.byType(ProductVideo), findsOneWidget);

      await tester.tap(find.textContaining('Photos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ProductVideo), findsNothing);
      expect(find.text('Photos 1/${detail.images.length}'), findsOneWidget);
    });

    testWidgets('a listing with no video says so rather than faking one', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(_detailWith(hasVideo: false)));
      await tester.pump();

      // The tab is still offered -- somebody looking for a video should be
      // told there is none rather than left wondering.
      await openVideo(tester);

      expect(find.text('No video for this product'), findsOneWidget);
      expect(find.byType(ProductVideo), findsNothing);
      expect(
        controllers.requested,
        isEmpty,
        reason: 'nothing was invented to play',
      );
    });

    testWidgets('the strip belongs to the photographs', (tester) async {
      // A thumbnail strip under a video is a control about something that is
      // not on screen.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(_detailWith(hasVideo: true, videoUrl: _url)),
      );
      await tester.pump();
      expect(find.byKey(galleryThumbnailsKey), findsOneWidget);

      await openVideo(tester);

      expect(find.byKey(galleryThumbnailsKey), findsNothing);
    });

    testWidgets('does not shift which photograph a tap opens', (tester) async {
      // The viewer shows photographs, and the video is not among them.
      _phone(tester);
      final detail = _detailWith(hasVideo: true, videoUrl: _url);
      final opened = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProductGallery(
                images: detail.images,
                videoUrl: detail.videoUrl,
                onImageTap: opened.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(
        find
            .descendant(
              of: find.byKey(galleryThumbnailsKey),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Image).first);
      await tester.pump();

      expect(opened, [0], reason: 'the first photograph, not the second');
    });
  });

  group('how long a photograph is held', () {
    testWidgets('two and a half seconds, unless the caller says otherwise', (
      tester,
    ) async {
      // Pinned because it is a judgement, not an accident: long enough to
      // judge a colour, short enough to read as a gallery that is moving.
      const gallery = ProductGallery(images: ['https://cdn.invalid/0.jpg']);

      expect(gallery.interval, const Duration(milliseconds: 2500));
    });

    testWidgets('the next photograph arrives on that beat', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ProductGallery(
                images: [
                  'https://cdn.invalid/0.jpg',
                  'https://cdn.invalid/1.jpg',
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Photos 1/2'), findsOneWidget);

      // Just short of the beat, it is still on the first.
      await tester.pump(const Duration(milliseconds: 2300));
      expect(find.text('Photos 1/2'), findsOneWidget);

      // And just past it, on the second.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Photos 2/2'), findsOneWidget);
    });
  });

  group('the rotation', () {
    /// A gallery of photographs alone, which is the ordinary product page.
    Widget photos({int count = 4, Duration? interval, bool stillness = false}) {
      final images = [
        for (var i = 0; i < count; i++) 'https://cdn.invalid/$i.jpg',
      ];
      return MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: stillness),
          child: Scaffold(
            body: SingleChildScrollView(
              child: ProductGallery(
                images: images,
                interval: interval ?? const Duration(seconds: 4),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('moves to the next photograph on its own', (tester) async {
      _phone(tester);
      await tester.pumpWidget(photos());
      await tester.pump();
      expect(find.text('Photos 1/4'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Photos 2/4'), findsOneWidget);
    });

    testWidgets('and stops once it reaches the last one', (tester) async {
      // Forward once through, then it rests. A page that keeps sliding under
      // somebody reading the specifications below is an irritation rather than
      // a feature -- and this is what lets the page settle at all.
      _phone(tester);
      await tester.pumpWidget(photos());
      await tester.pump();

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('Photos 4/4'), findsOneWidget);

      // Well past another two intervals: it does not wrap back to the first.
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Photos 4/4'), findsOneWidget);
    });

    testWidgets('the bar counts down, and restarts on each change', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(photos());
      await tester.pump();

      double barValue() => tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .first
          .value!;

      expect(barValue(), lessThan(0.1), reason: 'starts empty');

      await tester.pump(const Duration(seconds: 2));
      final midway = barValue();
      expect(midway, greaterThan(0.4), reason: 'halfway through the interval');

      // Over the change, and it is back at the beginning for the next one.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Photos 2/4'), findsOneWidget);
      expect(barValue(), lessThan(midway));
    });

    testWidgets('does not run for a single photograph', (tester) async {
      // Nothing to rotate between, so no timer and no bar counting down to a
      // change that will never come.
      _phone(tester);
      await tester.pumpWidget(photos(count: 1));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('and not at all when the reader asked for less movement', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(photos(stillness: true));
      await tester.pump();

      await tester.pump(const Duration(seconds: 9));

      expect(find.text('Photos 1/4'), findsOneWidget, reason: 'it never moved');
    });

    testWidgets('a finger on the picture pauses it, lifting it resumes', (
      tester,
    ) async {
      // The rule this gallery deliberately does not share with the home
      // banner, where one swipe ends the rotation for good -- here manual
      // switching must not break it.
      _phone(tester);
      await tester.pumpWidget(photos());
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await tester.pump(const Duration(seconds: 9));
      expect(
        find.text('Photos 1/4'),
        findsOneWidget,
        reason: 'held, so it waited',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Photos 2/4'),
        findsOneWidget,
        reason: 'and carried on after',
      );
    });

    testWidgets('it does not carry a video off the screen', (tester) async {
      // Rotation belongs to the photographs and stays off while the video is
      // up. Carrying away something somebody is watching is the rudest thing
      // this widget could do.
      _phone(tester);
      final detail = _detailWith(hasVideo: true, videoUrl: _url);
      await tester.pumpWidget(_wrap(detail));
      await tester.pump();

      // Open the video, which has its own tab.
      await tester.tap(find.text('Video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProductVideo), findsOneWidget);

      // Several intervals: nothing carries the player away, and coming back
      // to the photographs finds them where they were left.
      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(ProductVideo), findsOneWidget);

      await tester.tap(find.textContaining('Photos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Photos 1/${detail.images.length}'), findsOneWidget);
    });
  });
}

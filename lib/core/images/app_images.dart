import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'image_urls.dart';

/// Where every network picture in the app comes from.
///
/// Two jobs, and they are separate on purpose:
///
///   * **request** the smallest variant the CDN will serve that still covers
///     what is drawn -- [sizedImageUrl];
///   * **keep** what was downloaded, so it is fetched once ever rather than
///     once per launch.
///
/// The second is the larger win by far. Everything used to go through
/// `Image.network`, which caches in memory only: killing the app threw away
/// every byte, and reopening it re-downloaded the whole storefront. A shopper
/// on a Nepali mobile connection paid for the same photographs every morning.
class AppImages {
  AppImages._();

  /// Swaps the provider out, for tests.
  ///
  /// The disk cache needs `path_provider` and `sqflite` platform channels, and
  /// `flutter_test` supplies neither -- so left alone, every widget test would
  /// be exercising a cache that throws. Tests point this at a plain
  /// [NetworkImage], which the test binding already stubs.
  ///
  /// The same idiom as `ApiClient.overrideDio`: production has one path, and
  /// the seam is stated rather than discovered.
  static ImageProvider Function(String url)? providerOverride;

  /// A provider for [url], sized for a picture drawn [width] logical pixels
  /// wide on a device of [devicePixelRatio].
  ///
  /// Pass no [width] and the original file is requested and decoded at full
  /// size -- which is what the gallery and the zoom viewer want, being the two
  /// places a shopper is deliberately looking closely.
  ///
  /// [sized] governs only what is *asked for*, not what is decoded. The two are
  /// separate because the retry path needs exactly that combination: fetch the
  /// original, because the small variant just failed, but still decode it down
  /// to the tile it is going into. Collapsing them would mean a CDN hiccup
  /// quietly turned every thumbnail into a full-resolution bitmap in memory.
  static ImageProvider of(
    String url, {
    double? width,
    double devicePixelRatio = 1,
    bool sized = true,
  }) {
    final pixels = width == null || !width.isFinite || width <= 0
        ? null
        : (width * devicePixelRatio).round();

    final requested = pixels == null || !sized
        ? url
        : sizedImageUrl(url, width: pixels);

    final override = providerOverride;
    final ImageProvider base = override != null
        ? override(requested)
        : CachedNetworkImageProvider(requested);

    if (pixels == null) return base;

    // Width only. Constraining both would decode to a box of a different shape
    // than the source, and BoxFit.cover is already deciding what gets cropped.
    return ResizeImage(base, width: pixels, allowUpscaling: false);
  }

  /// Reads the URL back out of a provider, whatever it has been wrapped in.
  ///
  /// For tests and for the retry path: a provider here is a [ResizeImage]
  /// around either a [CachedNetworkImageProvider] or, under
  /// [providerOverride], a [NetworkImage]. Callers should not have to know
  /// which.
  static String? urlOf(ImageProvider provider) => switch (provider) {
    ResizeImage(:final imageProvider) => urlOf(imageProvider),
    CachedNetworkImageProvider(:final url) => url,
    NetworkImage(:final url) => url,
    _ => null,
  };
}

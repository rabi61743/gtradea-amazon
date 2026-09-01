/// Asking a CDN for the size the app is actually going to draw.
///
/// The catalogue's photographs come from Alibaba's CDN at whatever resolution
/// they were uploaded at. Measured across fifty live rows from `/feed/discover`
/// they average about 260 KB, and a product card draws its picture at roughly
/// 510 physical pixels on a 3x phone -- so most of every download is thrown
/// away before it reaches the screen.
///
/// That CDN takes a size and quality suffix, and the difference is not
/// marginal. On one real product image:
///
/// ```text
/// original                    320,428 bytes
/// _600x600q80.jpg_.webp        59,852 bytes   -81%
/// _250x250q75.jpg_.webp        15,322 bytes   -95%
/// ```
///
/// This file is the whole of that knowledge: one pure function, so it is tested
/// as a function rather than through a widget tree.
library;

/// Hosts known to take a size suffix.
///
/// One entry, because one is all the catalogue uses -- all fifty sampled
/// product images were on it. A list rather than a constant so adding a second
/// CDN is a line rather than a rewrite.
const _sizedHosts = {'cbu01.alicdn.com'};

/// The variants worth asking for, smallest first.
///
/// Quality climbs with size on purpose: a 250px thumbnail is being looked at
/// from across a strip and q75 is invisible there, while a 600px card picture
/// is the one a shopper actually studies.
const _rungs = <({int width, String suffix})>[
  (width: 250, suffix: '_250x250q75.jpg_.webp'),
  (width: 400, suffix: '_400x400q75.jpg_.webp'),
  (width: 600, suffix: '_600x600q80.jpg_.webp'),
  (width: 800, suffix: '_800x800q80.jpg_.webp'),
];

/// Matches a size already baked into a URL, e.g. `..._400x400.jpg`.
final _alreadySized = RegExp(r'_\d+x\d+');

/// [url], asking for the smallest variant that covers [width] device pixels.
///
/// Returns [url] unchanged when there is nothing safe to do, which is most of
/// the time and is the point:
///
///   * a host that does not document a transform -- the hero banners live on a
///     plain static file server, which returns byte-for-byte the same 1.9 MB
///     PNG for `?w=800` as for no query at all;
///   * a host that is already serving a thumbnail -- the category pictures come
///     from Pexels with `?w=300` on them and weigh 9 KB;
///   * a URL that already carries a size, so this cannot stack two;
///   * a [width] past the largest rung, where the original is the right answer.
///
/// Guessing at a transform a host has not published would turn working pictures
/// into 404s, and the widget's fallback is a coloured panel that nobody would
/// read as a failure.
String sizedImageUrl(String url, {required int width}) {
  if (url.isEmpty || width <= 0) return url;

  final uri = Uri.tryParse(url);
  if (uri == null || !_sizedHosts.contains(uri.host)) return url;

  // Already sized by whoever wrote the row. Appending a second suffix would ask
  // for a resize of a resize.
  if (_alreadySized.hasMatch(uri.path)) return url;

  for (final rung in _rungs) {
    if (width <= rung.width) return '$url${rung.suffix}';
  }

  // Wider than the largest rung: a gallery, or a zoom view. The full file is
  // the right file there.
  return url;
}

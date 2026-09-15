import 'package:flutter/material.dart';

import '../widgets/product_video.dart';

/// Full-screen video viewer: the seller's own file, playing, on black.
///
/// Deliberately the same screen as [ImageViewerScreen] in everything but its
/// contents -- black `Scaffold` whatever the theme, a drag down to leave, and
/// the close cross in the same corner at the same size. A shopper who has
/// opened a photograph here should not have to learn a second way out for the
/// video, and the two sitting side by side in the same gallery is exactly
/// where a difference would show.
///
/// The URL comes in from the record the product page already loaded; nothing
/// here fetches or invents an address of its own.
class VideoViewerScreen extends StatelessWidget {
  const VideoViewerScreen({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Drag down to leave, as the photographs do. There is no zoom to
          // guard against here, so unlike the image viewer the gesture is
          // never suppressed -- but the direction and the key shape match, so
          // the two screens feel like one thing.
          Dismissible(
            key: const ValueKey('video-viewer'),
            direction: DismissDirection.vertical,
            onDismissed: (_) => Navigator.of(context).pop(),
            child: Center(
              // The player keeps the file's own proportions and letterboxes
              // itself against the black, so a portrait clip fills the height
              // and a wide one fills the width -- neither is stretched to fit
              // a screen it was not shot for.
              //
              // No bottom inset: the gallery's tab pill is not on this screen,
              // so the controls sit where they belong.
              child: ProductVideo(
                url: url,
                autoPlay: true,
                // It failed to open. The viewer is a screen the shopper asked
                // for, so unlike the inline slide it says so by closing rather
                // than by sitting black -- the gallery behind it drops the
                // slide on the same signal.
                onUnavailable: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

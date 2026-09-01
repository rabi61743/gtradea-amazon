import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';

/// How a video controller is made.
///
/// A seam rather than a direct constructor call, for the same reason
/// `ImageSourcePicker.instance` is one: there is no video platform under
/// `flutter_test`, so a widget that built a real controller could not be
/// rendered in a test at all.
abstract class VideoControllers {
  const VideoControllers();

  static VideoControllers instance = const PlatformVideoControllers();

  VideoPlayerController create(String url);
}

class PlatformVideoControllers extends VideoControllers {
  const PlatformVideoControllers();

  /// What the CDN insists on hearing.
  ///
  /// Measured, and the whole feature turns on it. `cloud.video.taobao.com`
  /// answers a plain request with **HTTP 490** and
  /// `{"code":1112,"message":"非法访问"}` -- "illegal access". With a browser
  /// User-Agent the same URL answers **302** to a signed `caiyuanbao.alicdn.com`
  /// address that serves **206 Partial Content, video/mp4, Accept-Ranges:
  /// bytes**, which is everything a player needs.
  ///
  /// ExoPlayer's own default is `ExoPlayerLib/...`, which gets the 490. So this
  /// header is not decoration to be tidied away later: without it there is no
  /// video.
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126 Mobile Safari/537.36';

  @override
  VideoPlayerController create(String url) => VideoPlayerController.networkUrl(
    Uri.parse(url),
    httpHeaders: const {'User-Agent': _userAgent},
  );
}

/// The seller's video, with the controls a shopper expects.
///
/// **Fails to silence.** If the CDN refuses or the file will not open, this
/// reports upward through [onUnavailable] and the gallery drops the slide
/// entirely -- there is never a black rectangle or an error message where a
/// picture should be. That matters more here than usual: the address is behind
/// somebody else's hotlink protection, and the day that changes the page should
/// quietly become what it was before videos existed.
class ProductVideo extends StatefulWidget {
  const ProductVideo({
    super.key,
    required this.url,
    this.onUnavailable,
    this.onPlayingChanged,
  });

  final String url;

  /// Called once, when the video turns out not to be playable.
  final VoidCallback? onUnavailable;

  /// Called as playback starts and stops, so the gallery can keep its
  /// auto-advance off while something is playing.
  final ValueChanged<bool>? onPlayingChanged;

  @override
  State<ProductVideo> createState() => _ProductVideoState();
}

class _ProductVideoState extends State<ProductVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  /// Whether the controls are on screen. They fade out while it plays so the
  /// video is not watched through a row of buttons.
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final controller = VideoControllers.instance.create(widget.url);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      controller.addListener(_onTick);
      setState(() => _ready = true);
    } catch (_) {
      // Anything at all: a refusal, a codec the device will not open, a dead
      // connection. All of them mean the same thing to a shopper, and none of
      // them is worth a message on a product page.
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onUnavailable?.call();
    }
  }

  bool _wasPlaying = false;

  void _onTick() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing != _wasPlaying) {
      _wasPlaying = playing;
      widget.onPlayingChanged?.call(playing);
      // Out of the way while it plays, back when it stops.
      if (mounted) setState(() => _showControls = !playing);
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !_ready) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      // Round the clock back to the start once it has finished, so the button
      // plays it again rather than doing nothing at the end.
      if (controller.value.position >= controller.value.duration) {
        controller.seekTo(Duration.zero);
      }
      controller.play();
    }
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null || !_ready) return;
    setState(() => controller.setVolume(controller.value.volume > 0 ? 0 : 1));
  }

  static String _clock(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // The gallery removes the slide on [onUnavailable], so this is only ever
    // seen for the frame in between.
    if (_failed || controller == null) return const SizedBox.shrink();

    if (!_ready) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    final value = controller.value;
    final muted = value.volume == 0;

    return GestureDetector(
      // A tap anywhere brings the controls back rather than only the buttons
      // themselves, which is what every video on a phone does.
      onTap: () => setState(() => _showControls = !_showControls),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                // The file's own shape. Guessing 16:9 letterboxes anything shot
                // for a phone, which is most seller video.
                aspectRatio: value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _Controls(
                  playing: value.isPlaying,
                  muted: muted,
                  position: value.position,
                  duration: value.duration,
                  onPlay: _togglePlay,
                  onMute: _toggleMute,
                  onSeek: (fraction) =>
                      controller.seekTo(value.duration * fraction),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Play, mute, the clock and a scrub bar, drawn in the app's own parts rather
/// than a package's.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.playing,
    required this.muted,
    required this.position,
    required this.duration,
    required this.onPlay,
    required this.onMute,
    required this.onSeek,
  });

  final bool playing;
  final bool muted;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlay;
  final VoidCallback onMute;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = duration.inMilliseconds;
    final progress = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);

    return Stack(
      children: [
        // A scrim behind the buttons only. A full-frame one would dim the video
        // itself, which is the thing being looked at.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 18, 6, 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                _RoundButton(
                  icon: playing ? Icons.pause : Icons.play_arrow,
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: onPlay,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_ProductVideoState._clock(position)} / '
                  '${_ProductVideoState._clock(duration)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => onSeek(
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        ),
                      ),
                      onHorizontalDragUpdate: (details) => onSeek(
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        ),
                      ),
                      child: SizedBox(
                        height: 20,
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(
                                Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _RoundButton(
                  icon: muted ? Icons.volume_off : Icons.volume_up,
                  tooltip: muted ? 'Unmute' : 'Mute',
                  onPressed: onMute,
                ),
              ],
            ),
          ),
        ),
        // The big one, while it is stopped. A paused video with only a small
        // control in the corner reads as a picture that failed to load.
        if (!playing)
          Center(
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPlay,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(Icons.play_arrow, size: 34, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20, color: Colors.white),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

/// The badge laid over the video's thumbnail so the strip says which tile is
/// the video without a caption.
class VideoThumbBadge extends StatelessWidget {
  const VideoThumbBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: const Center(
        child: Icon(Icons.play_circle_fill, size: 22, color: Colors.white),
      ),
    );
  }
}

import 'dart:async';

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
    // The signed address answers 206 with `Accept-Ranges: bytes`, so the
    // player fetches the file in pieces as it goes and starts on the first
    // one. Nothing here asks for the whole video up front, and the options
    // are named rather than left default so that stays true.
    videoPlayerOptions: VideoPlayerOptions(
      // The page's own sound is the only sound: a product video should not
      // silence whatever the shopper already had playing.
      mixWithOthers: true,
    ),
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
///
/// Mounted only when the gallery is actually on its Video tab, so a product
/// page that is never switched over opens no connection to the CDN at all.
class ProductVideo extends StatefulWidget {
  const ProductVideo({
    super.key,
    required this.url,
    this.onUnavailable,
    this.onPlayingChanged,
    this.autoPlay = false,
    this.onRequestFullscreen,
  });

  /// Whether to start as soon as the first frame is ready.
  ///
  /// False inline, where a video that began on its own would be a page that
  /// started talking. True in the full-screen viewer, which is only ever
  /// reached by asking for it.
  final bool autoPlay;

  /// Where a tap goes instead of playing here.
  ///
  /// When this is given the widget is a preview: the real first frame off the
  /// real file, with the play mark over it, and a tap hands off to the
  /// full-screen viewer -- exactly what a photograph in this gallery does.
  /// The controls are not drawn, because the viewer has them.
  final VoidCallback? onRequestFullscreen;

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

  /// Whether the file actually carries sound.
  ///
  /// Asked of the platform rather than assumed. A mute button over a silent
  /// video is a control that looks like it does something and does nothing.
  /// It starts true because that is what the platform cannot contradict yet:
  /// where there is no track API to ask -- the web player has none -- the
  /// control stays, since hiding a working one is the worse of the two
  /// mistakes.
  bool _hasAudio = true;

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
      if (widget.autoPlay) controller.play();
      // After the first frame is available, not before it: this decides
      // whether a button is drawn, and it must not hold up playback.
      unawaited(_probeAudio(controller));
    } catch (_) {
      // Anything at all: a refusal, a codec the device will not open, a dead
      // connection. All of them mean the same thing to a shopper, and none of
      // them is worth a message on a product page.
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onUnavailable?.call();
    }
  }

  /// Whether there is a sound track for the mute button to act on.
  Future<void> _probeAudio(VideoPlayerController controller) async {
    try {
      if (!controller.isAudioTrackSupportAvailable()) return;
      final tracks = await controller.getAudioTracks();
      if (!mounted) return;
      setState(() => _hasAudio = tracks.isNotEmpty);
    } catch (_) {
      // A platform that will not answer leaves the control as it was. Not
      // knowing whether there is sound is not the same as knowing there is
      // none, and only the second is a reason to take the button away.
    }
  }

  bool _wasPlaying = false;

  /// Only what the frame-by-frame value cannot do for itself.
  ///
  /// The clock, the scrub bar and the buffering spinner all read the
  /// controller directly through a [ValueListenableBuilder], so this no longer
  /// calls `setState` on every tick. It used to, and each tick rebuilt the
  /// whole subtree -- the video texture included -- several times a second.
  /// That was most of what made playback stutter and the bar feel stuck.
  void _onTick() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    widget.onPlayingChanged?.call(playing);
    // Out of the way while it plays, back when it stops.
    if (mounted) setState(() => _showControls = !playing);
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
    // No setState: volume lives in the controller's own value, and the
    // controls are built from that.
    controller.setVolume(controller.value.volume > 0 ? 0 : 1);
  }

  void _setSpeed(double speed) {
    final controller = _controller;
    if (controller == null || !_ready) return;
    controller.setPlaybackSpeed(speed);
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

    // A preview: the real opening frame with the play mark over it, and a tap
    // anywhere on it opens the viewer. The same shape a photograph in this
    // gallery has, and for the same reason -- the slide is small, and looking
    // properly happens full screen.
    if (widget.onRequestFullscreen case final open?) {
      return GestureDetector(
        onTap: open,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
              Center(child: BigPlayMark(onTap: open)),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      // A tap anywhere brings the controls back rather than only the buttons
      // themselves, which is what every video on a phone does.
      onTap: () => setState(() => _showControls = !_showControls),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Outside the listener below, and deliberately: the texture is
            // built once and left alone while the clock runs over the top of
            // it. The shape is the file's own -- guessing 16:9 letterboxes
            // anything shot for a phone, which is most seller video.
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) => Stack(
                fit: StackFit.expand,
                children: [
                  // Waiting on the network part-way through, which is a
                  // different thing from a video that has not opened yet --
                  // and worth saying, because a stalled picture with no
                  // spinner reads as a player that has died.
                  if (value.isBuffering)
                    const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  AnimatedOpacity(
                    opacity: _showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: _Controls(
                        playing: value.isPlaying,
                        muted: value.volume == 0,
                        hasAudio: _hasAudio,
                        speed: value.playbackSpeed,
                        position: value.position,
                        duration: value.duration,
                        onPlay: _togglePlay,
                        onMute: _toggleMute,
                        onSpeed: _setSpeed,
                        onSeek: (fraction) =>
                            controller.seekTo(value.duration * fraction),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Play, mute, speed, the clock and a scrub bar, drawn in the app's own parts
/// rather than a package's.
///
/// Stateful for one reason: the finger's position while a drag is in progress.
/// The bar follows that rather than the controller, so a scrub is one seek on
/// lift instead of a seek per pointer move.
class _Controls extends StatefulWidget {
  const _Controls({
    required this.playing,
    required this.muted,
    required this.hasAudio,
    required this.speed,
    required this.position,
    required this.duration,
    required this.onPlay,
    required this.onMute,
    required this.onSpeed,
    required this.onSeek,
  });

  final bool playing;
  final bool muted;
  final bool hasAudio;
  final double speed;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlay;
  final VoidCallback onMute;
  final ValueChanged<double> onSpeed;
  final ValueChanged<double> onSeek;

  /// The speeds offered, slowest first.
  static const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static String speedLabel(double speed) {
    final whole = speed == speed.roundToDouble();
    return '${whole ? speed.toStringAsFixed(0) : speed.toString()}×';
  }

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  /// Where the finger is, as a fraction of the duration, while it is down.
  ///
  /// Null when nothing is being dragged, and then the bar reads the clock as
  /// usual. This exists because the old bar called `seekTo` from
  /// `onHorizontalDragUpdate`, which asked the decoder for a new frame dozens
  /// of times per gesture -- the scrub lurched and the video stalled behind
  /// it. One seek, when the finger lifts.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.duration.inMilliseconds;
    final elapsed = total <= 0
        ? 0.0
        : (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
    final progress = _dragging ?? elapsed;
    // The clock follows the finger too, so a drag says where it is going
    // rather than where it has been.
    final shown = _dragging == null
        ? widget.position
        : widget.duration * _dragging!;

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
                  icon: widget.playing ? Icons.pause : Icons.play_arrow,
                  tooltip: widget.playing ? 'Pause' : 'Play',
                  onPressed: widget.onPlay,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_ProductVideoState._clock(shown)} / '
                  '${_ProductVideoState._clock(widget.duration)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      double at(Offset local) =>
                          (local.dx / constraints.maxWidth).clamp(0.0, 1.0);

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // A tap is a single destination, so it seeks at once.
                        onTapDown: (d) => widget.onSeek(at(d.localPosition)),
                        onHorizontalDragStart: (d) =>
                            setState(() => _dragging = at(d.localPosition)),
                        onHorizontalDragUpdate: (d) =>
                            setState(() => _dragging = at(d.localPosition)),
                        onHorizontalDragEnd: (_) {
                          final target = _dragging;
                          setState(() => _dragging = null);
                          if (target != null) widget.onSeek(target);
                        },
                        onHorizontalDragCancel: () =>
                            setState(() => _dragging = null),
                        child: SizedBox(
                          // Twenty-eight rather than twenty: this is the
                          // control a thumb has to catch on a moving picture,
                          // and the bar it draws is still three tall.
                          height: 28,
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
                      );
                    },
                  ),
                ),
                _SpeedButton(speed: widget.speed, onSpeed: widget.onSpeed),
                // Only where there is sound to mute. A silent file gets no
                // button rather than a dead one.
                if (widget.hasAudio)
                  _RoundButton(
                    icon: widget.muted ? Icons.volume_off : Icons.volume_up,
                    tooltip: widget.muted ? 'Unmute' : 'Mute',
                    onPressed: widget.onMute,
                  ),
              ],
            ),
          ),
        ),
        // The big one, while it is stopped. A paused video with only a small
        // control in the corner reads as a picture that failed to load.
        if (!widget.playing) Center(child: BigPlayMark(onTap: widget.onPlay)),
      ],
    );
  }
}

/// The current speed, and the six to choose from.
///
/// A menu rather than a cycling button: six steps means five taps to get back
/// from 2x, and a shopper who wanted half speed to look at a stitch should not
/// have to pass through every other rate to find it.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.speed, required this.onSpeed});

  final double speed;
  final ValueChanged<double> onSpeed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: speed,
      onSelected: onSpeed,
      position: PopupMenuPosition.over,
      itemBuilder: (context) => [
        for (final option in _Controls.speeds)
          PopupMenuItem<double>(
            value: option,
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option == 1.0
                        ? '${_Controls.speedLabel(option)}  (Normal)'
                        : _Controls.speedLabel(option),
                  ),
                ),
                if (option == speed)
                  Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
              ],
            ),
          ),
      ],
      child: Container(
        // Its own touch target rather than the text's: a label this short is
        // otherwise a few points wide on a moving picture.
        constraints: const BoxConstraints(minWidth: 38, minHeight: 34),
        alignment: Alignment.center,
        child: Text(
          _Controls.speedLabel(speed),
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The play mark laid over a stopped video.
///
/// Shared rather than copied: the inline preview uses it to open the viewer
/// and the viewer's own controls use it to start playing, and the two should
/// not be able to drift into two different marks.
class BigPlayMark extends StatelessWidget {
  const BigPlayMark({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Icon(Icons.play_arrow, size: 34, color: Colors.white),
        ),
      ),
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/images/app_images.dart';
import 'product_video.dart';

/// Swipeable product photography.
///
/// Deliberately carries no product chrome: no save, no share, no rating badge.
/// Those are facts and actions about the product, not about the picture, and
/// putting controls on photography is what made them invisible against a
/// white-background product shot. They live in the pinned app bar and beside
/// the title instead.
///
/// The one overlay that stays is the image counter, which is genuinely about
/// the gallery. A counter rather than dots: dots stop being countable past four
/// or five, and a gallery is exactly where a shopper wants to know how much is
/// left to look at.
/// The thumbnail strip, for tests that need to address it apart from the tabs.
const galleryThumbnailsKey = ValueKey<String>('gallery-thumbnails');

class ProductGallery extends StatefulWidget {
  const ProductGallery({
    super.key,
    required this.images,
    this.videoUrl,
    this.onImageTap,
    this.onSearchImage,
    this.interval = const Duration(milliseconds: 2500),
  });

  final List<String> images;

  /// The seller's video, when the listing has one. Null for most listings, and
  /// null is what keeps the slide, the thumbnail and the whole player off the
  /// page rather than leaving an empty frame.
  final String? videoUrl;

  /// Opens the full-screen viewer at the tapped **photograph** -- the index it
  /// is given counts images only, so a leading video does not shift it.
  final ValueChanged<int>? onImageTap;

  /// Searches the catalogue for the photograph on screen, given its address.
  /// Absent leaves the control off entirely.
  final ValueChanged<String>? onSearchImage;

  /// How long each photograph is shown before the next.
  ///
  /// Two and a half seconds -- the middle of the two-to-three band asked for.
  /// The progress bar under the image runs the same span, so the change is
  /// announced rather than sprung.
  ///
  /// Worth knowing what the number buys: 420ms of it is the slide itself, so
  /// the photograph is actually still for about two seconds. The carousel also
  /// stops at the last slide rather than looping, so a six-photograph listing
  /// is fifteen seconds of motion and then stillness.
  final Duration interval;

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery>
    with SingleTickerProviderStateMixin {
  final _controller = PageController();
  int _index = 0;

  Timer? _timer;

  /// Drives the bar under the picture. Runs the length of one interval and is
  /// restarted from zero on every change, so it always reads "time until the
  /// next one" rather than time since the page opened.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.interval,
  );

  /// True while a finger is on the picture. Rotation waits rather than sliding
  /// out from under somebody looking at something.
  bool _held = false;

  /// True while the video is playing, which stops rotation for as long as it
  /// lasts even though the video slide already does.
  bool _videoPlaying = false;

  bool get _hasVideo => widget.videoUrl != null && !_videoFailed;

  /// Set when the video turns out not to be playable. From then on the gallery
  /// is exactly what it was before videos existed.
  bool _videoFailed = false;

  /// Which tab is showing.
  ///
  /// The video used to be the last slide of the same carousel. It has its own
  /// tab now, so the photographs are only photographs -- their count and their
  /// order are the server's, untouched.
  _MediaTab _tab = _MediaTab.photos;

  /// Slides in the photographs tab: the images, in the order they arrived.
  int get _slideCount => widget.images.length;

  bool get _onVideo => _tab == _MediaTab.video;

  /// Whether the pictures should be turning over right now.
  ///
  /// Five reasons not to, and each is a case somebody would otherwise complain
  /// about: there is nothing to rotate between; **the last slide is already
  /// up**; the reader has asked the system for less movement; a finger is down;
  /// or the video is on screen, and carrying a playing video away after four
  /// seconds is the rudest thing this widget could do.
  bool get _shouldRotate =>
      _tab == _MediaTab.photos &&
      _slideCount > 1 &&
      _index < _slideCount - 1 &&
      !_reducedMotion &&
      !_held &&
      !_onVideo &&
      !_videoPlaying;

  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.of(context).disableAnimations;
    _sync();
  }

  @override
  void didUpdateWidget(ProductGallery old) {
    super.didUpdateWidget(old);
    if (old.images.length != widget.images.length ||
        old.videoUrl != widget.videoUrl) {
      _index = 0;
      _sync();
    }
  }

  /// Starts or stops the clock to match [_shouldRotate].
  void _sync() {
    if (_shouldRotate) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    _progress
      ..duration = widget.interval
      ..forward(from: 0);
    _timer ??= Timer.periodic(widget.interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      // Forward only, and it stops at the end rather than looping back.
      //
      // Deliberate, and the one place this differs from the home banner. The
      // job of an auto-advancing gallery is to say "there is more than one
      // photograph here"; once it has been all the way through, it has said it.
      // A page that keeps sliding under a shopper reading the specifications
      // below is an irritation, not a feature -- and a widget that never rests
      // is one no test of this page can ever wait for.
      //
      // A swipe or a thumbnail tap starts it again from wherever they landed,
      // so manual switching does not end the rotation, which is what was asked
      // for.
      final next = _index + 1;
      if (next >= _slideCount) {
        _stop();
        return;
      }
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _progress.stop();
    _progress.value = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    // Restart the countdown from the picture now on screen, whether it arrived
    // by timer, by swipe or by thumbnail. Anything else leaves the bar
    // describing the previous picture's remaining time.
    _sync();
  }

  /// Brings [i] to the front. Animated rather than jumped, so a thumbnail tap
  /// reads as the same movement a swipe makes.
  void _select(int i) {
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _hold(bool held) {
    if (_held == held) return;
    _held = held;
    _sync();
  }

  void _onVideoUnavailable() {
    if (!mounted || _videoFailed) return;
    // The slide goes, and with it the thumbnail and any chance of an empty
    // player. The gallery becomes what it is for a listing with no video.
    setState(() {
      _videoFailed = true;
      // Nothing to show in that tab any more, so it goes and the photographs
      // come back up rather than leaving an empty player on screen.
      _tab = _MediaTab.photos;
    });
    _sync();
  }

  void _onVideoPlaying(bool playing) {
    if (!mounted || _videoPlaying == playing) return;
    _videoPlaying = playing;
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    // A single slide needs no strip and no bar: one thumbnail under one picture
    // is a control that cannot change anything, and a countdown to a change
    // that will never come is worse than none.
    if (_slideCount < 2 && !_hasVideo) return _main(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _main(context),
        // The strip and the countdown belong to the photographs. On the video
        // tab there is nothing for them to be about, and a bar counting down
        // to a slide change that cannot happen would be a lie.
        if (_tab == _MediaTab.photos && _slideCount > 1) ...[
          // Directly below the image, as the design asks. Drawn at a constant
          // height whether or not it is running, so the page does not jump by
          // two pixels every time the rotation stops and starts.
          _ProgressBar(progress: _progress, running: _shouldRotate),
          const SizedBox(height: 8),
          _Thumbnails(
            // Named so a test can count thumbnails rather than every tappable
            // thing in the gallery -- the tabs are InkWells too.
            key: galleryThumbnailsKey,
            images: widget.images,
            selected: _index,
            // The video is a tab now, not a thumbnail on the end of the strip.
            hasVideo: false,
            onSelected: _select,
          ),
        ],
      ],
    );
  }

  /// Moves between the photographs and the video.
  void _showTab(_MediaTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    // Rotation belongs to the photographs; leaving them stops the clock, and
    // coming back starts it again.
    _sync();
  }

  Widget _main(BuildContext context) {
    final theme = Theme.of(context);

    return AspectRatio(
      // Taller than square: clothing and appliances are both portrait
      // subjects, and cropping them to a square loses the thing being sold.
      aspectRatio: 0.88,
      child: Stack(
        children: [
          ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            // Crossfaded rather than cut: moving between the two is a change
            // of subject, and a hard swap reads as the page reloading.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _tab == _MediaTab.photos
                  ? _photos(context)
                  : KeyedSubtree(
                      key: const ValueKey('video'),
                      child: _video(context),
                    ),
            ),
          ),
          // Top right, clear of the tabs at the foot and of the picture's
          // middle, where the product itself usually sits.
          if (widget.onSearchImage != null &&
              _tab == _MediaTab.photos &&
              widget.images.isNotEmpty)
            Positioned(
              top: 10,
              right: 10,
              child: _SearchThisImage(
                onTap: () => widget.onSearchImage!(widget.images[_index]),
              ),
            ),
          // The tabs, over the foot of the picture as the reference has them.
          // The count rides on the active Photos tab rather than in a chip of
          // its own -- two scrims stacked in one corner was the alternative.
          if (_hasVideo || _slideCount > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Center(
                child: _MediaTabs(
                  tab: _tab,
                  photoLabel: _slideCount > 1
                      ? 'Photos ${_index + 1}/$_slideCount'
                      : 'Photos',
                  // Offered whether or not there is one to play: a shopper
                  // looking for a video should be told there is none rather
                  // than left wondering whether they missed the control.
                  onSelected: _showTab,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The photographs, exactly the carousel this has always been.
  Widget _photos(BuildContext context) {
    // Pointer events rather than a GestureDetector: a swipe belongs to the
    // PageView, and this only needs to know a finger is down so the rotation
    // can wait for it. A recogniser here would compete with the page scroll
    // for the same drag.
    return Listener(
      key: const ValueKey('photos'),
      onPointerDown: (_) => _hold(true),
      onPointerUp: (_) => _hold(false),
      onPointerCancel: (_) => _hold(false),
      child: PageView.builder(
        controller: _controller,
        itemCount: _slideCount,
        onPageChanged: _onPageChanged,
        // Slide i is photograph i: the photographs lead, in the order the
        // server sent them, and nothing shifts them along.
        itemBuilder: _photo,
      ),
    );
  }

  /// The seller's video, or a plain word that there is not one.
  Widget _video(BuildContext context) {
    final theme = Theme.of(context);

    if (!_hasVideo) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 34,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'No video for this product',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ProductVideo(
      url: widget.videoUrl!,
      onUnavailable: _onVideoUnavailable,
      onPlayingChanged: _onVideoPlaying,
    );
  }

  /// One photograph, at [i] counting images only.
  Widget _photo(BuildContext context, int i) {
    final theme = Theme.of(context);

    return GestureDetector(
      // The image index, not the slide index. The viewer shows photographs, so
      // a leading video must not push every one of them along by one.
      onTap: widget.onImageTap == null ? null : () => widget.onImageTap!(i),
      // The original file, deliberately: the gallery is what the zoom view
      // opens from, and a shopper pinching into a thumbnail would be pinching
      // into something the app chose to blur. It still comes through the disk
      // cache, so re-opening a product costs nothing.
      child: Image(
        image: AppImages.of(widget.images[i]),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
      ),
    );
  }
}

/// The countdown to the next photograph, under the picture.
///
/// Always occupies its height, empty when nothing is rotating. A bar that
/// appears and disappears would shift the thumbnails and everything below them
/// each time a finger touched the picture.
/// "Find products that look like this one."
///
/// A scrim rather than a theme surface: it sits on the seller's photography,
/// which can be any colour, and a tinted panel from the palette would vanish
/// over a white product shot.
class _SearchThisImage extends StatelessWidget {
  const _SearchThisImage({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(9),
          child: Icon(
            // The same icon the search bar uses for this, so the two read as
            // one feature rather than two.
            Icons.center_focus_weak,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Which half of the media the shopper is looking at.
enum _MediaTab { photos, video }

/// The pill over the foot of the picture: Photos on the left, Video on the
/// right, the chosen one raised on white.
///
/// Drawn to the reference: one translucent dark track, the active segment a
/// white pill with dark bold text, the inactive one plain white text on the
/// track. The colours are fixed rather than taken from the theme because it
/// sits on the seller's photography, which can be any colour at all -- a
/// surface tint from the palette would vanish over a white product shot.
///
/// The reference also carries a **Variations** segment between the two. It is
/// deliberately not here: the brief that came with the reference says not to
/// add or change variations, and the variant picker below the gallery already
/// does that job.
class _MediaTabs extends StatelessWidget {
  const _MediaTabs({
    required this.tab,
    required this.photoLabel,
    required this.onSelected,
  });

  final _MediaTab tab;

  /// "Photos 3/6" while the photographs are up -- the count rides on the tab
  /// rather than in a chip of its own, which is what the reference shows.
  final String photoLabel;

  final ValueChanged<_MediaTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: photoLabel,
            selected: tab == _MediaTab.photos,
            onTap: () => onSelected(_MediaTab.photos),
          ),
          _Segment(
            label: 'Video',
            selected: tab == _MediaTab.video,
            onTap: () => onSelected(_MediaTab.video),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            // labelMedium rather than labelLarge: the pill sits over the
            // seller's photography and its job is to be legible without
            // taking the picture over.
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.black87 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress, required this.running});

  final Animation<double> progress;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 3,
          child: AnimatedBuilder(
            animation: progress,
            builder: (context, _) => LinearProgressIndicator(
              value: running ? progress.value : 0,
              minHeight: 3,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip under the gallery: every photograph the seller published, with
/// the one on screen marked.
///
/// Horizontal and scrollable rather than wrapped, so a listing with five
/// photographs and a listing with fifteen both cost the page the same height.
class _Thumbnails extends StatelessWidget {
  const _Thumbnails({
    super.key,
    required this.images,
    required this.selected,
    required this.onSelected,
    this.hasVideo = false,
  });

  final List<String> images;
  final int selected;
  final ValueChanged<int> onSelected;

  /// Whether the first tile is the video rather than a photograph.
  final bool hasVideo;

  static const _size = 62.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = images.length + (hasVideo ? 1 : 0);

    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSelected = i == selected;
          final isVideo = hasVideo && i == images.length;
          // The video has no still of its own from the server, so its tile
          // shows the lead photograph under a play badge -- which is what the
          // shopper is about to see anyway.
          final imageIndex = isVideo ? 0 : i;

          return Semantics(
            label: isVideo
                ? 'Video'
                : 'Photo ${imageIndex + 1} of ${images.length}',
            selected: isSelected,
            button: true,
            child: InkWell(
              onTap: () => onSelected(i),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image(
                        // A thumbnail asks the CDN for a thumbnail. The main
                        // view above still requests the original, because that
                        // is what the zoom view opens from.
                        image: AppImages.of(
                          images[imageIndex],
                          width: _size,
                          devicePixelRatio: MediaQuery.devicePixelRatioOf(
                            context,
                          ),
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (isVideo) const VideoThumbBadge(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

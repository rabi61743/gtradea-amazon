import 'package:flutter/material.dart';

/// Full-screen image viewer: swipe between shots, pinch or double-tap to zoom,
/// drag down to dismiss.
///
/// Black background regardless of theme. This is the one screen where the
/// surrounding chrome should disappear so the product is all that is left, and
/// a white surround changes how the colours in the photo read.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<String> images;
  final int initialIndex;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// One controller per page so zoom resets when the shopper moves on, and so
  /// a zoomed page can suppress the dismiss gesture.
  final _transformControllers = <int, TransformationController>{};

  @override
  void dispose() {
    _controller.dispose();
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _transformFor(int index) =>
      _transformControllers.putIfAbsent(index, TransformationController.new);

  bool get _isZoomed {
    final controller = _transformControllers[_index];
    if (controller == null) return false;
    return controller.value.getMaxScaleOnAxis() > 1.01;
  }

  void _handleDoubleTap(int index, TapDownDetails details) {
    final controller = _transformFor(index);
    if (controller.value.getMaxScaleOnAxis() > 1.01) {
      controller.value = Matrix4.identity();
    } else {
      // Zoom about the point that was tapped, not the centre, so a double-tap
      // on a detail brings that detail closer.
      final position = details.localPosition;
      controller.value = Matrix4.identity()
        ..translateByDouble(-position.dx, -position.dy, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Drag down to leave, but only while the image is not zoomed --
          // otherwise panning a zoomed photo would keep closing the viewer.
          Dismissible(
            key: const ValueKey('image-viewer'),
            direction: _isZoomed
                ? DismissDirection.none
                : DismissDirection.vertical,
            onDismissed: (_) => Navigator.of(context).pop(),
            child: PageView.builder(
              controller: _controller,
              // A zoomed page owns the horizontal drag for panning.
              physics: _isZoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: widget.images.length,
              onPageChanged: (i) {
                _transformControllers[_index]?.value = Matrix4.identity();
                setState(() => _index = i);
              },
              itemBuilder: (context, i) => GestureDetector(
                onDoubleTapDown: (details) => _handleDoubleTap(i, details),
                onDoubleTap: () {},
                child: InteractiveViewer(
                  transformationController: _transformFor(i),
                  minScale: 1,
                  maxScale: 4,
                  onInteractionEnd: (_) => setState(() {}),
                  child: Center(
                    child: Image.network(
                      widget.images[i],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => const Icon(
                        Icons.image_not_supported_outlined,
                        size: 48,
                        color: Colors.white54,
                      ),
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                ),
                    ),
                  ),
                ),
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
                  if (widget.images.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_index + 1}/${widget.images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

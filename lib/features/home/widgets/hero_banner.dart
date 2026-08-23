import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';

class BannerItem {
  const BannerItem({
    required this.headline,
    required this.caption,
    required this.cta,
    required this.tint,
    this.imageUrl,
  });

  final String headline;
  final String caption;
  final String cta;
  final Color tint;
  final String? imageUrl;
}

/// Full-width hero carousel that advances on its own, with dot indicators.
///
/// Auto-advance stops the moment the customer touches it and does not resume:
/// a banner that keeps moving under a finger is how people tap the wrong offer.
/// It also stays still when the platform asks for reduced motion, which is what
/// `MediaQuery.disableAnimations` reports.
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.items,
    this.interval = const Duration(seconds: 5),
  });

  final List<BannerItem> items;
  final Duration interval;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _userTookOver = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: MediaQuery is not available yet at
    // initState, and the answer can change while the app is running.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion || _userTookOver || widget.items.length < 2) {
      _stop();
    } else {
      _start();
    }
  }

  void _start() {
    _timer ??= Timer.periodic(widget.interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.items.length;
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
  }

  @override
  void dispose() {
    _stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 168,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is UserScrollNotification) {
                _userTookOver = true;
                _stop();
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _BannerCard(item: widget.items[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 6,
                // The active dot stretches rather than just darkening, so the
                // position is readable at a glance.
                width: i == _index ? 18 : 6,
                decoration: BoxDecoration(
                  color: i == _index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.item});

  final BannerItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = item.imageUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    item.tint.withValues(alpha: 0.92),
                    item.tint.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            if (url != null && url.isNotEmpty)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 150,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 190,
                    child: Text(
                      item.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 190,
                    child: Text(
                      item.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusControl),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Text(
                        item.cta,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: item.tint,
                          fontWeight: FontWeight.w700,
                        ),
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

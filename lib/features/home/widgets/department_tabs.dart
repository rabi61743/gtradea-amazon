import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/shimmer.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/presentation/catalog_visuals.dart';

/// The department strip that sits directly under the search bar.
///
/// Painted on the same teal band as the header rather than on the page, so the
/// two read as one control surface: a shopper's eye goes search bar, then
/// departments, then products, instead of finding a separate slab of chrome
/// wedged between them.
///
/// "For You" leads, and it is not a department -- it is the whole feed, which
/// is where somebody who has not decided yet should land. Selecting anything
/// else changes what is listed below without leaving the page.
class DepartmentTabs extends StatefulWidget {
  const DepartmentTabs({
    super.key,
    required this.categories,
    required this.selectedCid,
    required this.onSelected,
  });

  final List<Category> categories;

  /// Null means "For You".
  final String? selectedCid;

  /// Null for "For You", a department otherwise.
  final ValueChanged<Category?> onSelected;

  /// How many departments the strip offers.
  ///
  /// The catalogue has forty-eight, which is a scroll nobody finishes. These
  /// are the first by the server's own `sort_order` -- the order the storefront
  /// wants them in -- and the rest stay one tap away in "Shop by category".
  static const maxItems = 12;

  /// One item's footprint. Fixed so the strip has a rhythm and the labels line
  /// up, rather than each item being as wide as its own name.
  static const itemWidth = 68.0;
  static const _tile = 38.0;
  static const _labelGap = 4.0;
  static const _underline = 3.0;

  /// The strip's height: tile, gap, one line of label, and the underline.
  ///
  /// One line, not two. This sits above the fold on every page load, and a
  /// second line of label costs fifteen points of the first screen to spell out
  /// department names that ellipsis handles.
  static double heightFor(BuildContext context) {
    final style =
        Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    final line = MediaQuery.textScalerOf(context)
        .scale((style.fontSize ?? 11) * 1.25);
    return _tile + _labelGap + line + 4 + _underline;
  }

  @override
  State<DepartmentTabs> createState() => _DepartmentTabsState();
}

class _DepartmentTabsState extends State<DepartmentTabs> {
  final _controller = ScrollController();

  /// Whether there is anything past the right edge, which decides the fade.
  bool _moreRight = false;
  bool _moreLeft = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // The extents are unknown until the strip has been laid out once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(DepartmentTabs old) {
    super.didUpdateWidget(old);
    if (old.selectedCid != widget.selectedCid) _revealSelected();
    if (old.categories.length != widget.categories.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final left = _controller.position.extentBefore > 1;
    final right = _controller.position.extentAfter > 1;
    if (left != _moreLeft || right != _moreRight) {
      setState(() {
        _moreLeft = left;
        _moreRight = right;
      });
    }
  }

  /// Scrolls the chosen department into view.
  ///
  /// A selection made off-screen -- from a deep link, or after the strip has
  /// been scrolled and the page rebuilt -- would otherwise leave the shopper
  /// looking at a strip where nothing appears selected.
  void _revealSelected() {
    if (!_controller.hasClients) return;
    final index = _indexOfSelected();
    if (index < 0) return;

    const step = DepartmentTabs.itemWidth;
    final viewport = _controller.position.viewportDimension;
    final target = index * step + step / 2 - viewport / 2;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  int _indexOfSelected() {
    final cid = widget.selectedCid;
    // "For You" is index zero and the departments follow it.
    if (cid == null) return 0;
    final shown = _shown();
    for (var i = 0; i < shown.length; i++) {
      if (shown[i].cid == cid) return i + 1;
    }
    return -1;
  }

  List<Category> _shown() =>
      widget.categories.take(DepartmentTabs.maxItems).toList(growable: false);

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown();

    // No colour of its own: the shell paints one gradient behind this strip
    // and the search header above it, so the ramp runs unbroken across the
    // join instead of restarting at it.
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: DepartmentTabs.heightFor(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Everything fits: centre it rather than leaving the whole set
            // hard against the left edge of a tablet or a desktop window.
            final total = (shown.length + 1) * DepartmentTabs.itemWidth;
            final fits = total <= constraints.maxWidth - 16;

            final strip = ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: fits
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: fits ? (constraints.maxWidth - total) / 2 : 8,
              ),
              itemCount: shown.length + 1,
              itemBuilder: (context, i) {
                // The selected tab's shadow is not drawn here. It used to be
                // wrapped around this first tab, which meant "For You" carried
                // it whether or not it was the one chosen -- and no other tab
                // could ever have it. It is one layer under the strip now, and
                // it slides. See [_SelectionShadow].
                if (i == 0) {
                  return _Tab(
                    label: 'For You',
                    icon: Icons.shopping_bag_outlined,
                    selected: widget.selectedCid == null,
                    onTap: () => widget.onSelected(null),
                  );
                }
                final category = shown[i - 1];
                return _Tab(
                  label: category.name,
                  icon: iconForCategory(category.name),
                  selected: category.cid == widget.selectedCid,
                  onTap: () => widget.onSelected(category),
                );
              },
            );

            // Under the strip, not over it: the tabs are drawn on top of
            // their own shadow, exactly as they were when it was wrapped
            // around one of them.
            final layered = Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: _SelectionShadow(
                      slot: _indexOfSelected(),
                      leading: fits ? (constraints.maxWidth - total) / 2 : 8.0,
                      controller: _controller,
                    ),
                  ),
                ),
                strip,
              ],
            );

            if (fits) return layered;

            // Says there is more without spending a row on a scrollbar: the
            // departments fade out at whichever edge still has more behind it.
            //
            // The tabs are faded rather than covered. This used to paint a
            // short wash of the band colour over each edge, which worked while
            // the band was one flat colour and stopped working the moment it
            // became a gradient -- a flat wash on a ramp is a patch of the
            // wrong teal. Masking the content needs no colour at all, so it is
            // right whatever ends up behind it.
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  if (_moreLeft) const Color(0x00FFFFFF),
                  const Color(0xFFFFFFFF),
                  const Color(0xFFFFFFFF),
                  if (_moreRight) const Color(0x00FFFFFF),
                ],
                stops: [
                  if (_moreLeft) 0.0,
                  _moreLeft ? _fadeWidth / bounds.width : 0.0,
                  _moreRight ? 1 - _fadeWidth / bounds.width : 1.0,
                  if (_moreRight) 1.0,
                ],
              ).createShader(bounds),
              child: layered,
            );
          },
        ),
      ),
    );
  }
}

/// The active tab's shadow, drawn once and moved.
///
/// One shadow exists for the whole strip rather than one per tab, which is
/// what makes "only the current tab is marked" true by construction: there is
/// nothing to leave behind on the tab you came from.
///
/// It travels on two things at once -- the slot it is heading for, and the
/// strip's own scroll offset -- so it stays under its tab while the strip
/// scrolls the newly chosen department into view.
class _SelectionShadow extends StatelessWidget {
  const _SelectionShadow({
    required this.slot,
    required this.leading,
    required this.controller,
  });

  /// Which tab is selected: 0 for "For You", or -1 for a department that is
  /// not among the twelve on the strip.
  final int slot;

  /// The strip's leading padding, which the first tab starts after.
  final double leading;

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    // Nothing to mark. A department chosen from "Shop by category" that did
    // not make the strip has no tab to sit under, and a shadow parked at the
    // left edge would claim the wrong one.
    if (slot < 0) return const SizedBox.shrink();

    return AnimatedBuilder(
      // Redraws as the strip scrolls, so the shadow keeps its tab rather than
      // sliding off it.
      animation: controller,
      builder: (context, _) {
        final offset = controller.hasClients ? controller.offset : 0.0;

        return TweenAnimationBuilder<double>(
          // The slot itself is what animates, so the shadow travels the tabs
          // between here and there instead of cutting across.
          tween: Tween<double>(end: slot.toDouble()),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, position, child) => Stack(
            children: [
              Positioned(
                left: leading + position * DepartmentTabs.itemWidth - offset,
                top: 0,
                bottom: 0,
                width: DepartmentTabs.itemWidth,
                child: child!,
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                // The strip's own shadow, unchanged: hard-edged and dropped
                // straight down, not a soft halo.
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The strip's shape while the department tree is being fetched.
///
/// Exactly [DepartmentTabs.heightFor] tall and on the same band, because
/// without it the strip appears out of nothing the moment the tree lands and
/// shoves the entire storefront down by seventy points. That shift is the one
/// thing a skeleton here exists to prevent.
///
/// The bones are on the band rather than on the page, so they are washes of the
/// header's own white -- the same treatment the real tabs get.
class DepartmentTabsSkeleton extends StatelessWidget {
  const DepartmentTabsSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    // No colour of its own: the shell paints one gradient behind this strip
    // and the search header above it, so the ramp runs unbroken across the
    // join instead of restarting at it.
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: DepartmentTabs.heightFor(context),
        child: Shimmer(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: count,
            itemBuilder: (context, i) => SizedBox(
              width: DepartmentTabs.itemWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _BandBone(
                    width: DepartmentTabs._tile,
                    height: DepartmentTabs._tile,
                    radius: 14,
                  ),
                  const SizedBox(height: DepartmentTabs._labelGap),
                  // Uneven, because department names are uneven. A row of
                  // identical bars reads as a loading widget; a row of ragged
                  // ones reads as words that have not arrived.
                  _BandBone(width: 34 + (i % 3) * 8, height: 9, radius: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bone tinted for the brand band rather than for the page.
class _BandBone extends StatelessWidget {
  const _BandBone({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final pulse = Shimmer.maybeOf(context);

    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    if (pulse == null) return box;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) =>
          Opacity(opacity: 0.55 + pulse.value * 0.45, child: box),
    );
  }
}

/// How wide the fade at a scrollable edge is.
///
/// Was the width of the wash this replaced, kept so the strip looks the same.
const _fadeWidth = 26.0;

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // On the band, so both states are shades of the header's own foreground.
    // An unselected tab is the same white held back, which keeps the strip one
    // material instead of a row of differently-coloured chips.
    final foreground = selected
        ? AppColors.onPrimary
        : AppColors.onPrimary.withValues(alpha: 0.72);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: DepartmentTabs.itemWidth,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Colour animates; size does not. A tile that grew on selection
              // would shove its neighbours sideways on every tap.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: DepartmentTabs._tile,
                height: DepartmentTabs._tile,
                decoration: BoxDecoration(
                  color: AppColors.onPrimary.withValues(
                    alpha: selected ? 0.22 : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: foreground),
              ),
              const SizedBox(height: DepartmentTabs._labelGap),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  style: (theme.textTheme.labelSmall ?? const TextStyle())
                      .copyWith(
                        height: 1.25,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: foreground,
                      ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // The underline, which is what makes the selection unmistakable
              // where the tinted tile alone is a matter of degree.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: DepartmentTabs._underline,
                width: selected ? 22 : 0,
                decoration: BoxDecoration(
                  color: AppColors.onPrimary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

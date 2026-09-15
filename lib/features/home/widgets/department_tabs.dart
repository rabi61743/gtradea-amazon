import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/shimmer.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/presentation/catalog_visuals.dart';
// For the fold's duration and curve. One way only -- the header knows nothing
// of this strip, so the timing lives with the movement that owns it and the
// strip follows.
import 'search_header.dart';

/// The department strip, its own section between the header and the hero.
///
/// It used to be painted on the header's teal band, as part of it. It is a
/// section of the page now: its own light ground, its own spacing, and a rule
/// under it -- so the eye goes header, then departments, then products, with
/// each of the three plainly a different thing.
///
/// Everything here is coloured for that ground rather than for the band. The
/// chosen tab keeps Commerce Orange, which is the one mark that did not have
/// to change: it was legible on the teal and it is legible on white.
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
    this.onNewForYou,
    this.compact = false,
  });

  final List<Category> categories;

  /// Null means "For You".
  final String? selectedCid;

  /// Null for "For You", a department otherwise.
  final ValueChanged<Category?> onSelected;

  /// Opens the personalised feed.
  ///
  /// A destination rather than a filter, and the only tab on the strip that is
  /// one: every other tab changes what is listed below without leaving the
  /// page, and this pushes a screen on top of it. That is also why it never
  /// draws as selected -- it is never the thing the feed underneath is showing.
  ///
  /// Optional, so a preview or a test can build the strip with nowhere to send
  /// anyone. Given nothing to open, the tab is left out rather than drawn dead.
  final VoidCallback? onNewForYou;

  /// True once the feed has been scrolled, which folds the icon tiles away.
  ///
  /// The labels stay. They are what says which department is being shown, and
  /// a strip that emptied itself on a scroll would lose the answer to that
  /// exactly when the shopper is furthest from the top of the page.
  final bool compact;

  /// How many departments the strip offers.
  ///
  /// The catalogue has forty-eight, which is a scroll nobody finishes. These
  /// are the first by the server's own `sort_order` -- the order the storefront
  /// wants them in -- and the rest stay one tap away in "Shop by category".
  static const maxItems = 12;

  /// One item's footprint. Fixed so the strip has a rhythm and the labels line
  /// up, rather than each item being as wide as its own name.
  ///
  /// 58 rather than the 68 it was: the ten points came out of the air between
  /// the tiles, not out of the tiles themselves, so more departments reach the
  /// first screen and the ones that do sit closer together.
  static const itemWidth = 58.0;
  static const _tile = 34.0;
  static const _labelGap = 4.0;
  static const _underline = 3.0;

  /// The glyph inside a tile. Bigger than it was, on a bigger tile: the strip
  /// is meant to be scanned, and the department is easier to recognise by its
  /// mark than by six ellipsised letters.
  static const _glyph = 20.0;

  /// The label size. Named because [heightFor] has to agree with it.
  static const _labelSize = 11.0;

  /// How long the tiles take to go, and to come back.
  ///
  /// The header's own measure, borrowed deliberately: this strip sits directly
  /// under the band and folds on the same gesture, so the two are one movement
  /// and have to be timed as one.
  ///
  /// They were not. This ran 220ms on an ease-out against the header's 450ms
  /// ease-in-out-cubic -- less than half the travel time, on a curve that
  /// spends itself in the first few frames. The strip finished while the band
  /// above it was barely halfway, so the artwork appeared to lurch, settle,
  /// then carry on moving. That is the "coming apart" the header's own doc
  /// warns about, and it is what made the image read as abrupt.
  ///
  /// Referencing [SearchHeader] rather than repeating its numbers, so the two
  /// cannot drift apart again.
  static const collapse = SearchHeader.fold;
  static const collapseCurve = SearchHeader.foldCurve;

  /// The strip's height: tile, gap, one line of label, and the underline.
  ///
  /// One line, not two. This sits above the fold on every page load, and a
  /// second line of label costs fifteen points of the first screen to spell out
  /// department names that ellipsis handles.
  static double heightFor(BuildContext context, {bool compact = false}) {
    final line = MediaQuery.textScalerOf(context).scale(_labelSize * 1.25);
    // Compact drops the tile and the gap under it. Everything else is where it
    // was, so the labels neither move sideways nor change size.
    return (compact ? 0 : _tile + _labelGap) + line + 4 + _underline;
  }

  @override
  State<DepartmentTabs> createState() => _DepartmentTabsState();
}

/// The ink every unchosen tab takes: a soft charcoal.
///
/// Between the two things this has been. The theme's muted grey was too faint
/// to scan at eleven points; the near-black that replaced it was heavier than
/// the page around it, so a row of twelve unchosen departments read as the
/// darkest thing on the screen and pulled the eye off the products.
///
/// This still clears 9:1 on the page, so nothing is lost in legibility.
const _ink = Color(0xFF454E52);

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
    final slot = _newForYouSlot(shown);
    for (var i = 0; i < shown.length; i++) {
      if (shown[i].cid == cid) {
        final index = i + 1;
        // Everything at or past the inserted tab has been pushed along one.
        // This drives the selection shadow and the scroll-into-view, so an
        // off-by-one here parks the orange wash under a department's
        // neighbour rather than under the department.
        return (slot != null && index >= slot) ? index + 1 : index;
      }
    }
    return -1;
  }

  /// Which slot "New for You" takes, in strip positions, or null when there is
  /// nowhere to send anyone.
  ///
  /// Immediately after "Men", by request. Found by name rather than pinned to a
  /// number because the strip is the server's own list in the server's own
  /// order: a fixed index would put this after whatever happened to be third
  /// the day the catalogue was reordered. With no "Men" on the strip at all it
  /// goes last, which is the one position that cannot displace a department.
  int? _newForYouSlot(List<Category> shown) {
    if (widget.onNewForYou == null) return null;
    for (var i = 0; i < shown.length; i++) {
      // Strip positions, not category positions: "For You" holds zero, so the
      // department at `shown[i]` sits at `i + 1` and this follows it.
      if (shown[i].name.trim().toLowerCase() == 'men') return i + 2;
    }
    return shown.length + 1;
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
    final slot = _newForYouSlot(shown);
    final extra = slot == null ? 0 : 1;

    // No colour of its own: the shell paints one gradient behind this strip
    // and the search header above it, so the ramp runs unbroken across the
    // join instead of restarting at it.
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: AnimatedContainer(
        duration: DepartmentTabs.collapse,
        curve: DepartmentTabs.collapseCurve,
        height: DepartmentTabs.heightFor(context, compact: widget.compact),
        // The tiles are mid-fold for a fifth of a second; without this the
        // column inside overflows its box on the way.
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Everything fits: centre it rather than leaving the whole set
            // hard against the left edge of a tablet or a desktop window.
            final total = (shown.length + 1 + extra) * DepartmentTabs.itemWidth;
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
              itemCount: shown.length + 1 + extra,
              itemBuilder: (context, i) {
                // The one tab that leaves the page. Built from the same [_Tab]
                // as every other, so its type, spacing, height, ink, fold and
                // pressed state are not a copy of the strip's -- they are the
                // strip's.
                if (slot != null && i == slot) {
                  return _Tab(
                    label: 'New for You',
                    // The glyph the bottom bar already uses for this
                    // destination, so the two read as the same place.
                    icon: Icons.auto_awesome_outlined,
                    // Never lit: it opens a screen rather than filtering the
                    // feed, so there is no state of this page it describes.
                    selected: false,
                    compact: widget.compact,
                    onTap: widget.onNewForYou!,
                  );
                }
                // Back into category space: everything past the inserted tab
                // is one along from the list it is read out of.
                final index = (slot != null && i > slot) ? i - 1 : i;

                // The selected tab's shadow is not drawn here. It used to be
                // wrapped around this first tab, which meant "For You" carried
                // it whether or not it was the one chosen -- and no other tab
                // could ever have it. It is one layer under the strip now, and
                // it slides. See [_SelectionShadow].
                if (index == 0) {
                  return _Tab(
                    label: 'For You',
                    icon: Icons.shopping_bag_outlined,
                    selected: widget.selectedCid == null,
                    compact: widget.compact,
                    onTap: () => widget.onSelected(null),
                  );
                }
                final category = shown[index - 1];
                return _Tab(
                  label: category.name,
                  icon: iconForCategory(category.name),
                  selected: category.cid == widget.selectedCid,
                  compact: widget.compact,
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
              // A wash of the active colour rather than the hard drop shadow
              // it carried on the teal band. That shadow was a black rectangle
              // offset four points under a transparent box: unnoticeable on
              // the dark band, and a grey slab behind the tab on this one.
              color: AppColors.commerceOrange.withValues(alpha: 0.10),
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
        // The page's own placeholder tone. On the teal this was white at 16%,
        // which on a light ground is very nearly nothing at all.
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;

  /// True while the feed is scrolled: the tile goes, the label stays.
  final bool compact;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // On the band, so both states are shades of the header's own foreground.
    // An unselected tab is the same white held back, which keeps the strip one
    // material instead of a row of differently-coloured chips.
    //
    // The chosen one is Commerce Orange throughout -- its mark, its words and
    // its underline -- and everything else is the page's own near-black. The
    // orange sits on a wash of itself rather than on a solid fill, because an
    // orange mark on an orange tile is a mark nobody can see.
    //
    // A soft charcoal rather than the muted grey the labels used to take: the
    // strip is navigation, and at eleven points a light grey label is the first
    // thing a tired eye gives up on. Not black either -- twelve black labels
    // outweigh the products they are meant to lead to.
    // The held-back slate is a light-page ink; on the dark page it would all
    // but vanish, so there the theme's own body ink takes its place.
    final ink = theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurface
        : _ink;
    final foreground = selected ? AppColors.commerceOrange : ink;
    // The glyph is the heavier mark of the two -- a filled shape against a few
    // thin letters -- so it takes the same ink held back a little, which is
    // what keeps the row from reading darker than the page it sits on.
    final glyph = selected
        ? AppColors.commerceOrange
        : ink.withValues(alpha: 0.82);

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
              // Colour animates; size does not, except on the one thing that
              // is meant to: scrolling the feed folds the tile away and the
              // label rises into its place.
              AnimatedContainer(
                duration: DepartmentTabs.collapse,
                curve: DepartmentTabs.collapseCurve,
                width: DepartmentTabs._tile,
                height: compact ? 0 : DepartmentTabs._tile,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.commerceOrange.withValues(alpha: 0.14)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.hardEdge,
                child: AnimatedOpacity(
                  duration: DepartmentTabs.collapse,
                  curve: DepartmentTabs.collapseCurve,
                  opacity: compact ? 0 : 1,
                  child: Icon(icon, size: DepartmentTabs._glyph, color: glyph),
                ),
              ),
              AnimatedContainer(
                duration: DepartmentTabs.collapse,
                curve: DepartmentTabs.collapseCurve,
                height: compact ? 0 : DepartmentTabs._labelGap,
              ),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  style: (theme.textTheme.labelSmall ?? const TextStyle())
                      .copyWith(
                        fontSize: DepartmentTabs._labelSize,
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
              // The underline, in the same orange as the tile. It is the only
              // mark left once the strip folds its tiles away on a scroll, so
              // it carries the active colour on its own from there.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: DepartmentTabs._underline,
                width: selected ? 22 : 0,
                decoration: BoxDecoration(
                  // Only the chosen tab carries the colour at all: an unselected
                  // tab draws a nought-wide bar, and leaving it orange would
                  // put the active colour in the tree twelve times over.
                  color: selected
                      ? AppColors.commerceOrange
                      : Colors.transparent,
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

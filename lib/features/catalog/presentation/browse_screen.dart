import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../home/widgets/category_section.dart' show CategoryEntry;
import '../../search/presentation/search_entry_screen.dart';
import '../../search/presentation/search_results_screen.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/catalog_repository.dart';
import '../data/catalog_store.dart';
import '../data/department.dart';
import '../widgets/category_nav.dart';

/// The whole catalogue in one scroll, with a navigator that follows along.
///
/// One continuous list rather than a pane per department: a shopper browsing
/// for something they cannot name should be able to keep scrolling past the
/// end of Electronics into Home and kitchen without deciding to. The navigator
/// tracks where they are; tapping it takes them somewhere.
///
/// Everything is built up front rather than lazily. It is what makes the
/// scroll tracking exact -- a lazy list disposes the sections above the
/// viewport, and both the tracker and `Scrollable.ensureVisible` need a
/// section to exist before they can find it. The cost of that decision is
/// the photographs, which is why the tiles only fetch theirs once their
/// section comes within reach of the viewport.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, this.initialDepartment = 0});

  final int initialDepartment;

  @override
  State<BrowseScreen> createState() => _BrowseScreenEntry();
}

class _BrowseScreenEntry extends State<BrowseScreen> {
  @override
  void initState() {
    super.initState();
    // Revalidate, not load: the tree is cached to disk, and `load` returns
    // early once anything has loaded, so a department added in the backoffice
    // would stay invisible until the app was restarted. This paints the cached
    // tree at once and quietly checks behind it.
    //
    // In initState, not build. It was in build, where every rebuild of this
    // widget or any ancestor kicked another fetch of the tree and another
    // 434KB re-encode of the disk cache on the UI thread.
    CatalogStore.instance.categories.revalidate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LoadableView<List<Category>>(
          loadable: CatalogStore.instance.categories,
          emptyCheck: (categories) => categories.isEmpty,
          empty: const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('The catalogue is empty just now.'),
            ),
          ),
          builder: (context, categories) => _BrowseBody(
            initialDepartment: widget.initialDepartment,
            departments: departmentsFrom(
              categories,
              onOpen: (category) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SearchResultsScreen(query: '', categoryCid: category.cid),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The catalogue itself, once there is one to draw.
///
/// Split from the loading above it because the scroll tracking keys on the
/// department list: a widget that had to cope with that list arriving later
/// would need every key and index to be nullable.
class _BrowseBody extends StatefulWidget {
  const _BrowseBody({
    required this.departments,
    required this.initialDepartment,
  });

  final List<Department> departments;
  final int initialDepartment;

  @override
  State<_BrowseBody> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<_BrowseBody> {
  List<Department> get _departments => widget.departments;

  /// A wide window gets the navigator down the side; a phone gets it across
  /// the top. Measured rather than guessed from the platform, so a split-screen
  /// tablet and a small window get the layout that actually fits.
  static const _wideBreakpoint = 760.0;

  final _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys = List.generate(
    _departments.length,
    (_) => GlobalKey(),
  );

  /// Which department the navigator is highlighting.
  ///
  /// A notifier rather than a field behind `setState`, because only the
  /// navigator cares. Calling `setState` for it rebuilt this whole widget --
  /// forty-eight sections and roughly twenty thousand elements -- on every
  /// department boundary crossed while scrolling. Measured at build p90 47ms,
  /// p99 123ms against an 8.3ms budget.
  late final _active = ValueNotifier<int>(
    widget.initialDepartment.clamp(0, _departments.length - 1),
  );

  /// True while a tap-driven scroll is running.
  ///
  /// Without it, the animation sweeps past every section between here and the
  /// destination and the navigator flickers through all of them -- the active
  /// item changing to places the shopper never asked for.
  bool _animating = false;

  /// True from a tap until the shopper scrolls again.
  ///
  /// A tap is a statement about where they want to be, and it outranks what
  /// the geometry says. Landing at the bottom of the list, where the last two
  /// sections are both on screen, must not quietly move the highlight onto a
  /// department they did not choose.
  bool _pinned = false;

  /// Departments whose subcategory tiles are allowed to fetch their pictures.
  ///
  /// The whole catalogue is built up front so the navigator can measure it,
  /// which is fine for glyphs and emphatically not fine for photographs: every
  /// tile that exists resolves its image whether or not anyone can see it, and
  /// the tree holds over a thousand of them. Gating on "has this section been
  /// near the viewport" keeps the request count to a screenful or two while
  /// leaving the layout, the measurements and the scroll tracking untouched.
  ///
  /// Only ever grows. Dropping a department on the way past would re-request
  /// its images the moment the shopper scrolled back.
  ///
  /// One notifier per department rather than one shared set: flipping a shared
  /// value rebuilds every listener, and the point of this is to rebuild exactly
  /// the section that just came into reach.
  late final List<ValueNotifier<bool>> _imaged = List.generate(
    _departments.length,
    (_) => ValueNotifier<bool>(false),
  );

  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
    LanguageStore.instance.load();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateImageWindow());

    if (_active.value != 0) {
      // Opened at a department: get there without animating through the ones
      // before it.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpTo(_active.value),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _active.dispose();
    for (final notifier in _imaged) {
      notifier.dispose();
    }
    super.dispose();
  }

  /// Works out which section the shopper is looking at.
  ///
  /// The active section is the last one whose top has passed the line just
  /// under the navigator, which is what "currently reading" means when
  /// headings scroll up off the top.
  /// Where the list was the last time the geometry was swept.
  double _lastSweep = double.negativeInfinity;

  /// How far the list must move before the sections are measured again.
  ///
  /// Both sweeps below walk up to forty-eight sections calling `localToGlobal`,
  /// which in a tree this size is not cheap -- and the scroll listener fires on
  /// every frame, so at 120Hz that was ninety-six transform walks per frame and
  /// a steady ~8ms of build time on an 8.3ms budget. Neither the highlight nor
  /// the image window needs per-frame precision; a third of a tile's travel is
  /// far finer than either can show.
  static const _sweepEvery = 48.0;

  void _onScroll() {
    if (!mounted) return;

    final offset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    // Always sweep at the very ends, or the last department can never become
    // active and the final sections never fill in.
    final atEdge =
        _scrollController.hasClients &&
        _scrollController.position.hasContentDimensions &&
        (offset <= 0 ||
            offset >= _scrollController.position.maxScrollExtent - 4);
    if (!atEdge && (offset - _lastSweep).abs() < _sweepEvery) return;
    _lastSweep = offset;

    // Before the early return below: a tap-driven jump to a distant department
    // must bring that department's pictures with it, and it is exactly the
    // case where `_animating` is true the whole way.
    _updateImageWindow();

    if (_animating || _pinned) return;

    final viewport = context.findRenderObject();
    if (viewport is! RenderBox) return;
    final threshold = viewport.localToGlobal(Offset.zero).dy + _spyLine;

    var active = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final sectionContext = _sectionKeys[i].currentContext;
      if (sectionContext == null) continue;
      final box = sectionContext.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= threshold) {
        active = i;
      } else {
        break;
      }
    }

    // At the very bottom, the last section wins whatever the rule says. A
    // short final department never reaches the top of the viewport because
    // there is nothing left to scroll, so without this it could never be the
    // active one -- the shopper would be looking straight at it while the
    // navigator pointed somewhere else.
    final position = _scrollController.position;
    if (position.hasContentDimensions &&
        position.pixels >= position.maxScrollExtent - 4) {
      active = _sectionKeys.length - 1;
    }

    // A notifier assignment, not setState: only the navigator reads this, and
    // rebuilding the catalogue for it was the single most expensive thing this
    // screen did.
    _active.value = active;
  }

  /// A little below the navigator, so a heading counts as current once it has
  /// actually reached the top of the content rather than when it first peeks
  /// into view.
  double get _spyLine => 140;

  /// Lets the sections within reach of the viewport load their pictures.
  ///
  /// One viewport of lead-in on each side, so a photograph is already decoded
  /// by the time it scrolls into view rather than fading in under the
  /// shopper's thumb.
  void _updateImageWindow() {
    if (!mounted) return;

    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;

    final top = viewport.localToGlobal(Offset.zero).dy;
    final height = viewport.size.height;
    // Half a viewport of lead-in, not a whole one either side. Three viewports'
    // worth used to come into reach at once during a fast scroll, and each
    // arriving section builds its two dozen tiles in that frame -- which showed
    // up as a steady 12ms build cost on every frame of a scroll.
    final from = top - height * 0.5;
    final to = top + height * 1.5;

    // One section per frame. Filling several at once costs several sections'
    // worth of building in a single frame; spreading them costs the same total
    // work across several frames, none of which drops. Two per frame measured
    // at a steady 8.1ms build against an 8.3ms budget -- right on the edge.
    var filled = 0;

    for (var i = 0; i < _sectionKeys.length; i++) {
      if (_imaged[i].value) continue;
      final sectionContext = _sectionKeys[i].currentContext;
      if (sectionContext == null) continue;
      final box = sectionContext.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;

      final sectionTop = box.localToGlobal(Offset.zero).dy;
      final sectionBottom = sectionTop + box.size.height;
      if (sectionBottom >= from && sectionTop <= to) {
        // Rebuilds exactly this section, not the other forty-seven.
        _imaged[i].value = true;
        if (++filled >= 1) return;
      }
    }
  }

  /// Tapping the current section scrolls to the top of it rather than doing
  /// nothing, which is what a tap on where-you-already-are should mean.
  Future<void> _goTo(int index) async {
    // No setState: the navigator reads `_active` and the two flags are only
    // read by the scroll listener, so nothing on screen depends on a rebuild
    // here. This used to rebuild the whole catalogue to move a highlight.
    _active.value = index;
    _animating = true;
    _pinned = true;

    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext != null) {
      await Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
        alignment: 0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    }
    if (!mounted) return;
    _animating = false;
  }

  /// The shopper has taken the wheel back, so the tracker resumes.
  void _releasePin() {
    if (_pinned && !_animating) _pinned = false;
  }

  void _jumpTo(int index) {
    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext == null) return;
    Scrollable.ensureVisible(sectionContext, alignment: 0);
  }

  /// Opens the subcategory itself rather than searching for its name.
  ///
  /// Searching the words "Flange" and browsing the Flange category are not the
  /// same query, and the second is the one the shopper asked for.
  void _openEntry(CategoryEntry entry) {
    final open = entry.onTap;
    if (open != null) return open();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(query: entry.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LanguageStore.instance,
      builder: (context, _) {
        final strings = LanguageStore.instance.strings;

        return Scaffold(
          appBar: AppBar(
            title: Text(strings.categories),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: strings.search,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchEntryScreen()),
                ),
              ),
              ListenableBuilder(
                listenable: CartStore.instance,
                builder: (context, _) => IconButton(
                  icon: Badge.count(
                    count: CartStore.instance.count,
                    isLabelVisible: CartStore.instance.count > 0,
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                  tooltip: strings.cart,
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const CartScreen())),
                ),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideBreakpoint;
              // Only the navigator rebuilds when the active department
              // changes. It used to be the whole screen.
              final nav = ValueListenableBuilder<int>(
                valueListenable: _active,
                builder: (context, active, _) => CategoryNav(
                  departments: _departments,
                  active: active,
                  onSelected: _goTo,
                  strings: strings,
                  vertical: wide,
                ),
              );
              final content = _CatalogueList(
                departments: _departments,
                sectionKeys: _sectionKeys,
                controller: _scrollController,
                strings: strings,
                width: wide ? constraints.maxWidth - 208 : constraints.maxWidth,
                imaged: _imaged,
                onEntryTap: _openEntry,
                onUserScroll: _releasePin,
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    nav,
                    Expanded(child: content),
                  ],
                );
              }
              return Column(
                children: [
                  nav,
                  Expanded(child: content),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _CatalogueList extends StatelessWidget {
  const _CatalogueList({
    required this.departments,
    required this.sectionKeys,
    required this.controller,
    required this.strings,
    required this.width,
    required this.imaged,
    required this.onEntryTap,
    required this.onUserScroll,
  });

  final List<Department> departments;
  final List<GlobalKey> sectionKeys;
  final ScrollController controller;
  final AppStrings strings;
  final double width;

  /// One flag per department, each rebuilding only its own section.
  final List<ValueNotifier<bool>> imaged;

  final ValueChanged<CategoryEntry> onEntryTap;
  final VoidCallback onUserScroll;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<UserScrollNotification>(
      // The shopper touching the list is what releases a pinned selection.
      // A programmatic scroll does not emit this, so the pin survives the
      // animation it started.
      onNotification: (notification) {
        if (notification.direction != ScrollDirection.idle) onUserScroll();
        return false;
      },
      child: RefreshIndicator(
        // The tree is cached to disk and revalidated quietly on open. This is
        // for the shopper who has a reason to think it changed and wants to
        // say so.
        onRefresh: CatalogStore.instance.categories.refresh,
        child: SingleChildScrollView(
          controller: controller,
          // Always scrollable, or a catalogue shorter than the window has no
          // overscroll for the refresh gesture to start from.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < departments.length; i++)
                _DepartmentSection(
                  key: sectionKeys[i],
                  department: departments[i],
                  strings: strings,
                  width: width,
                  showImages: imaged[i],
                  onEntryTap: onEntryTap,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepartmentSection extends StatelessWidget {
  const _DepartmentSection({
    super.key,
    required this.department,
    required this.strings,
    required this.width,
    required this.showImages,
    required this.onEntryTap,
  });

  final Department department;
  final AppStrings strings;
  final double width;

  /// Flips true once this section has been near the viewport, which keeps a
  /// thousand off-screen tiles from all reaching for the network at once.
  ///
  /// A notifier so the flip rebuilds this section alone. It used to be a bool
  /// read from a shared set, and setting it rebuilt all forty-eight.
  final ValueNotifier<bool> showImages;

  final ValueChanged<CategoryEntry> onEntryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = strings.department(department.label);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DepartmentBanner(
            department: department,
            name: name,
            count: strings.categoryCount(department.entryCount),
          ),
          for (final group in department.groups) ...[
            const SizedBox(height: 20),
            _GroupHeading(
              // Built from the translated department name rather than read
              // off `group.title`, which is assembled in English in the data
              // layer and could never be translated by a lookup.
              label: strings.browseIn(name),
              tint: department.tint,
            ),
            const SizedBox(height: 12),
            // Listens where the flag is used rather than where it is set, so
            // a section coming into reach rebuilds its own grid and nothing
            // else on the screen.
            ValueListenableBuilder<bool>(
              valueListenable: showImages,
              builder: (context, show, _) => _EntryGrid(
                entries: group.entries,
                width: width - 32,
                showImages: show,
                onTap: onEntryTap,
              ),
            ),
          ],
          if (department.groups.isEmpty) ...[
            const SizedBox(height: 14),
            // Four of the real departments genuinely have no subcategories.
            // A heading over blank space reads as a page that failed to load;
            // this says which it is, and still opens the department.
            _NoSubcategories(department: department),
          ],
          const SizedBox(height: 16),
          Text(
            strings.endOfList(name),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: theme.colorScheme.outlineVariant),
        ],
      ),
    );
  }
}

/// A department's opening card: photograph on one side, name on the other.
///
/// The tiles underneath carry their own photographs too. They did not used to,
/// on the grounds that glyphs kept the page cheap -- but the server sends an
/// image for nearly every subcategory, and drawing a generic icon over a real
/// photograph told the shopper less, not more. The cost is handled where it
/// belongs: the tiles build lazily and decode at tile size.
class _DepartmentBanner extends StatelessWidget {
  const _DepartmentBanner({
    required this.department,
    required this.name,
    required this.count,
  });

  final Department department;
  final String name;
  final String count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Container(
        color: department.tint.withValues(alpha: 0.10),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: ArtworkPanel(
                icon: department.icon,
                tint: department.tint,
                imageUrl: department.imageUrl,
                iconScale: 0.4,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      department.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      count,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: department.tint,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A group label, marked by a short bar in the department's colour rather than
/// sitting inside a card. The sections need separating, not boxing.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Tiles that reflow to the width they are given.
///
/// Column count comes from the space available rather than a fixed three, so
/// a phone, a tablet and a desktop window each get a sensible density and
/// adding categories later does not need the layout revisited.
/// What a department with no subcategories says for itself.
///
/// Not an error and not worded as one: a handful of the real departments have
/// nothing under them, and the products are still there to browse.
class _NoSubcategories extends StatelessWidget {
  const _NoSubcategories({required this.department});

  final Department department;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: department.tint.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: department.onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(department.icon, size: 20, color: department.tint),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No subcategories here yet -- browse everything in '
                  '${department.label}.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryGrid extends StatelessWidget {
  const _EntryGrid({
    required this.entries,
    required this.width,
    required this.showImages,
    required this.onTap,
  });

  final List<CategoryEntry> entries;
  final double width;
  final bool showImages;
  final ValueChanged<CategoryEntry> onTap;

  static const _gap = 10.0;
  static const _runGap = 14.0;
  static const _targetTileWidth = 116.0;

  /// The label under a tile: two lines of bodySmall plus its gap.
  static const _labelHeight = 38.0;

  @override
  Widget build(BuildContext context) {
    final columns = (width / _targetTileWidth).floor().clamp(3, 8);
    final tileWidth = (width - _gap * (columns - 1)) / columns;

    // Far from the viewport, the grid is a box of the right size and nothing
    // else.
    //
    // This is the difference between building forty-eight departments' worth of
    // tiles at once and building the two you can see. The catalogue holds about
    // eleven hundred subcategories, each roughly fifteen elements once its
    // ArtworkPanel and two LayoutBuilders are counted -- twenty thousand
    // elements laid out before the first frame, which measured as a 131ms
    // ninety-ninth-percentile build against an 8.3ms budget.
    //
    // The height has to match what the tiles would occupy, or the scroll extent
    // changes as sections fill in and the navigator's measurements move under
    // it. The same `showImages` flag drives both, so a section is filled in
    // well before it is on screen.
    if (!showImages) {
      final rows = (entries.length / columns).ceil();
      final tileHeight = tileWidth + _labelHeight;
      return SizedBox(
        height: rows * tileHeight + (rows - 1).clamp(0, rows) * _runGap,
      );
    }

    return Wrap(
      spacing: _gap,
      runSpacing: _runGap,
      children: [
        for (final entry in entries)
          SizedBox(
            width: tileWidth,
            child: _EntryTile(
              entry: entry,
              showImage: showImages,
              // Measured once for the grid instead of once per tile.
              tileWidth: tileWidth,
              onTap: () => onTap(entry),
            ),
          ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.showImage,
    required this.tileWidth,
    required this.onTap,
  });

  final CategoryEntry entry;
  final bool showImage;

  /// Known from the grid, so the panel does not have to measure itself.
  final double tileWidth;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The subcategory's own photograph, which the server sends for
          // nearly every one of them. This tile used to draw the glyph and
          // throw the picture away; ArtworkPanel keeps the glyph as the
          // loading and failure state instead, so a slow connection looks the
          // same as it always did.
          ArtworkPanel(
            icon: entry.icon,
            tint: entry.tint,
            knownWidth: tileWidth,
            // Withheld until this section is near the viewport. Passing null
            // is exactly the "no picture" case ArtworkPanel already draws, so
            // an off-screen tile looks like it always did.
            imageUrl: showImage ? entry.imageUrl : null,
            aspectRatio: 1,
          ),
          const SizedBox(height: 6),
          Text(
            entry.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.25),
          ),
        ],
      ),
    );
  }
}

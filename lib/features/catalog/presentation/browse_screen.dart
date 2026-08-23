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
import '../data/catalog_content.dart';
import '../widgets/category_nav.dart';

/// The whole catalogue in one scroll, with a navigator that follows along.
///
/// One continuous list rather than a pane per department: a shopper browsing
/// for something they cannot name should be able to keep scrolling past the
/// end of Electronics into Home and kitchen without deciding to. The navigator
/// tracks where they are; tapping it takes them somewhere.
///
/// Everything is built up front rather than lazily. Seven departments of
/// glyph tiles is cheap, and it is what makes the scroll tracking exact --
/// a lazy list disposes the sections above the viewport, and a tracker that
/// cannot see them has to guess.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, this.initialDepartment = 0});

  final int initialDepartment;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  static const _departments = CatalogContent.departments;

  /// A wide window gets the navigator down the side; a phone gets it across
  /// the top. Measured rather than guessed from the platform, so a split-screen
  /// tablet and a small window get the layout that actually fits.
  static const _wideBreakpoint = 760.0;

  final _scrollController = ScrollController();
  final List<GlobalKey> _sectionKeys =
      List.generate(_departments.length, (_) => GlobalKey());

  late int _active = widget.initialDepartment.clamp(0, _departments.length - 1);

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

  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
    LanguageStore.instance.load();
    _scrollController.addListener(_onScroll);

    if (_active != 0) {
      // Opened at a department: get there without animating through the ones
      // before it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_active));
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Works out which section the shopper is looking at.
  ///
  /// The active section is the last one whose top has passed the line just
  /// under the navigator, which is what "currently reading" means when
  /// headings scroll up off the top.
  void _onScroll() {
    if (_animating || _pinned || !mounted) return;

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

    if (active != _active) setState(() => _active = active);
  }

  /// A little below the navigator, so a heading counts as current once it has
  /// actually reached the top of the content rather than when it first peeks
  /// into view.
  double get _spyLine => 140;

  /// Tapping the current section scrolls to the top of it rather than doing
  /// nothing, which is what a tap on where-you-already-are should mean.
  Future<void> _goTo(int index) async {
    setState(() {
      _active = index;
      _animating = true;
      _pinned = true;
    });

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
    setState(() => _animating = false);
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

  void _openEntry(CategoryEntry entry) {
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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  ),
                ),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideBreakpoint;
              final nav = CategoryNav(
                departments: _departments,
                active: _active,
                onSelected: _goTo,
                strings: strings,
                vertical: wide,
              );
              final content = _CatalogueList(
                departments: _departments,
                sectionKeys: _sectionKeys,
                controller: _scrollController,
                strings: strings,
                width: wide ? constraints.maxWidth - 208 : constraints.maxWidth,
                onEntryTap: _openEntry,
                onUserScroll: _releasePin,
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [nav, Expanded(child: content)],
                );
              }
              return Column(children: [nav, Expanded(child: content)]);
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
    required this.onEntryTap,
    required this.onUserScroll,
  });

  final List<Department> departments;
  final List<GlobalKey> sectionKeys;
  final ScrollController controller;
  final AppStrings strings;
  final double width;
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
      child: SingleChildScrollView(
        controller: controller,
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
                onEntryTap: onEntryTap,
              ),
          ],
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
    required this.onEntryTap,
  });

  final Department department;
  final AppStrings strings;
  final double width;
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
              label: strings.group(group.title),
              tint: department.tint,
            ),
            const SizedBox(height: 12),
            _EntryGrid(
              entries: group.entries,
              width: width - 32,
              onTap: onEntryTap,
            ),
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
/// The one place in the browse tree that carries a photograph. The tiles
/// underneath use glyphs, which keeps the page cheap to build and means a
/// mismatched stock photo cannot mislabel a category.
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
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
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
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
class _EntryGrid extends StatelessWidget {
  const _EntryGrid({
    required this.entries,
    required this.width,
    required this.onTap,
  });

  final List<CategoryEntry> entries;
  final double width;
  final ValueChanged<CategoryEntry> onTap;

  static const _gap = 10.0;
  static const _targetTileWidth = 116.0;

  @override
  Widget build(BuildContext context) {
    final columns = (width / _targetTileWidth).floor().clamp(3, 8);
    final tileWidth = (width - _gap * (columns - 1)) / columns;

    return Wrap(
      spacing: _gap,
      runSpacing: 14,
      children: [
        for (final entry in entries)
          SizedBox(
            width: tileWidth,
            child: _EntryTile(entry: entry, onTap: () => onTap(entry)),
          ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final CategoryEntry entry;
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
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                color: entry.tint.withValues(alpha: 0.10),
                border: Border.all(color: entry.tint.withValues(alpha: 0.20)),
              ),
              child: FractionallySizedBox(
                widthFactor: 0.42,
                heightFactor: 0.42,
                child: FittedBox(
                  child: Icon(entry.icon, color: entry.tint),
                ),
              ),
            ),
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

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../home/widgets/category_section.dart' show CategoryEntry;
import '../../search/presentation/search_entry_screen.dart';
import '../../search/presentation/search_results_screen.dart';
import '../data/catalog_content.dart';

/// Browse the whole catalogue: departments down the side, their subcategories
/// beside them.
///
/// Two panes rather than a drill-down, because the point of a browse screen is
/// comparison -- a shopper who opened Electronics and meant Home and kitchen
/// should be one tap away, not one tap and a back gesture.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, this.initialDepartment = 0});

  final int initialDepartment;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late int _selected = widget.initialDepartment.clamp(
    0,
    CatalogContent.departments.length - 1,
  );

  final _paneController = ScrollController();

  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
  }

  @override
  void dispose() {
    _paneController.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);

    // Back to the top of the new department. Keeping the old offset lands the
    // shopper halfway down a section they have never seen.
    if (_paneController.hasClients) _paneController.jumpTo(0);
  }

  void _openEntry(CategoryEntry entry) {
    // A category tile is a search for that category. It leads somewhere real
    // rather than being a picture that does nothing.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(query: entry.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final department = CatalogContent.departments[_selected];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
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
              tooltip: 'Cart',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DepartmentRail(
            departments: CatalogContent.departments,
            selected: _selected,
            onSelected: _select,
          ),
          Expanded(
            child: ListView(
              // Keyed on the department so switching resets scroll position
              // and rebuilds cleanly rather than animating one list into
              // another with different content.
              key: ValueKey(department.label),
              controller: _paneController,
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                _DepartmentHeader(department: department),
                if (department.popular.isNotEmpty) ...[
                  const _GroupTitle('Popular right now'),
                  _PopularStrip(
                    entries: department.popular,
                    onTap: _openEntry,
                  ),
                ],
                for (final group in department.groups) ...[
                  _GroupTitle(group.title),
                  _EntryGrid(entries: group.entries, onTap: _openEntry),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
                  child: Text(
                    'That is everything in ${department.label}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The department list down the left edge.
class _DepartmentRail extends StatelessWidget {
  const _DepartmentRail({
    required this.departments,
    required this.selected,
    required this.onSelected,
  });

  final List<Department> departments;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 96,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: departments.length,
        itemBuilder: (context, i) => _RailItem(
          department: departments[i],
          isSelected: i == selected,
          onTap: () => onSelected(i),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.department,
    required this.isSelected,
    required this.onTap,
  });

  final Department department;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // The selected item is a white card that reads as continuous with
            // the pane beside it -- the rail is a tab strip, and the chosen tab
            // belongs to the content it opened.
            if (isSelected)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(AppTheme.radiusCard),
                    ),
                  ),
                ),
              ),
            if (isSelected)
              Positioned(
                left: 0,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: department.tint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: department.tint
                          .withValues(alpha: isSelected ? 0.16 : 0.08),
                    ),
                    // A tinted glyph rather than a photograph: this is
                    // navigation chrome, and it should not wait on the network
                    // or shift when an image fails.
                    child: Icon(
                      department.icon,
                      size: 21,
                      color: isSelected
                          ? department.tint
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    department.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      height: 1.25,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected
                          ? department.tint
                          : theme.colorScheme.onSurfaceVariant,
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

/// The band at the top of the pane, in the department's own colour.
class _DepartmentHeader extends StatelessWidget {
  const _DepartmentHeader({required this.department});

  final Department department;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          gradient: LinearGradient(
            colors: [
              department.tint.withValues(alpha: 0.16),
              department.tint.withValues(alpha: 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: department.tint.withValues(alpha: 0.18),
              ),
              child: Icon(department.icon, size: 21, color: department.tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    department.label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    department.tagline,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${department.entryCount} categories',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: department.tint,
                      fontWeight: FontWeight.w700,
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

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// A sample of the department as a single scrollable row of pills.
///
/// A row rather than another grid: it has to read as a different kind of thing
/// from the sections under it, or it is just the first section twice.
class _PopularStrip extends StatelessWidget {
  const _PopularStrip({required this.entries, required this.onTap});

  final List<CategoryEntry> entries;
  final ValueChanged<CategoryEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 44 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final entry = entries[i];
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onTap(entry),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: ArtworkPanel(
                        icon: entry.icon,
                        tint: entry.tint,
                        imageUrl: entry.imageUrl,
                        iconScale: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.label,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Three to a row, image above the label.
class _EntryGrid extends StatelessWidget {
  const _EntryGrid({required this.entries, required this.onTap});

  final List<CategoryEntry> entries;
  final ValueChanged<CategoryEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * 2) / 3;

          return Wrap(
            spacing: gap,
            runSpacing: 14,
            children: [
              for (final entry in entries)
                SizedBox(
                  width: width,
                  child: _EntryTile(entry: entry, onTap: () => onTap(entry)),
                ),
            ],
          );
        },
      ),
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
          // Square, so a row of tiles lines up whatever the photographs are.
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: ArtworkPanel(
                icon: entry.icon,
                tint: entry.tint,
                imageUrl: entry.imageUrl,
                iconScale: 0.42,
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

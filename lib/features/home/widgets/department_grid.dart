import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../../shared/widgets/section_header.dart';

class DepartmentEntry {
  const DepartmentEntry({
    required this.label,
    required this.icon,
    required this.tint,
    this.imageUrl,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;

  /// Photograph for the tile; falls back to the tinted panel when absent.
  final String? imageUrl;

  /// Where the tile goes.
  final VoidCallback? onTap;
}

/// A grid of department tiles: a square picture with its name underneath.
///
/// The index at the foot of the home page. Three columns rather than two: at
/// two, forty-eight departments is twenty-four rows and forty-eight images
/// fetched at once, which is a wall rather than an index -- so the home page
/// passes a bounded set and points "See All" at the browse screen, which lists
/// every one.
///
/// The name goes *under* the picture here, unlike [SubcategoryGrid], where it
/// is written across the foot of the tile. An index is scanned, and a label on
/// its own line is quicker to read down a column than one laid over a
/// photograph.
class DepartmentGrid extends StatelessWidget {
  const DepartmentGrid({
    super.key,
    required this.title,
    required this.entries,
    this.subtitle,
    this.leadingIcon,
    this.onSeeAll,
    this.actionLabel = 'See All',
    this.columns = defaultColumns,
  });

  final String title;

  /// A line under the title, for a block that is a chosen set rather than an
  /// index and has something to say about what is in it.
  final String? subtitle;

  final IconData? leadingIcon;
  final List<DepartmentEntry> entries;
  final VoidCallback? onSeeAll;
  final String actionLabel;

  /// How many across.
  ///
  /// Three for the index of departments, where the job is fitting a lot of them
  /// on a screen. Two for a short chosen set, where the tiles are meant to be
  /// looked at -- and where the names are long enough that four columns would
  /// give each one about seventy points and four lines of ellipsis.
  final int columns;

  static const defaultColumns = 3;
  static const gap = 12.0;
  static const _labelGap = 6.0;
  static const _labelLines = 2;

  /// One tile's width, given the space the grid has.
  static double tileWidth(double available, {int columns = defaultColumns}) =>
      (available - gap * (columns - 1)) / columns;

  /// Exactly how tall a tile of [width] will be.
  ///
  /// Measured from the tile's own parts rather than expressed as an aspect
  /// ratio. A ratio is a guess that has to be re-guessed every time a row is
  /// added or the reader changes their text size, and it is the bug this
  /// codebase has already fixed three times.
  static double heightFor(BuildContext context, double width) {
    final painter = TextPainter(
      // Ascender and descender, so this is a full line box rather than the
      // height of whichever glyphs a department happens to be named with.
      text: TextSpan(text: 'Ag', style: _labelStyleOf(Theme.of(context))),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    // The picture is square and spans the tile.
    return width + _labelGap + painter.height * _labelLines;
  }

  static TextStyle _labelStyleOf(ThemeData theme) =>
      (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
        height: 1.2,
        fontWeight: FontWeight.w500,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _labelStyleOf(theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          leadingIcon: leadingIcon,
          onSeeAll: onSeeAll,
          actionLabel: actionLabel,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SectionHeader.edge),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = tileWidth(constraints.maxWidth, columns: columns);

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  // The tile's own answer, not a second calculation of it.
                  mainAxisExtent: heightFor(context, width),
                ),
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    onTap: entry.onTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusCard,
                          ),
                          child: ArtworkPanel(
                            icon: entry.icon,
                            tint: entry.tint,
                            imageUrl: entry.imageUrl,
                            aspectRatio: 1,
                            // Already known, so the panel skips the
                            // LayoutBuilder it would otherwise need to size
                            // its decode -- and there are a dozen of these.
                            knownWidth: width,
                            iconScale: 0.42,
                          ),
                        ),
                        const SizedBox(height: _labelGap),
                        Text(
                          entry.label,
                          maxLines: _labelLines,
                          overflow: TextOverflow.ellipsis,
                          // The resolved one, not the nullable parameter --
                          // which would silently drop the index's own style
                          // for every caller that does not pass one.
                          style: style,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

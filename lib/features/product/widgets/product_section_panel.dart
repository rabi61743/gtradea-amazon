import 'package:flutter/material.dart';

/// A section of the product page that opens and closes.
///
/// Built on [ExpansionTile] rather than a hand-rolled fold: Material's own
/// expansion is the smooth open-and-close this needs, with the chevron that
/// tells a shopper the row can be opened, and no motion of its own invented on
/// top of it.
///
/// The heading is the same `titleSmall` at weight 700 that every other section
/// on this page uses, and it sits on the same 16pt margin -- so a closed panel
/// reads as one of the page's headings rather than as a control bolted on.
class ProductSectionPanel extends StatelessWidget {
  const ProductSectionPanel({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.trailingLabel,
  });

  final String title;
  final Widget child;

  /// Closed by default: the page is long, and the sections below these two --
  /// ratings, and the rail of similar products -- are why somebody keeps
  /// scrolling. Opening them by default buries that behind a spec table.
  final bool initiallyExpanded;

  /// A count beside the heading, so the panel says how much is inside before
  /// it is opened.
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return Theme(
      // ExpansionTile draws a divider above and below itself from the ambient
      // theme. The page separates its sections with space, not rules, and two
      // stray lines here would be the only ones on it.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // The product page is a lazy `SliverList`: it destroys a child once it
        // has been scrolled far enough past, and an ExpansionTile keeps
        // `isExpanded` in a controller it builds in `initState` and disposes
        // with itself. Without somewhere outside the tile to remember, a panel
        // the shopper opened is shut again by the time they scroll back to it.
        //
        // A PageStorageKey is that somewhere: `Expansible` reads it on init and
        // writes it on every toggle, and the bucket belongs to the route, which
        // outlives the recycled tile. The key must also be distinct per panel,
        // because storage slots are addressed by the keys found above a widget
        // -- two unkeyed panels on one page would share a slot, and opening
        // Specifications would open Detail images with it.
        key: PageStorageKey<String>('product-section-$title'),
        initiallyExpanded: initiallyExpanded,
        // The page's own margin, so the heading lines up with every other
        // section title above it.
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: theme.colorScheme.onSurfaceVariant,
        collapsedIconColor: theme.colorScheme.onSurfaceVariant,
        title: Row(
          children: [
            Expanded(child: Text(title, style: heading)),
            if (trailingLabel != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  trailingLabel!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        children: [child],
      ),
    );
  }
}

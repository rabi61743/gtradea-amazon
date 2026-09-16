import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

import 'product_type_scale.dart';

/// A section of the product page that opens and closes.
///
/// Drawn as a card, like every other section on this page: white on the ivory
/// ground, a hairline round it, the same 16pt corner. A bare heading between
/// two cards reads as a row that failed to load its frame.
///
/// Built on [ExpansionTile] rather than a hand-rolled fold: Material's own
/// expansion is the smooth open-and-close this needs. The heading is the same
/// `accordionLabel` the other cards use, so a closed panel reads as one of the
/// page's sections rather than as a control bolted on.
class ProductSectionPanel extends StatefulWidget {
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
  State<ProductSectionPanel> createState() => _ProductSectionPanelState();
}

class _ProductSectionPanelState extends State<ProductSectionPanel> {
  /// The corner every card on this page is cut to.
  static const _radius = AppTheme.radiusSection;

  late bool _open = widget.initiallyExpanded;
  bool _restored = false;

  /// Where this panel's open state is filed.
  ///
  /// Distinct per panel, because two panels sharing a slot would open
  /// together -- Specifications would take Detail images with it.
  String get _slot => 'product-section-${widget.title}';

  /// The product page is a lazy `SliverList`: it destroys a child once it has
  /// been scrolled far enough past. Without somewhere outside the widget to
  /// remember, a panel the shopper opened is shut again by the time they
  /// scroll back to it. The bucket belongs to the route, which outlives the
  /// recycled tile.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    final stored = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _slot);
    if (stored is bool) _open = stored;
  }

  void _remember(bool open) {
    setState(() => _open = open);
    PageStorage.maybeOf(context)?.writeState(context, open, identifier: _slot);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The same 97% the cards above it take, centred, so the stack down this
    // page is one width whatever the screen.
    return Padding(
      // No seam at all now, by request: the cards' own borders are what say
      // where one section ends and the next begins, so a run of panels reads
      // as one stack rather than as separate sections with empty page between
      // them. Kept as an explicit zero so the measure stays in one place.
      padding: EdgeInsets.zero,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.97,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            // So the tile's own ink stays inside the corners it is drawn in.
            clipBehavior: Clip.antiAlias,
            child: Theme(
              // ExpansionTile draws a divider above and below itself from the
              // ambient theme. The card already has an edge, and two stray lines
              // inside it would be the only ones on the page.
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: PageStorageKey<String>(_slot),
                initiallyExpanded: _open,
                onExpansionChanged: _remember,
                // The card supplies the page margin now, so the tile keeps a
                // card's own padding.
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                // A list tile is 56 tall before it has drawn anything, and a
                // run of closed panels is mostly that height. Forty-eight is
                // still a thumb target and takes a row of empty card off each
                // one.
                minTileHeight: 48,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                shape: const Border(),
                collapsedShape: const Border(),
                // The control is drawn here rather than left to the default
                // rotating chevron: a shopper looking for a way to close a
                // screenful of photographs should find something that looks like a
                // button.
                trailing: _OpenClose(open: _open, section: widget.title),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: ProductType.accordionLabel(theme),
                      ),
                    ),
                    if (widget.trailingLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          widget.trailingLabel!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                children: [widget.child],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The open/close mark at the right of a panel's heading.
///
/// Not itself tappable: the whole heading row is, and a button inside a button
/// is a target that swallows taps meant for the row around it. It is drawn as
/// a control because that is what it is -- and it says which way it goes, so
/// the state is legible without reading the section below it.
class _OpenClose extends StatelessWidget {
  const _OpenClose({required this.open, required this.section});

  final bool open;
  final String section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: open ? 'Close $section' : 'Open $section',
      child: Tooltip(
        message: open ? 'Close' : 'Open',
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              key: ValueKey(open),
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

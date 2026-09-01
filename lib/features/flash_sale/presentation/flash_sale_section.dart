import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../data/flash_sale.dart';
import 'flash_deal_tile.dart';

/// The flash sale block on the home page.
///
/// One tinted panel: a heading, a line of context, and a two-by-two grid of
/// what is in the sale. It has been four stacked slabs, then a blue bar over a
/// swipeable rail; this is the shape asked for, and it is a better fit for what
/// the block is actually for. A rail hid three of six deals behind a gesture
/// nobody makes on a home page. A grid of four shows all four at once and asks
/// for one tap.
///
/// **The whole panel is that one tap.** Not the tiles, not a button in the
/// corner -- the panel. So there is no wrong place to press, and every press
/// goes to the same place: the deals page, where the prices, the stock and the
/// Add buttons live. That is why the tiles below are inert: a tile with its own
/// gesture would cut a hole in the panel's, and a block where some presses go
/// one way and some another is worse than either.
///
/// It owns the ended state: when the deadline passes the whole block swaps
/// rather than leaving a grid of prices that are no longer being offered. The
/// countdown that used to announce that moment is gone from the design, so a
/// single timer does it instead -- see [_FlashSaleSectionState._expiry].
class FlashSaleSection extends StatefulWidget {
  const FlashSaleSection({
    super.key,
    required this.sale,
    this.onSeeAllDeals,
    this.now,
  });

  final FlashSale sale;

  /// Opens the deals page. The panel's tap, and the ended state's button, both
  /// go here -- an expired sale pointing at the deals still running is a better
  /// answer than dropping someone into a blank search.
  final VoidCallback? onSeeAllDeals;

  /// The clock, injectable so a test can put the sale in the past.
  final DateTime Function()? now;

  @override
  State<FlashSaleSection> createState() => _FlashSaleSectionState();
}

class _FlashSaleSectionState extends State<FlashSaleSection> {
  late bool _ended = widget.sale.hasEndedAt((widget.now ?? DateTime.now)());

  /// Four tiles, two by two. More than that and each one is too small to tell
  /// what it is; fewer and the panel is a lot of colour for very little.
  static const _shown = 4;

  static const _gap = 12.0;
  static const _edge = 16.0;

  /// Fires once, when the sale runs out.
  ///
  /// The visible countdown used to do this: it ticked every second and told the
  /// section when it hit zero. The clock is gone from the design, but the
  /// deadline is not -- an expired sale still has to stop showing prices that
  /// are no longer offered, and a shopper sitting on the home page must not be
  /// the one person who never sees that happen.
  ///
  /// One timer for the whole remaining duration rather than a ticker: there is
  /// nothing to redraw until the moment it ends, so a per-second rebuild on the
  /// home page would be a frame a second spent for nothing.
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _armExpiry();
  }

  @override
  void didUpdateWidget(FlashSaleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sale.endsAt != widget.sale.endsAt) {
      _ended = widget.sale.hasEndedAt((widget.now ?? DateTime.now)());
      _armExpiry();
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  void _armExpiry() {
    _expiry?.cancel();
    if (_ended) return;

    final left = widget.sale.remainingAt((widget.now ?? DateTime.now)());
    _expiry = Timer(left, () {
      if (mounted) setState(() => _ended = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ended) return _SaleEnded(onSeeAll: widget.onSeeAllDeals);

    final theme = Theme.of(context);
    final items = widget.sale.items.take(_shown).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(_edge, 18, _edge, 4),
      child: Material(
        // Blended rather than translucent. A wash of Commerce Orange over the
        // page gives the warm panel the design calls for while staying inside
        // the app's own palette -- and blending it flat means the tiles on top
        // are opaque white against a known colour rather than whatever happens
        // to be scrolling underneath.
        color: Color.alphaBlend(
          AppColors.accent.withValues(alpha: 0.13),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onSeeAllDeals,
          // The whole panel, including the gaps between the tiles. The ripple
          // is what tells you the block is one thing.
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _PanelHeading(
                  sale: widget.sale,
                  // No arrow when there is nowhere to go. A chevron that points
                  // at nothing is the thing this app keeps refusing to draw.
                  showChevron: widget.onSeeAllDeals != null,
                ),
                const SizedBox(height: 14),
                _TileGrid(items: items, gap: _gap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The name of the sale and what it is for.
class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.sale, required this.showChevron});

  final FlashSale sale;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subhead = sale.subhead;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                sale.headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // The same weight and size every other section heading on the
                // page uses. It was titleLarge w800, a step above all of them,
                // and one block shouting is what made the page read as a set of
                // things assembled rather than one page.
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 2),
              // Small, and against the heading rather than parked in the
              // corner: the whole panel is the target, so this is a hint about
              // where it leads, not a button competing with it.
              Icon(
                Icons.chevron_right,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
        if (subhead != null && subhead.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subhead,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Four deals, two by two.
///
/// Rows of [Expanded] rather than a [GridView]: this is four fixed tiles, not
/// a scrollable list, and a GridView here would bring a viewport, its own
/// scroll physics and a childAspectRatio that has to be guessed. The tiles size
/// themselves from their content; two in a row are the same width, so they come
/// out the same height without anything being told what that height is.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.items, required this.gap});

  final List<FlashSaleItem> items;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <List<FlashSaleItem>>[
      for (var i = 0; i < items.length; i += 2) items.skip(i).take(2).toList(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: FlashDealTile(item: rows[r].first)),
              SizedBox(width: gap),
              // An odd last deal keeps its column rather than stretching to
              // fill the row: a single wide tile under two square ones reads as
              // a different kind of thing.
              Expanded(
                child: rows[r].length > 1
                    ? FlashDealTile(item: rows[r][1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// What stands where the sale was.
///
/// The grid goes with it. Leaving the tiles up under an "ended" heading would
/// still be advertising prices that are no longer on offer, which is the one
/// thing an expired sale must stop doing.
class _SaleEnded extends StatelessWidget {
  const _SaleEnded({this.onSeeAll});

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusCard + 4),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timer_off_outlined,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This flash sale has ended',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The offer is over and these prices are no longer available. '
              'Pull down to refresh -- the next one may already be running.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onSeeAll,
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('Keep shopping'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

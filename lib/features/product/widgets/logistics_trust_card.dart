import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

import '../../../shared/widgets/page_width.dart';
import '../data/product_detail_content.dart';
import '../data/storefront_config.dart';
import 'product_type_scale.dart';

/// Who carries the order and by when, over what the shop promises either way.
///
/// The window sits in a tinted card -- a statement the shopper is asked to
/// trust, which is what Trust Blue is for in the brand -- and the guarantees
/// sit on the page's own ground below it, as the reference has them: three
/// standing terms, not part of the delivery promise.
class LogisticsTrustCard extends StatelessWidget {
  const LogisticsTrustCard({
    super.key,
    this.guarantee,
    this.assurances = const [],
    this.now,
  });

  /// Null, or switched off, means the shop has not committed to a window --
  /// the card is then left out entirely rather than filled with an estimate
  /// nobody published. The guarantees below stand on their own.
  final DeliveryGuarantee? guarantee;

  final List<Assurance> assurances;

  /// The clock, injectable so a test can pin the window.
  final DateTime Function()? now;

  static const double _radius = AppTheme.radiusSection;

  bool get _hasWindow => guarantee?.enabled ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_hasWindow && assurances.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasWindow) _window(context, theme),
        if (assurances.isNotEmpty) ...[
          // Only when the window above it actually drew. Most listings carry
          // no delivery guarantee, and an unconditional gap here set the
          // trust row twelve below nothing -- which read on the page as the
          // one section gap that had been forgotten.
          if (_hasWindow) const SizedBox(height: 12),
          _trustRow(context, theme),
        ],
      ],
    );
  }

  /// The tinted card: the courier's mark, what it carries, and by when.
  Widget _window(BuildContext context, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final (from, to) = guarantee!.windowFrom((now ?? DateTime.now)());

    return Padding(
      // The page's own measure -- 97% of the screen, centred -- which is what
      // the product card above this one takes. A flat 16 left the guarantees
      // inset further than the card they sit under, and two blocks on the same
      // page starting at different margins read as a mistake.
      padding: EdgeInsets.symmetric(horizontal: PageWidth.marginOf(context)),
      child: Material(
        color: primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          // The chevron is a promise that the whole card does something, so
          // the whole card does it: the same note the ⓘ opens.
          onTap: () => _explainWindow(context),
          borderRadius: BorderRadius.circular(_radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Row(
              children: [
                Icon(Icons.local_shipping_outlined, size: 30, color: primary),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Standard gtradea.com Logistics',
                        style: ProductType.logisticsTitle(theme),
                      ),
                      const SizedBox(height: 3),
                      // A Wrap, not a Row: at a large text size the label and
                      // the dates together are wider than a phone, and the
                      // dates are the half worth keeping whole.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          Text(
                            'Guaranteed delivery:',
                            style: ProductType.deliveryLabel(theme),
                          ),
                          // The dates and their footnote travel together: a
                          // mark that wrapped onto a line of its own would
                          // read as belonging to nothing.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_short(from)} – ${_short(to)}',
                                style: ProductType.deliveryDate(theme),
                              ),
                              const SizedBox(width: 4),
                              _Explain(guarantee: guarantee!),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Returns, payment on delivery and quality checks, in equal thirds in a
  /// card of their own, ruled apart.
  ///
  /// Standing terms -- the same on every listing -- but still one tap each to
  /// what the term actually says. A guarantee a shopper cannot read is
  /// decoration.
  Widget _trustRow(BuildContext context, ThemeData theme) {
    return Padding(
      // The page's own measure -- 97% of the screen, centred -- which is what
      // the product card above this one takes. A flat 16 left the guarantees
      // inset further than the card they sit under, and two blocks on the same
      // page starting at different margins read as a mistake.
      padding: EdgeInsets.symmetric(horizontal: PageWidth.marginOf(context)),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final assurance in assurances) ...[
                if (assurance != assurances.first)
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    indent: 14,
                    endIndent: 14,
                    color: theme.colorScheme.outlineVariant,
                  ),
                Expanded(
                  child: InkWell(
                    onTap: () => _explain(context, assurance),
                    child: Padding(
                      // The mark above the term rather than beside it. Side by
                      // side, a third of a 375dp phone left the text about
                      // ninety points to work in, so "Cash on delivery" was
                      // scaled down to fit while its two neighbours were not --
                      // three terms in a row at three different sizes. Stacked,
                      // each label has the whole cell and they all set at the
                      // same size, which is what makes the row read as one set
                      // of three rather than three separate claims.
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            assurance.icon,
                            // Two points larger, carrying the extra height the
                            // stack gives it. Below this the mark reads as a
                            // bullet; above it, it is doing no work at all.
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          // Kept as a guard, not as the usual case: with the
                          // full cell to sit in these fit at their own size on
                          // a phone, and the scale-down only takes effect if a
                          // translation or a large font setting overruns it.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text(
                              assurance.label,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: ProductType.benefit(theme),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _explainWindow(BuildContext context) {
    final window = guarantee;
    if (window == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guaranteed delivery'),
        content: Text(_windowNote(window)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _explain(BuildContext context, Assurance assurance) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(assurance.icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        assurance.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  assurance.detail,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// "Sep 18". No year: both ends of the window are within weeks, and a year
  /// on a delivery date reads as a warning rather than as information.
  static String _short(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

/// What the dates are counted from, which is the caveat the window needs.
String _windowNote(DeliveryGuarantee guarantee) =>
    'Imported orders clear customs before they are delivered, so the window '
    'is ${guarantee.weeksMin} to ${guarantee.weeksMax} weeks from today '
    'rather than a single date.\n\n'
    'It is an estimate for this route, not a quote for this order — freight '
    'is charged on delivery, as per actual.';

/// The ⓘ beside the window.
///
/// It repeats what the card's own tap does, and earns its place by saying so:
/// a caveat set in small print under every product page is one nobody reads,
/// and a mark beside the dates is where a shopper looks for it.
class _Explain extends StatelessWidget {
  const _Explain({required this.guarantee});

  final DeliveryGuarantee guarantee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkResponse(
      radius: 18,
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Guaranteed delivery'),
          content: Text(_windowNote(guarantee)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
      child: Semantics(
        button: true,
        label: 'What guaranteed delivery means',
        child: Icon(
          Icons.info_outline,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

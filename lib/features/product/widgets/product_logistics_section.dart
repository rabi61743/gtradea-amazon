import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/theme/colors.dart';

import '../../address/data/address_store.dart';
import '../../cart/data/cart_store.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../checkout/data/checkout_repository.dart' show DeliveryQuote;
import '../../logistics/data/logistics_quotes.dart';
import '../../logistics/data/shipping_mode_store.dart';
import '../data/storefront_config.dart';
import 'product_type_scale.dart';

/// How this order will be carried, inside the product card.
///
/// A line rather than a card: it sits under the summary, on the same ground as
/// the price and the quantity above it, because how a thing arrives is part of
/// what is being bought and not a separate offer beside it.
///
/// Tapping it opens the shop's own list of ways to ship. **Everything in that
/// list is the server's**: the modes and their names come from the site
/// settings ([StorefrontConfigRepository.logistics]), and each one's freight
/// comes from `POST /checkout/delivery-charge` priced for this product, this
/// variant, this quantity and the shopper's own district. Nothing is named,
/// rated or estimated here -- a shop that publishes two modes shows two, one
/// that publishes four shows four, and one that publishes none says so.
///
/// Choosing a mode is not a label. [ShippingModeStore] holds the choice for
/// the whole app, so the cart prices freight by it and the checkout places the
/// order under it.
class ProductLogisticsSection extends StatefulWidget {
  const ProductLogisticsSection({super.key, required this.lines});

  /// The product as it is currently configured -- variant and quantity
  /// included, since freight is priced on what is actually being bought.
  final List<CartLine> lines;

  @override
  State<ProductLogisticsSection> createState() =>
      _ProductLogisticsSectionState();
}

class _ProductLogisticsSectionState extends State<ProductLogisticsSection> {
  final LogisticsQuotes _quotes = LogisticsQuotes();

  ShippingModeStore get _store => ShippingModeStore.instance;

  /// Where this order is going, which is what freight is priced against.
  String? get _district => AddressStore.instance.defaultAddress?.city;

  @override
  void initState() {
    super.initState();
    _store.load();
    _store.addListener(_modesChanged);
    AddressStore.instance.addListener(_addressChanged);
    // The options are on the page rather than behind a tap now, so their
    // figures are asked for with them. The request is skipped where it cannot
    // answer for this product anyway -- see [LogisticsQuotes.load].
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshQuotes());
  }

  @override
  void didUpdateWidget(ProductLogisticsSection old) {
    super.didUpdateWidget(old);
    // A different variant or a different count is a different order, and the
    // freight already shown was priced for the old one.
    //
    // Asked every time, not only when there is already a figure to replace.
    // Guarding on having quotes meant a page that opened with nothing chosen
    // -- which is every page with a variant grid -- never asked at all once a
    // quantity was typed, because it had no quote to refresh. [LogisticsQuotes
    // .load] does its own de-duplication on the lines, the district and the
    // modes, so calling it on every rebuild costs nothing.
    _refreshQuotes();
  }

  /// The options landed. Freight is priced for them now -- once, and only once
  /// there is something to price it for.
  void _modesChanged() {
    if (_store.modes.isEmpty) return;
    if (_quotes.hasQuotes || _quotes.isLoading || _quotes.error != null) return;
    _refreshQuotes();
  }

  @override
  void dispose() {
    _store.removeListener(_modesChanged);
    AddressStore.instance.removeListener(_addressChanged);
    _quotes.dispose();
    super.dispose();
  }

  /// A new destination reprices freight, which is quoted to a district.
  void _addressChanged() {
    if (_quotes.hasQuotes || _quotes.error != null) _refreshQuotes();
  }

  Future<void> _refreshQuotes({bool force = false}) => _quotes.load(
    lines: widget.lines,
    district: _district,
    modes: _store.modes,
    force: force,
  );

  void _choose(LogisticsMode mode) => _store.select(mode.key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        _store,
        _quotes,
        AddressStore.instance,
        CartStore.instance,
      ]),
      builder: (context, _) {
        final modes = _store.modes;

        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusSection),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(theme),
              const SizedBox(height: 10),
              if (modes.isEmpty && _store.isLoading)
                _note(theme, 'Fetching delivery options...', spinner: true)
              else if (modes.isEmpty && _store.error != null)
                _note(
                  theme,
                  'Delivery options are unavailable just now.',
                  onRetry: () => _store.load(force: true),
                )
              else if (modes.isEmpty)
                _note(theme, 'The shop publishes no delivery options.')
              else
                for (final mode in modes) _optionCard(theme, mode),
              ..._figureNotes(theme),
            ],
          ),
        );
      },
    );
  }

  /// The mark, the heading and the line under it.
  ///
  /// The words here are the section's own -- they name the control rather than
  /// state a fact about this order, and nothing about them changes with the
  /// server's answer. Every figure below them is the server's.
  Widget _header(ThemeData theme) {
    final footnote = _store.config.footnote;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The supplied mark, unmodified.
        Image.asset(
          'assets/images/logistics_truck.png',
          width: 38,
          height: 29,
          errorBuilder: (context, error, stack) => Icon(
            Icons.local_shipping_outlined,
            size: 26,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'gtradea.com Delivery Options',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Choose what matters most to you.',
                style: ProductType.meta(theme),
              ),
            ],
          ),
        ),
        // Only where the shop has actually written one. An information button
        // that opens an empty sheet is a control that lies about having
        // something to say.
        if (footnote != null && footnote.isNotEmpty)
          Tooltip(
            message: footnote,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 6),
            child: Icon(
              Icons.info_outline,
              size: 20,
              color: theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }

  /// One way to ship, as the shop published it.
  Widget _optionCard(ThemeData theme, LogisticsMode mode) {
    final chosen = mode.key == _store.selected?.key;
    final config = _store.config;
    final quote = _quotes.forMode(mode.key);

    // What the shop says about this mode beyond its name -- each part only
    // where the shop actually publishes it.
    final rate = mode.listed && mode.perKg != null
        ? '${formatRupees(mode.perKg!)}/kg'
        : null;
    final discount = config.discountsApply && mode.discountPercent > 0
        ? '${mode.discountPercent}% off goods'
        : null;
    final detail = [?rate, ?discount].join(' \u00b7 ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // One control, named and with its state, rather than a radio and some
      // text a screen reader reads as unrelated things.
      child: Semantics(
        button: true,
        inMutuallyExclusiveGroup: true,
        selected: chosen,
        // No label of its own: the row's own words -- the mode, the window,
        // the figure -- are what a reader should hear, and a label here would
        // replace them with the name alone.
        child: Material(
          color: chosen
              ? theme.colorScheme.primary.withValues(alpha: 0.05)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _choose(mode),
            // Told to a pointer and to a keyboard as well as to a finger. The
            // defaults are drawn from the theme's primary, so the three states
            // are the same wash at different strengths rather than three
            // different colours.
            hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
            focusColor: theme.colorScheme.primary.withValues(alpha: 0.08),
            splashColor: theme.colorScheme.primary.withValues(alpha: 0.10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: chosen
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: chosen ? 1.6 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    chosen
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: chosen
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  // What carries it: a plane, a lorry, a ship. By the key the
                  // server gave the mode, with the lorry for a mode this app has
                  // no mark for -- a generic carriage rather than one of the
                  // three misapplied.
                  //
                  // The app's own icon set at the app's own weight, so the three
                  // read as one component rather than as three stickers.
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: chosen
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _markFor(mode.key),
                      size: 21,
                      color: chosen
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          mode.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (detail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ProductType.meta(theme),
                            ),
                          ),
                        // The shop's own delivery window. One window, published
                        // once for the whole shop rather than per mode, so it
                        // reads the same on each -- which is what the settings
                        // actually say.
                        if (config.hasLeadTime)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _leadChip(theme, config),
                          ),
                        // And everything else the server said about this quote.
                        if (quote != null) _quoteDetail(theme, quote),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Shrink(child: _figure(theme, quote)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What the server sent about this quote beyond the figure.
  ///
  /// Where it went, what it was charged on, who priced it, and what it took
  /// off -- each one only where the server actually filled it in. Nothing here
  /// is computed by the app; every part is a field of the response.
  Widget _quoteDetail(ThemeData theme, DeliveryQuote quote) {
    final parts = <String>[
      // Where it was priced to. The server echoes the district back, which is
      // the only confirmation this is a quote for the shopper's destination.
      ?quote.district,
      // What it was billed on. 'higher' is the server comparing real against
      // volumetric weight and charging the greater.
      if (quote.chargeableKg != null)
        '${quote.chargeableKg} kg${quote.weightBasis == 'higher' ? ' chargeable' : ''}',
      // Who priced it: a live carrier rate, or the shop's own table.
      if (quote.freightSource == 'api') 'carrier rate',
      // What the shop took off for combining this with other orders.
      if (quote.combineDiscount > 0)
        '${formatRupees(quote.combineDiscount)} combined off',
      // Who collects it. The shop sets this per quote, and the two are not the
      // same promise: one is paid now, the other on the doorstep.
      quote.isCollectedUpfront ? 'paid at checkout' : 'paid on delivery',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Shrink(
            child: Text(
              parts.join(' \u00b7 '),
              maxLines: 1,
              style: ProductType.meta(theme),
            ),
          ),
          // The server's own flag, said plainly: it could not get a rate from
          // the carrier and fell back to its minimum, so this figure may move.
          if (quote.unpriceable)
            _Shrink(
              child: Text(
                'Estimated -- the carrier gave no rate for this item.',
                maxLines: 1,
                style: ProductType.meta(theme)
                    .copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  /// The delivery window, in the pill the reference sets it in.
  Widget _leadChip(ThemeData theme, LogisticsConfig config) {
    return _Shrink(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              'Arrives in ${config.leadDaysMin} - ${config.leadDaysMax} days',
              style: ProductType.meta(theme),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  /// The freight the server quoted for this mode, or an honest blank.
  Widget _figure(ThemeData theme, DeliveryQuote? quote) {
    if (quote != null) {
      // Zero is a quote, and what it says is that carriage costs nothing --
      // not that there is no quote. The two used to be indistinguishable.
      if (quote.isFree) {
        return Text(
          'Free',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.success,
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatRupees(quote.total),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          // The tax already inside that figure, where the server itemised it.
          if (quote.vat > 0)
            Text(
              'incl. ${formatRupees(quote.vat)} VAT',
              style: ProductType.meta(theme),
            ),
        ],
      );
    }

    // Nothing invented in its place. Which blank depends on why there is no
    // figure, and the reason is spelled out under the list -- see
    // [_figureNotes].
    final waiting =
        _quotes.isLoading || _district == null || widget.lines.isEmpty;

    return Text(
      waiting ? '--' : 'At checkout',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// Why the figures are what they are: a wait, a failure, or a reason.
  List<Widget> _figureNotes(ThemeData theme) {
    if (_store.modes.isEmpty) return const [];

    if (_quotes.isLoading) {
      return [_note(theme, 'Pricing freight for this order...', spinner: true)];
    }
    if (_quotes.error != null) {
      return [
        _note(
          theme,
          _quotes.error!.isNetwork
              ? 'No connection, so freight could not be priced.'
              : 'Freight could not be priced right now.',
          onRetry: () => _refreshQuotes(force: true),
        ),
      ];
    }
    if (widget.lines.isEmpty) {
      return [
        _note(theme, 'Choose what you want above to see freight for it.'),
      ];
    }
    if (_district == null) {
      return [
        _note(theme, 'Add a delivery address to see freight for each option.'),
      ];
    }
    if (!_quotes.hasQuotes) {
      return [_note(theme, 'Freight is worked out at checkout.')];
    }
    return const [];
  }

  /// The mark for a mode, by the key the server gave it.
  ///
  /// The carriage itself rather than a mood: a shopper reading "By Air" beside
  /// a lightning bolt has to work out that the bolt means speed and the speed
  /// means flying. A plane says it in one look.
  ///
  /// A mode this app has no mark for gets the lorry, which is carriage without
  /// claiming a manner of it.
  static IconData _markFor(String key) => switch (key) {
    'air' => Icons.flight,
    'land' => Icons.local_shipping,
    'sea' => Icons.directions_boat,
    _ => Icons.local_shipping_outlined,
  };

  /// A line that is not an option: a wait, a failure, or the reason there are
  /// no figures beside the names.
  Widget _note(
    ThemeData theme,
    String message, {
    bool spinner = false,
    VoidCallback? onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Said in words, with a still mark beside them rather than a turning
          // one. This section is on the page from the moment a product opens,
          // and an indeterminate indicator animates for as long as it is shown
          // -- which is a page that never comes to rest, for every product,
          // and every widget test that pumps one.
          if (spinner) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.hourglass_empty,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(message, style: ProductType.meta(theme))),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Room to shrink only if it is ever needed.
///
/// Everything in this section is the shop's own words and figures, and a shop
/// can write a longer one than fits. Scaled a little beats an overflow, and
/// beats truncating a number.
class _Shrink extends StatelessWidget {
  const _Shrink({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: child,
  );
}

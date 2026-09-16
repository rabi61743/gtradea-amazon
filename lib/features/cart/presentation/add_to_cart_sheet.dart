import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/network/api_error.dart';
import '../../../core/images/app_images.dart';
import '../../catalog/data/product.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../product/data/product_detail_content.dart';
import '../../product/data/product_repository.dart';
import '../../product/widgets/option_chips.dart';
import '../data/cart_store.dart';
import '../data/cart_variant_catalogue.dart';

/// Choosing a product's options without leaving the list it was found in.
///
/// The cart button on a card used to add the product outright, at the seller's
/// minimum and with no variant at all -- so a shirt reached the cart with no
/// size and no colour on it, and the choice had to be made again later in the
/// cart. This asks first.
///
/// Everything in it is the seller's: the axes are derived from the published
/// SKUs by [axesOf], a combination that was never published cannot be picked,
/// the minimum is the record's own, and the price is the one the product page
/// would show for the same choice. Nothing here is a second catalogue.
///
/// The product page is untouched. It has room for the full record and its own
/// way of showing it; this is the short form, for a card.
class AddToCartSheet extends StatefulWidget {
  const AddToCartSheet({super.key, required this.product});

  final Product product;

  /// Opens the sheet. Resolves true if the product was added.
  static Future<bool?> show(BuildContext context, Product product) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddToCartSheet(product: product),
    );
  }

  @override
  State<AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends State<AddToCartSheet> {
  ProductDetail? _detail;
  Object? _error;

  /// What has been picked on each axis, by axis index. An axis missing from
  /// this map is an axis still to be answered, which is what keeps the button
  /// reading "Select an option".
  final Map<int, String> _picked = {};

  late int _quantity = widget.product.minOrder;
  bool _adding = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    // A record the shopper has already opened, or one warmed by another card,
    // is here now -- no skeleton, no wait.
    final cached = ProductRepository.instance.cachedDetail(
      widget.product.numIid,
    );
    if (cached != null) {
      _detail = ProductDetail.fromApi(cached, fallback: widget.product);
      _quantity = _minOrder;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final body = await ProductRepository.instance.detail(
        widget.product.numIid,
      );
      if (!mounted) return;
      setState(() {
        _detail = ProductDetail.fromApi(body, fallback: widget.product);
        _quantity = _minOrder;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  int get _minOrder {
    final moq = _detail?.minOrder ?? widget.product.minOrder;
    return moq > 0 ? moq : 1;
  }

  List<ProductVariant> get _variants => _detail?.variants ?? const [];

  List<VariantAxis> get _axes => axesOf(_variants);

  /// The variant the current picks land on, if they land on one at all.
  ProductVariant? get _selected {
    final axes = _axes;
    if (axes.isEmpty) return null;
    if (_picked.length < axes.length) return null;

    final depth = _variants.fold<int>(
      0,
      (a, v) => a > v.axisValues.length ? a : v.axisValues.length,
    );
    final values = [
      for (var i = 0; i < depth; i++)
        _picked[i] ??
            (_variants.first.axisValues.length > i
                ? _variants.first.axisValues[i]
                : ''),
    ];
    return variantAt(_variants, values);
  }

  /// Whether a value on [axis] can be reached from what is already picked.
  ///
  /// A size the chosen colour does not come in is not offered: the seller
  /// never published that pairing, and a control that cannot lead anywhere is
  /// worse than no control.
  bool _reachable(VariantAxis axis, String value) {
    for (final variant in _variants) {
      if (axis.index >= variant.axisValues.length) continue;
      if (variant.axisValues[axis.index] != value) continue;
      var fits = true;
      for (final entry in _picked.entries) {
        if (entry.key == axis.index) continue;
        if (entry.key >= variant.axisValues.length ||
            variant.axisValues[entry.key] != entry.value) {
          fits = false;
          break;
        }
      }
      if (fits && variant.inStock) return true;
    }
    return false;
  }

  /// The picture for a value, where the seller published one. This is what
  /// makes a colour row read as colours rather than as words.
  String? _imageFor(VariantAxis axis, String value) {
    for (final variant in _variants) {
      if (axis.index >= variant.axisValues.length) continue;
      if (variant.axisValues[axis.index] != value) continue;
      final url = variant.imageUrl;
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  num get _unitPrice =>
      _selected?.price ??
      _detail?.priceAt(_quantity) ??
      widget.product.displayPrice ??
      0;

  bool get _answered => _picked.length >= _axes.length;

  bool get _soldOut => _selected?.inStock == false;

  /// The line this sheet would add, built on the product page's own rules:
  /// a variant's own price beats the ladder, and the ladder only travels with
  /// the line when it is what set the price.
  CartLine? get _line {
    final detail = _detail;
    if (detail == null) return null;
    final variant = _selected;
    return CartLine(
      productId: detail.numIid,
      title: detail.title,
      unitPrice: _unitPrice,
      variantLabel: variant?.label,
      imageUrl: (variant?.imageUrl.isNotEmpty ?? false)
          ? variant!.imageUrl
          : (detail.images.isNotEmpty
                ? detail.images.first
                : widget.product.imageUrl),
      quantity: _quantity,
      minOrder: _minOrder,
      freeDelivery: detail.freeDelivery,
      category: detail.category ?? widget.product.categoryName,
      categoryCid: widget.product.categoryCid,
      source: '1688',
      skuId: variant?.skuId,
      specId: variant?.specId,
      tiers: variant?.price == null ? detail.tiers : const [],
    );
  }

  Future<void> _add() async {
    if (_adding) return;
    final line = _line;
    if (line == null || !_answered || _soldOut) return;

    setState(() {
      _adding = true;
      _failure = null;
    });

    try {
      CartStore.instance.add(line);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _adding = false;
        _failure = e is ApiError
            ? e.message
            : 'Could not add this to the cart.';
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = _detail;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(
              product: widget.product,
              detail: detail,
              unitPrice: _priceShown,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _body(theme),
              ),
            ),
            _Footer(
              label: _buttonLabel,
              enabled: detail != null && _answered && !_soldOut && !_adding,
              busy: _adding,
              onPressed: _add,
            ),
          ],
        ),
      ),
    );
  }

  /// What the header says the product costs: the chosen option's price once
  /// there is one, the record's own before that.
  num? get _priceShown {
    if (_detail == null) return widget.product.displayPrice;
    final price = _unitPrice;
    return price > 0 ? price : null;
  }

  String get _buttonLabel {
    if (_error != null) return 'Try again';
    if (_soldOut) return 'Sold out';
    if (!_answered) return 'Select an option';
    return 'Add to cart';
  }

  Widget _body(ThemeData theme) {
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The options for this product could not be loaded.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _error = null);
              _load();
            },
            child: const Text('Try again'),
          ),
        ],
      );
    }

    final detail = _detail;
    if (detail == null) return const _OptionsSkeleton();

    final axes = _axes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final axis in axes) ...[
          _AxisGroup(
            axis: axis,
            picked: _picked[axis.index],
            imageFor: (value) => _imageFor(axis, value),
            reachable: (value) => _reachable(axis, value),
            onPicked: (value) => setState(() => _picked[axis.index] = value),
          ),
          const SizedBox(height: 12),
        ],
        if (_soldOut)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'That option is sold out.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        _QuantityRow(
          quantity: _quantity,
          minOrder: _minOrder,
          unitLabel: detail.unitLabel,
          onChanged: (q) => setState(() => _quantity = q),
        ),
        if (_failure != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _failure!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// The product, in the few facts a shopper needs to recognise it: its picture,
/// its name and what it costs. No description, by design -- this sheet is for
/// choosing, and the card it opened from has already said what the product is.
class _Header extends StatelessWidget {
  const _Header({
    required this.product,
    required this.detail,
    required this.unitPrice,
    required this.onClose,
  });

  final Product product;
  final ProductDetail? detail;
  final num? unitPrice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discount = detail?.discountPercent;
    final listPrice = detail?.listPrice;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: SizedBox(
              width: 64,
              height: 64,
              child: product.imageUrl == null
                  ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                  : Image(
                      image: AppImages.of(
                        product.imageUrl!,
                        width: 64,
                        devicePixelRatio: MediaQuery.devicePixelRatioOf(
                          context,
                        ),
                      ),
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                // Wrapped rather than a row: a price, a struck was-price and a
                // badge do not fit beside a thumbnail on a narrow phone, and
                // the part that would be pushed off is the saving.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      unitPrice == null
                          ? 'Price on request'
                          : formatRupees(unitPrice!),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.trustBlue,
                      ),
                    ),
                    // Only where the seller published a price to compare
                    // against: a percentage off nothing is a claim, not a
                    // fact, and this catalogue leaves the was-price empty on
                    // most records.
                    if (listPrice != null && discount != null) ...[
                      Text(
                        'Was: ${formatRupees(listPrice)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      _OffPill(percent: discount),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _OffPill extends StatelessWidget {
  const _OffPill({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.accent),
      ),
      child: Text(
        '$percent% OFF',
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One axis the seller published, with its own name over it.
class _AxisGroup extends StatelessWidget {
  const _AxisGroup({
    required this.axis,
    required this.picked,
    required this.imageFor,
    required this.reachable,
    required this.onPicked,
  });

  final VariantAxis axis;
  final String? picked;
  final String? Function(String value) imageFor;
  final bool Function(String value) reachable;
  final ValueChanged<String> onPicked;

  /// An axis whose values come with pictures *of their own* is drawn as
  /// pictures. That is what a colour row is: the word "Khaki" is not the
  /// colour.
  ///
  /// Sizes usually carry a picture too, and it is the same picture on every
  /// one of them -- a row of identical photographs says nothing, and the size
  /// is the only part worth reading. So the test is whether the pictures
  /// differ, not whether they exist.
  /// Whether this axis is the one sizes are on, by the seller's own name for
  /// it -- the same test the product page's picker makes.
  bool get _isSize => axis.name.toLowerCase().contains('size');

  bool get _pictorial {
    final seen = <String>{};
    for (final value in axis.values) {
      final url = imageFor(value);
      if (url == null) return false;
      seen.add(url);
    }
    return seen.length > 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              axis.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (_isSize) const _SizeGuideTag(),
          ],
        ),
        const SizedBox(height: 8),
        if (_pictorial)
          _Swatches(
            axis: axis,
            picked: picked,
            imageFor: imageFor,
            reachable: reachable,
            onPicked: onPicked,
          )
        else
          OptionChips(
            options: [
              for (final value in axis.values)
                ChipOption(
                  label: shortVariantLabel(value),
                  available: reachable(value),
                  tooltip: value,
                ),
            ],
            selectedIndex: picked == null ? -1 : axis.values.indexOf(picked!),
            onSelected: (i) {
              final value = axis.values[i];
              if (reachable(value)) onPicked(value);
            },
          ),
      ],
    );
  }
}

/// The "Size guide" mark beside a size heading.
///
/// A label, and only a label: it opens nothing and measures nothing, because
/// nothing was asked for behind it. Drawn as the reference draws it -- a pale
/// rounded tag at the right of the heading -- and marked as decoration so a
/// screen reader does not announce a control that cannot be used.
class _SizeGuideTag extends StatelessWidget {
  const _SizeGuideTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.straighten,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Size guide',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.axis,
    required this.picked,
    required this.imageFor,
    required this.reachable,
    required this.onPicked,
  });

  final VariantAxis axis;
  final String? picked;
  final String? Function(String value) imageFor;
  final bool Function(String value) reachable;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: axis.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final value = axis.values[i];
          final url = imageFor(value);
          final chosen = value == picked;
          final available = reachable(value);

          return Opacity(
            opacity: available ? 1 : 0.35,
            child: InkWell(
              onTap: available ? () => onPicked(value) : null,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              child: Container(
                width: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(
                    color: chosen
                        ? AppColors.trustBlue
                        : theme.colorScheme.outlineVariant,
                    width: chosen ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Expanded(
                      child: url == null
                          ? ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                            )
                          : Image(
                              image: AppImages.of(
                                url,
                                width: 92,
                                devicePixelRatio: MediaQuery.devicePixelRatioOf(
                                  context,
                                ),
                              ),
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Text(
                        shortVariantLabel(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// How many, never fewer than the seller will sell.
class _QuantityRow extends StatelessWidget {
  const _QuantityRow({
    required this.quantity,
    required this.minOrder,
    required this.unitLabel,
    required this.onChanged,
  });

  final int quantity;
  final int minOrder;
  final String? unitLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRemove = quantity > minOrder;
    final canAdd = quantity < CartStore.maxPerLine;

    return Row(
      children: [
        Text(
          'Qty',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: canRemove ? () => onChanged(quantity - 1) : null,
                icon: const Icon(Icons.remove),
                tooltip: 'One fewer',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '$quantity',
                  key: const ValueKey('sheet-quantity'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: canAdd ? () => onChanged(quantity + 1) : null,
                icon: const Icon(Icons.add),
                tooltip: 'One more',
              ),
            ],
          ),
        ),
        if (minOrder > 1) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Min. order: $minOrder ${unitLabel ?? 'pcs'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          key: const ValueKey('sheet-add-to-cart'),
          onPressed: enabled ? onPressed : null,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      ),
    );
  }
}

/// While the record is on its way. The sheet opens straight away rather than
/// waiting for the catalogue: a shopper who tapped a cart button should see
/// something happen.
class _OptionsSkeleton extends StatelessWidget {
  const _OptionsSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(80, 14),
        bar(double.infinity, 40),
        bar(60, 14),
        bar(180, 40),
      ],
    );
  }
}

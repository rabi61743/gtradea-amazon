import 'package:flutter/material.dart';

import '../../../core/images/app_images.dart';
import '../../../core/network/api_error.dart';
import '../../product/data/product_detail_content.dart';
import '../data/cart_store.dart';
import '../data/cart_variant_catalogue.dart';

/// The variant dropdowns inside one cart line.
///
/// One per axis the seller published -- "Color", "Size", whatever they called
/// them -- built from the catalogue's own variants rather than from any list
/// this app keeps. A product with no variants draws nothing at all, which is
/// most of the cart most of the time.
///
/// Changing one is a real change to the basket: the line is swapped for the
/// same product in the chosen variant, at that variant's own price and
/// photograph, and the account is written to before the control comes back to
/// life. See [CartStore.changeVariant] for why that is a swap rather than an
/// edit.
///
/// A combination the seller never published cannot be reached: values that
/// would make one are shown and refused rather than hidden, so a shopper can
/// see that the medium exists and simply not in that colour.
class CartVariantPickers extends StatefulWidget {
  const CartVariantPickers({super.key, required this.line});

  final CartLine line;

  @override
  State<CartVariantPickers> createState() => _CartVariantPickersState();
}

class _CartVariantPickersState extends State<CartVariantPickers> {
  /// Null until the catalogue has answered for this product.
  List<ProductVariant>? _variants;

  /// Set when the catalogue could not be reached.
  Object? _loadError;

  /// True while a chosen variant is being written to the account.
  bool _applying = false;

  /// Set when that write did not land.
  String? _applyError;

  /// What is chosen on each axis, by axis index.
  ///
  /// Seeded from the line's own variant where it has one, and left partly empty
  /// where it does not -- a line added without choosing anything, which is what
  /// a quick add from a rail produces. Half a choice cannot identify a SKU, so
  /// nothing is written to the cart until every axis has a value.
  final Map<int, String> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CartVariantPickers old) {
    super.didUpdateWidget(old);
    // A different product in the same slot: the list rebuilds its children as
    // lines are removed, and the options must follow the line.
    if (old.line.productId != widget.line.productId) {
      _variants = null;
      _loadError = null;
      _load();
    }
  }

  /// Fills [_picked] from whatever the line already stands for.
  void _seed(List<ProductVariant> variants) {
    _picked.clear();
    final current = variantForLine(
      variants,
      skuId: widget.line.skuId,
      label: widget.line.variantLabel,
    );
    if (current == null) return;
    for (var i = 0; i < current.axisValues.length; i++) {
      _picked[i] = current.axisValues[i];
    }
  }

  Future<void> _load() async {
    final productId = widget.line.productId;

    // Already parsed for this product: no frame is spent on a spinner for
    // something that is in memory.
    final known = CartVariantCatalogue.instance.cached(productId);
    if (known != null) {
      setState(() {
        _variants = known;
        _seed(known);
      });
      return;
    }

    try {
      final variants = await CartVariantCatalogue.instance.variantsFor(
        productId,
      );
      if (!mounted || productId != widget.line.productId) return;
      setState(() {
        _variants = variants;
        _loadError = null;
        _seed(variants);
      });
    } on ApiError catch (e) {
      if (!mounted || productId != widget.line.productId) return;
      setState(() => _loadError = e);
    }
  }

  /// Records a value on one axis, and writes the line once the set is whole.
  Future<void> _choose(VariantAxis axis, String value) async {
    final variants = _variants;
    if (variants == null || _applying) return;

    setState(() {
      _picked[axis.index] = value;
      _applyError = null;
    });

    final axes = axesOf(variants);
    // Half a choice. The shopper has said which colour and not yet which size,
    // and there is no SKU to put in the cart until they have said both -- so
    // the picker holds what they said and waits rather than guessing the rest.
    if (axes.any((a) => _picked[a.index] == null)) return;

    final depth = variants
        .map((v) => v.axisValues.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final values = [
      for (var i = 0; i < depth; i++) _picked[i] ?? _onlyValueAt(variants, i),
    ];
    if (values.any((v) => v == null)) return;

    final target = variantAt(variants, values.cast<String>());
    // Refused rather than approximated. Picking the nearest thing the seller
    // does make is a decision for the shopper, not for the cart.
    if (target == null || !target.inStock) return;
    if (target.skuId != null && target.skuId == widget.line.skuId) return;

    setState(() {
      _applying = true;
      _applyError = null;
    });

    final store = CartStore.instance;
    store.changeVariant(
      widget.line.key,
      variantLabel: target.label,
      skuId: target.skuId,
      specId: target.specId,
      // The variant's own price when the seller prices them apart. Null leaves
      // the line's price alone, which is right for a seller who does not.
      unitPrice: target.price,
      imageUrl: target.imageUrl.isEmpty ? null : target.imageUrl,
    );

    try {
      // Waited on, so the control is dead until the account has it. Without
      // this the shopper is told the colour changed and the write is still six
      // hundred milliseconds away, with nothing to say if it fails.
      await store.syncNow();
    } finally {
      if (mounted) setState(() => _applying = false);
    }

    if (!mounted) return;
    final error = store.syncError;
    setState(() {
      _applyError = error == null
          ? null
          : error.isNetwork
          ? 'Changed here only - no connection to your account.'
          : 'Not saved to your account: ${error.message}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadError != null) {
      return _Note(
        icon: Icons.error_outline,
        color: theme.colorScheme.error,
        text: 'Options unavailable just now.',
        onRetry: () {
          setState(() => _loadError = null);
          _load();
        },
      );
    }

    final variants = _variants;
    if (variants == null) {
      // A bar rather than a spinner, and a still one. An indeterminate
      // indicator animates for as long as it is on screen, which never settles
      // -- every widget test that pumps this page to rest would hang on it,
      // and a cart of six lines would keep six animations running for a
      // request that usually takes a moment.
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }

    final axes = axesOf(variants);
    if (axes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrapped rather than a Row: two dropdowns fit beside each other on
          // anything wider than a small phone and stack when they do not,
          // without a breakpoint to keep in step with the tile's own padding.
          LayoutBuilder(
            builder: (context, constraints) {
              final each = axes.length > 1 && constraints.maxWidth >= 260
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final axis in axes)
                    SizedBox(
                      width: each,
                      child: _AxisPicker(
                        axis: axis,
                        variants: variants,
                        picked: _picked,
                        enabled: !_applying,
                        onChanged: (value) => _choose(axis, value),
                      ),
                    ),
                ],
              );
            },
          ),
          // Said in words rather than drawn as a moving bar, for the reason
          // above: this is on screen while the account is written to, and an
          // animation there would stop the page ever coming to rest.
          if (_applying)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Updating...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_applyError != null)
            _Note(
              icon: Icons.error_outline,
              color: theme.colorScheme.error,
              text: _applyError!,
            ),
        ],
      ),
    );
  }
}

/// One axis as a dropdown.
class _AxisPicker extends StatelessWidget {
  const _AxisPicker({
    required this.axis,
    required this.variants,
    required this.picked,
    required this.enabled,
    required this.onChanged,
  });

  final VariantAxis axis;
  final List<ProductVariant> variants;

  /// What is chosen on every axis so far, by axis index.
  final Map<int, String> picked;

  final bool enabled;
  final ValueChanged<String> onChanged;

  /// Whether [value] is one the shopper can actually get, given what they have
  /// already settled on the other axes.
  ///
  /// Axes they have not settled yet place no constraint: before a size is
  /// chosen every colour the seller stocks in any size is reachable, and the
  /// list narrows as the other axes are filled in.
  bool _reachable(String value) {
    for (final variant in variants) {
      if (!variant.inStock) continue;
      if (axis.index >= variant.axisValues.length) continue;
      if (variant.axisValues[axis.index] != value) continue;

      var fits = true;
      for (final entry in picked.entries) {
        if (entry.key == axis.index) continue;
        if (entry.key >= variant.axisValues.length) continue;
        if (variant.axisValues[entry.key] != entry.value) {
          fits = false;
          break;
        }
      }
      if (fits) return true;
    }
    return false;
  }

  /// What to write in the list for [value].
  ///
  /// The catalogue's short form where it still tells one option from another,
  /// and the seller's own text where it does not. Measured on a live listing:
  /// its colours are written "Polo【white】", "Polo【black】" and so on, and the
  /// short form cuts every one of them down to "Polo" -- a dropdown of eighteen
  /// identical entries. Shortening is a convenience; distinguishing them is the
  /// entire job.
  String _labelFor(String value) {
    final short = shortVariantLabel(value);
    for (final other in axis.values) {
      if (other == value) continue;
      if (shortVariantLabel(other) == short) return value.trim();
    }
    return short;
  }

  /// The seller's own photograph of [value], when this axis is the one the
  /// seller photographs.
  ///
  /// Sellers shoot the colourway, not the colour-and-size, so on a colour axis
  /// each value has its own picture and on a size axis they all share one. An
  /// axis whose values do not carry at least two different pictures is not
  /// shown with thumbnails at all -- a row of identical thumbnails beside
  /// "S, M, L" would say nothing.
  String? _photoFor(String value) {
    final photos = <String, String>{};
    for (final variant in variants) {
      if (axis.index >= variant.axisValues.length) continue;
      if (variant.imageUrl.isEmpty) continue;
      photos.putIfAbsent(variant.axisValues[axis.index], () => variant.imageUrl);
    }
    if (photos.values.toSet().length < 2) return null;
    return photos[value];
  }

  /// What the small indicator beside [value] shows, or null for none.
  ///
  /// The catalogue publishes no colour codes -- a colour is a name, and a SKU
  /// may carry a photograph -- so the indicator is built only from those.
  ///
  /// A plain dot first, where the seller's name for the colour contains an
  /// ordinary colour word: "Pink", "Lake green", "Sapphire blue". The photo
  /// only after that. Measured on a live listing, a seller's per-colour photos
  /// were all crops of one group shot of every colourway, and at 14pt six of
  /// them looked alike -- a dot says "pink" where that thumbnail cannot. The
  /// photo is still the right indicator for a name with no colour in it
  /// ("Floral print"), and a name with neither gets none rather than a guess.
  _Swatch? _swatchFor(String value) {
    final key = ValueKey('swatch:$value');
    if (_isColourAxis(axis.name)) {
      final colour = colourNamed(value);
      if (colour != null) return _Swatch.colour(colour, key: key);
    }
    final photo = _photoFor(value);
    return photo == null ? null : _Swatch.photo(photo, key: key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = picked[axis.index];
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final nameStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // The closed control: the axis name, then what is chosen on it, on one
    // line. The name used to be a floating label, which is what made each
    // selector a two-line box -- written inline it costs width, not height.
    Widget closed(String? value) => Row(
      children: [
        Text(axis.name, style: nameStyle),
        const SizedBox(width: 6),
        if (value != null) ...[
          if (_swatchFor(value) case final swatch?) ...[
            swatch,
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              _labelFor(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ),
        ],
      ],
    );

    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      isDense: true,
      // The line's own type scale. A cart tile is a dense thing and the
      // dropdown has to sit inside it rather than take it over.
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
      icon: Icon(
        Icons.expand_more_rounded,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      borderRadius: BorderRadius.circular(10),
      // Long colour lists scroll inside the menu rather than filling the
      // screen with it.
      menuMaxHeight: 320,
      decoration: const InputDecoration(
        isDense: true,
        // 7 above and below the dense 24pt line: a 38pt control, slimmer than
        // the labelled box it replaces and still an easy target for a thumb.
        contentPadding: EdgeInsets.fromLTRB(10, 7, 6, 7),
      ),
      hint: closed(null),
      selectedItemBuilder: (context) => [
        for (final value in axis.values) closed(value),
      ],
      items: [
        for (final value in axis.values)
          DropdownMenuItem<String>(
            value: value,
            // Shown and refused rather than dropped: a size missing from the
            // list reads as a size the seller does not make, when in fact it
            // is one they do not make in this colour.
            enabled: _reachable(value),
            child: Row(
              children: [
                if (_swatchFor(value) case final swatch?) ...[
                  Opacity(opacity: _reachable(value) ? 1 : 0.4, child: swatch),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _labelFor(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _reachable(value)
                        ? null
                        : TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                            decoration: TextDecoration.lineThrough,
                          ),
                  ),
                ),
                if (value == selected)
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
      onChanged: enabled
          ? (value) {
              if (value == null || value == selected) return;
              onChanged(value);
            }
          : null,
    );
  }
}

/// Whether the seller named this axis as a colour.
bool _isColourAxis(String name) {
  final lower = name.toLowerCase();
  return lower.contains('colo') || name.contains('颜色') || name.contains('色');
}

/// The small indicator beside a colour: the SKU's photo, or a plain dot.
class _Swatch extends StatelessWidget {
  const _Swatch.photo(String this.url, {super.key}) : colour = null;
  const _Swatch.colour(Color this.colour, {super.key}) : url = null;

  final String? url;
  final Color? colour;

  static const double _size = 14;

  @override
  Widget build(BuildContext context) {
    final edge = Theme.of(context).colorScheme.outline;
    final photo = url;

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour,
        // A hairline, so white and pale colours still read as a dot on the
        // white menu rather than as a gap.
        border: Border.all(color: edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: photo == null
          ? null
          : Image(
              image: AppImages.of(
                photo,
                width: _size,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
              fit: BoxFit.cover,
              // A picture that will not load leaves the ring, not a broken
              // image glyph in a 14pt circle.
              errorBuilder: (context, _, _) => const SizedBox.shrink(),
            ),
    );
  }
}

/// A colour for a seller's colour name, when the name says one plainly.
///
/// Matched on ordinary colour words -- English, and the Chinese characters
/// supplier listings use -- inside whatever the seller wrote, so "Wine red",
/// "Polo【black】" and "深蓝色" all find theirs. A name with no such word
/// returns null: the indicator is left out rather than invented.
@visibleForTesting
Color? colourNamed(String name) {
  final lower = name.toLowerCase();
  // Longest and most specific first, so "navy blue" is navy and "wine red"
  // is wine rather than the plain word inside them.
  const words = <(String, Color)>[
    ('navy', Color(0xFF1F2A44)),
    ('wine', Color(0xFF7B1E3A)),
    ('burgundy', Color(0xFF800020)),
    ('khaki', Color(0xFFC3B091)),
    ('beige', Color(0xFFE8DCC4)),
    ('apricot', Color(0xFFFBCEB1)),
    ('coffee', Color(0xFF6F4E37)),
    ('brown', Color(0xFF7B5236)),
    ('silver', Color(0xFFC0C0C0)),
    ('gold', Color(0xFFD4AF37)),
    ('purple', Color(0xFF7E57C2)),
    ('violet', Color(0xFF8F5BD6)),
    ('pink', Color(0xFFF48FB1)),
    ('orange', Color(0xFFFB8C00)),
    ('yellow', Color(0xFFFDD835)),
    ('green', Color(0xFF43A047)),
    ('blue', Color(0xFF1E88E5)),
    ('red', Color(0xFFE53935)),
    ('grey', Color(0xFF9E9E9E)),
    ('gray', Color(0xFF9E9E9E)),
    ('black', Color(0xFF212121)),
    ('white', Color(0xFFFFFFFF)),
    ('藏青', Color(0xFF1F2A44)),
    ('酒红', Color(0xFF7B1E3A)),
    ('卡其', Color(0xFFC3B091)),
    ('米', Color(0xFFE8DCC4)),
    ('咖啡', Color(0xFF6F4E37)),
    ('棕', Color(0xFF7B5236)),
    ('银', Color(0xFFC0C0C0)),
    ('金', Color(0xFFD4AF37)),
    ('紫', Color(0xFF7E57C2)),
    ('粉', Color(0xFFF48FB1)),
    ('橙', Color(0xFFFB8C00)),
    ('黄', Color(0xFFFDD835)),
    ('绿', Color(0xFF43A047)),
    ('蓝', Color(0xFF1E88E5)),
    ('红', Color(0xFFE53935)),
    ('灰', Color(0xFF9E9E9E)),
    ('黑', Color(0xFF212121)),
    ('白', Color(0xFFFFFFFF)),
  ];
  for (final (word, colour) in words) {
    final ascii = word.codeUnitAt(0) < 128;
    final hit = ascii
        ? RegExp('(^|[^a-z])$word([^a-z]|\$)').hasMatch(lower)
        : name.contains(word);
    if (hit) return colour;
  }
  return null;
}

/// The only value on an axis, when there is only one.
///
/// An axis with a single value is not offered as a dropdown -- there is nothing
/// to choose -- but it still has to be filled in to name a SKU.
String? _onlyValueAt(List<ProductVariant> variants, int index) {
  String? found;
  for (final variant in variants) {
    if (index >= variant.axisValues.length) continue;
    final value = variant.axisValues[index];
    if (found == null) {
      found = value;
    } else if (found != value) {
      return null;
    }
  }
  return found;
}

/// A short line under the pickers: what went wrong, and a way to try again.
class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.color,
    required this.text,
    this.onRetry,
  });

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          if (onRetry != null)
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
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../cart/data/cart_store.dart';

/// The Saved items page's "Add to cart" button, with its own animation.
///
/// Used on that page only. On a tap the label fades away and the cart icon
/// travels left to right across the button, toward the cart. When it arrives
/// the add is made, and only once that has succeeded does the button read
/// "Added to Cart". If there is nothing to add -- no price could be found --
/// it runs back and reads "Add to cart" again.
///
/// "Added" is read from the cart rather than remembered here, so an Undo, or
/// the line being removed anywhere else, puts the button back by itself.
class SavedAddToCartButton extends StatefulWidget {
  const SavedAddToCartButton({
    super.key,
    required this.productId,
    required this.enabled,
    required this.prepare,
    required this.commit,
    required this.onOpenCart,
  });

  final String productId;

  /// False while the whole list is being moved.
  final bool enabled;

  /// Finds the price to add at; null means it cannot be added.
  final Future<num?> Function() prepare;

  /// Makes the add. True when the line is now in the cart.
  final bool Function(num price) commit;

  /// Where a tap on "Added to Cart" goes.
  final VoidCallback onOpenCart;

  /// How long the icon takes to cross.
  static const flight = Duration(milliseconds: 650);

  @override
  State<SavedAddToCartButton> createState() => _SavedAddToCartButtonState();
}

class _SavedAddToCartButtonState extends State<SavedAddToCartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: SavedAddToCartButton.flight,
    reverseDuration: const Duration(milliseconds: 280),
  );

  bool _busy = false;

  bool get _inCart => CartStore.instance.contains(widget.productId);

  @override
  void initState() {
    super.initState();
    CartStore.instance.addListener(_cartChanged);
  }

  @override
  void dispose() {
    CartStore.instance.removeListener(_cartChanged);
    _fly.dispose();
    super.dispose();
  }

  void _cartChanged() {
    // Removed from the cart (Undo, or elsewhere): back to "Add to cart".
    if (!_busy && !_inCart && _fly.value != 0) _fly.value = 0;
    if (mounted) setState(() {});
  }

  Future<void> _tap() async {
    if (_busy) return;
    if (_inCart) {
      widget.onOpenCart();
      return;
    }
    setState(() => _busy = true);

    // The animation and the price lookup run side by side; the add waits for
    // both, so nothing is claimed before it is true.
    final results = await Future.wait<Object?>([
      _fly.forward(from: 0).orCancel.catchError((_) {}),
      widget.prepare(),
    ]);
    if (!mounted) return;

    final price = results[1] as num?;
    final added = price != null && widget.commit(price);
    if (!added) {
      await _fly.reverse().orCancel.catchError((_) {});
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _inCart && !_busy;

    return Semantics(
      button: true,
      label: done ? 'Added to Cart' : 'Add to cart',
      excludeSemantics: true,
      child: FilledButton(
        key: ValueKey('saved-add-${widget.productId}'),
        onPressed: widget.enabled ? _tap : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          padding: EdgeInsets.zero,
        ),
        child: SizedBox(
          height: 40,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final ink =
                  DefaultTextStyle.of(context).style.color ?? Colors.white;
              final labelStyle = theme.textTheme.labelLarge?.copyWith(
                color: ink,
              );

              if (done) {
                return Center(
                  child: TweenAnimationBuilder<double>(
                    key: const ValueKey('added'),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    builder: (context, t, child) => Opacity(
                      opacity: t.clamp(0, 1),
                      child: Transform.scale(
                        scale: 0.85 + 0.15 * t,
                        child: child,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 18, color: ink),
                          const SizedBox(width: 8),
                          Text('Added to Cart', style: labelStyle),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return AnimatedBuilder(
                animation: _fly,
                builder: (context, _) {
                  final t = _fly.value;
                  // The label leaves in the first third, sliding the way the
                  // cart is going.
                  final labelOut = Curves.easeIn.transform(
                    (t / 0.35).clamp(0.0, 1.0),
                  );
                  // The icon crosses from where it sits beside the label to
                  // the right-hand end, and fades as it gets there.
                  final travel = Curves.easeInOutCubic.transform(t);
                  const iconSize = 18.0;
                  final startX = (width / 2 - 56).clamp(10.0, width);
                  final endX = width - iconSize - 12;
                  final iconX = startX + (endX - startX) * travel;
                  final iconFade = t < 0.85 ? 1.0 : 1 - (t - 0.85) / 0.15;

                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      if (t == 0)
                        Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_shopping_cart,
                                  size: iconSize,
                                  color: ink,
                                ),
                                const SizedBox(width: 8),
                                Text('Add to cart', style: labelStyle),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        Center(
                          child: Opacity(
                            opacity: 1 - labelOut,
                            child: Transform.translate(
                              offset: Offset(18 * labelOut, 0),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 26),
                                child: Text('Add to cart', style: labelStyle),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: iconX,
                          top: (40 - iconSize) / 2,
                          child: Opacity(
                            opacity: iconFade.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: 1 + 0.2 * (1 - (2 * travel - 1).abs()),
                              child: Icon(
                                Icons.shopping_cart,
                                size: iconSize,
                                color: ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

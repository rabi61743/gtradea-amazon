import 'package:flutter/material.dart';

import 'swipe_hint.dart';
import 'variant_tooltip.dart';

/// One option in a chip row: what it says, and whether it can be picked.
class ChipOption {
  const ChipOption({required this.label, this.available = true, this.tooltip});

  /// What the chip says. Kept short; the long form goes in [tooltip].
  final String label;

  /// Sold out or not made is drawn struck and refuses the tap.
  final bool available;

  /// The seller's full wording, where the chip had to shorten it.
  final String? tooltip;
}

/// A row of options in words, that scrolls when there are more than fit.
///
/// Sizes are short and there are often a dozen of them, so they sit in one
/// line and the line moves rather than wrapping into a block that pushes the
/// price off the screen.
///
/// The last chip is deliberately left half-covered by a fade at the right
/// edge: a row that ends flush with the screen reads as the end of the row,
/// and the options past it are never looked for. The fade goes as the end
/// arrives, so it never sits over the final chip.
class OptionChips extends StatefulWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.hintNoun,
  });

  final List<ChipOption> options;

  /// Negative for nothing chosen yet.
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// What this row holds, for the swipe hint: "sizes", "colours". Null shows
  /// no hint at all.
  final String? hintNoun;

  @override
  State<OptionChips> createState() => _OptionChipsState();
}

class _OptionChipsState extends State<OptionChips> {
  final _controller = ScrollController();

  /// How much of the fade to draw: full while there is more to the right,
  /// gone as the end arrives.
  final _endFade = ValueNotifier<double>(0);

  /// Whether the row overflows, which is the only case worth hinting at.
  bool _overflows = false;

  /// Set the first time the row is moved. The hint has done its job then, and
  /// a standing instruction to do the thing you are already doing is noise.
  bool _used = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(OptionChips old) {
    super.didUpdateWidget(old);
    // A different product, or a colour whose sizes differ: the row may no
    // longer overflow, and a fade left over would point at nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_update)
      ..dispose();
    _endFade.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;

    final overflows = max > 0;
    final used = _used || _controller.offset > 4;
    if (overflows != _overflows || used != _used) {
      setState(() {
        _overflows = overflows;
        _used = used;
      });
    }

    if (max <= 0) {
      _endFade.value = 0;
      return;
    }
    _endFade.value = ((max - _controller.offset) / 24).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final noun = widget.hintNoun;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: Stack(
            children: [
              ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.options.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final option = widget.options[i];
                  final isSelected = i == widget.selectedIndex;
                  final ink = option.available
                      ? (isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface)
                      : theme.colorScheme.onSurfaceVariant;

                  final chip = InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: option.available ? () => widget.onSelected(i) : null,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      constraints: const BoxConstraints(minWidth: 56),
                      decoration: BoxDecoration(
                        // The same border and radius the swatches carry, so the
                        // two forms of this control read as one thing.
                        borderRadius: BorderRadius.circular(10),
                        // A box of its own: without a fill the chip melted
                        // into the grey sheet and read as bare letters.
                        color: isSelected
                            ? Color.alphaBlend(
                                theme.colorScheme.primary.withValues(
                                  alpha: 0.06,
                                ),
                                theme.colorScheme.surface,
                              )
                            : theme.colorScheme.surface,
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ink,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          decoration: option.available
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  );

                  return Semantics(
                    label: option.available
                        ? option.label
                        : '${option.label}, out of stock',
                    selected: isSelected,
                    child: option.tooltip == null
                        ? chip
                        : VariantTooltip(message: option.tooltip!, child: chip),
                  );
                },
              ),
              // "There is more to the right."
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _endFade,
                    builder: (context, amount, _) => Opacity(
                      opacity: amount,
                      child: Container(
                        width: 28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              theme.colorScheme.surface.withValues(alpha: 0),
                              theme.colorScheme.surface,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Only where there is something past the edge, and only until the
        // shopper has moved the row once.
        if (noun != null)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _overflows && !_used
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SwipeHint(noun: noun),
                  )
                : const SizedBox(width: double.infinity),
          ),
      ],
    );
  }
}

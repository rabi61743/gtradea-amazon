import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../data/catalog_content.dart';

/// The category navigator, in the shape the width can carry.
///
/// A horizontal strip on a phone and a vertical list on a wide window, driven
/// by the same state. Both keep the active item scrolled into view, because a
/// highlight nobody can see is not a highlight.
///
/// Animations are short and only on colour and weight. The active item is
/// something the shopper's own scrolling moves, so anything longer reads as
/// lag rather than as polish.
class CategoryNav extends StatefulWidget {
  const CategoryNav({
    super.key,
    required this.departments,
    required this.active,
    required this.onSelected,
    required this.strings,
    required this.vertical,
  });

  final List<Department> departments;
  final int active;
  final ValueChanged<int> onSelected;
  final AppStrings strings;
  final bool vertical;

  @override
  State<CategoryNav> createState() => _CategoryNavState();
}

class _CategoryNavState extends State<CategoryNav> {
  final _controller = ScrollController();
  late final List<GlobalKey> _keys =
      List.generate(widget.departments.length, (_) => GlobalKey());

  @override
  void didUpdateWidget(CategoryNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _revealActive();
  }

  /// Brings the active item into view without yanking the list about.
  void _revealActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keys[widget.active].currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        // Centred, so the items either side stay visible and the shopper can
        // see where they are in the list rather than only what they are on.
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.vertical) {
      return Container(
        width: 208,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          itemCount: widget.departments.length,
          itemBuilder: (context, i) => Padding(
            key: _keys[i],
            padding: const EdgeInsets.only(bottom: 4),
            child: _NavItem(
              department: widget.departments[i],
              label: widget.strings.department(widget.departments[i].label),
              isActive: i == widget.active,
              expanded: true,
              onTap: () => widget.onSelected(i),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 52 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
        child: ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          itemCount: widget.departments.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => Center(
            key: _keys[i],
            child: _NavItem(
              department: widget.departments[i],
              label: widget.strings.department(widget.departments[i].label),
              isActive: i == widget.active,
              expanded: false,
              onTap: () => widget.onSelected(i),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.department,
    required this.label,
    required this.isActive,
    required this.expanded,
    required this.onTap,
  });

  final Department department;
  final String label;
  final bool isActive;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = department.tint;

    return Semantics(
      selected: isActive,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 12 : 12,
            vertical: expanded ? 10 : 7,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: isActive ? tint.withValues(alpha: 0.13) : Colors.transparent,
            border: Border.all(
              color: isActive ? tint.withValues(alpha: 0.55) : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(
                department.icon,
                size: 17,
                color: isActive ? tint : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              // Weight and colour animate; size does not. A label that grows
              // reflows everything beside it on every scroll tick.
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  style: (theme.textTheme.labelLarge ?? const TextStyle())
                      .copyWith(
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                    color: isActive
                        ? tint
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

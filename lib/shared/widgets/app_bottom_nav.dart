import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/colors.dart';
import '../../features/wishlist/presentation/wishlist_flight.dart';
import '../motion/motion_curves.dart';

/// Five-destination bottom bar: Home, Saved, Account, Cart, Categories.
///
/// New for You held the second slot until it moved to the department strip on
/// the home page, immediately after Men. One destination reached from one
/// place: carrying it in both was a duplicate, and the bar is the copy that
/// went. The screen itself is untouched and the strip still opens it.
///
/// Back to five, which is Material's own ceiling for this control -- the sixth
/// slot was one past it, and the labels had begun wrapping to two lines on an
/// ordinary phone.
///
/// The cart and saved counts ride as badges, each shown only once there is
/// something to count.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.cartCount = 0,
    this.savedCount = 0,
    this.isSignedIn = false,
    this.strings,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final int cartCount;

  /// Saved products, shown so the tab is worth returning to.
  final int savedCount;

  /// Drives the account destination's wording. Passed in rather than read from
  /// the store here so this stays a presentational widget.
  final bool isSignedIn;

  /// Labels for the destinations. Defaults to English so a widget test or a
  /// preview can build the bar without wiring the language store.
  final AppStrings? strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = strings ?? AppStrings.en;

    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onSelected,
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: t.home,
        ),
        NavigationDestination(
          icon: _SavedTabIcon(count: savedCount, filled: false),
          selectedIcon: _SavedTabIcon(count: savedCount, filled: true),
          label: t.saved,
        ),
        // "Sign in" rather than the full "Sign In / Sign Up": a five-slot bar
        // gives each label about 78dp, and the longer string truncates on a
        // normal phone -- worse still at large text sizes. The full wording is
        // the heading of the screen this opens, where there is room for it.
        NavigationDestination(
          icon: Icon(
            isSignedIn ? Icons.account_circle_outlined : Icons.person_outline,
          ),
          selectedIcon: Icon(isSignedIn ? Icons.account_circle : Icons.person),
          label: isSignedIn ? t.account : t.signIn,
        ),
        NavigationDestination(
          icon: Badge.count(
            count: cartCount,
            // Hidden at zero, like the saved badge. A badge reading 0 is a
            // notification about nothing.
            isLabelVisible: cartCount > 0,
            child: const Icon(Icons.shopping_cart_outlined),
          ),
          selectedIcon: Badge.count(
            count: cartCount,
            // Hidden at zero, like the saved badge. A badge reading 0 is a
            // notification about nothing.
            isLabelVisible: cartCount > 0,
            child: const Icon(Icons.shopping_cart),
          ),
          label: t.cart,
        ),
        NavigationDestination(
          icon: const Icon(Icons.grid_view_outlined),
          selectedIcon: const Icon(Icons.grid_view),
          label: t.categories,
        ),
      ],
    );
  }
}

/// The Saved destination's heart, and the count that rides on it.
///
/// This is where hearts thrown from a product card land, so it is also what
/// reacts to one: a squash, a pop, a fill, and a soft pink glow that fades
/// behind it. The number itself is untouched -- it is the same
/// [Badge.count] on the same `savedCount` as before, and the only new thing
/// about it is that it scales in when it changes.
class _SavedTabIcon extends StatefulWidget {
  const _SavedTabIcon({required this.count, required this.filled});

  final int count;

  /// The selected variant of the destination. Only the unselected one offers
  /// itself as the flight's destination: both are in the tree at the same
  /// place, and one registration is enough.
  final bool filled;

  @override
  State<_SavedTabIcon> createState() => _SavedTabIconState();
}

class _SavedTabIconState extends State<_SavedTabIcon>
    with TickerProviderStateMixin {
  final GlobalKey _anchor = GlobalKey();

  late final AnimationController _land = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// The badge's own arrival, kept apart from the landing so a count that
  /// changes for any other reason -- a sync, another screen -- still animates.
  late final AnimationController _badge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.filled) WishlistFlight.bindTarget(_anchor, _react);
  }

  @override
  void didUpdateWidget(_SavedTabIcon old) {
    super.didUpdateWidget(old);
    // The real count, from the real store: when it grows, the badge arrives.
    if (widget.count > old.count && widget.count > 0) {
      _badge.forward(from: 0);
    }
  }

  void _react() {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) return;
    _land.forward(from: 0);
  }

  @override
  void dispose() {
    if (!widget.filled) WishlistFlight.unbindTarget(_anchor);
    _land.dispose();
    _badge.dispose();
    super.dispose();
  }

  /// Down, past one, then settling back to it.
  double get _scale {
    final t = _land.value;
    if (t == 0 || _land.isCompleted) return 1;
    if (t <= 0.15) return 1 - 0.18 * power2Out.transform(t / 0.15);
    if (t <= 0.45) return 0.82 + 0.36 * backOut3.transform((t - 0.15) / 0.3);
    return 1 + 0.18 * (1 - elasticOutSoft.transform((t - 0.45) / 0.55));
  }

  /// A soft pink bloom behind the heart, brightest as it lands and gone by
  /// the time the heart has settled.
  double get _glow {
    final t = _land.value;
    if (t == 0 || _land.isCompleted) return 0;
    if (t <= 0.15) return t / 0.15;
    return 1 - power1Out.transform((t - 0.15) / 0.85);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_land, _badge]),
      builder: (context, _) {
        final reacting = _land.isAnimating;
        final filled = widget.filled || reacting;

        return Transform.scale(
          scale: _scale,
          child: Badge(
            isLabelVisible: widget.count > 0,
            // The same number the badge always carried, straight from the
            // store's count -- it only arrives with a pop now.
            label: Transform.scale(
              scale: backOut3.transform(_badge.value),
              child: Text(widget.count > 999 ? '999+' : '${widget.count}'),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (_glow > 0)
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(
                        alpha: 0.28 * _glow.clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                Icon(
                  key: _anchor,
                  filled ? Icons.favorite : Icons.favorite_border,
                  color: reacting ? AppColors.accent : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

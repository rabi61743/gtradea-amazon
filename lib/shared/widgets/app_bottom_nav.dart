import 'package:flutter/material.dart';

/// Five-destination bottom bar: Home, Saved, Account, Cart, Menu.
///
/// The cart carries a live count as a badge; it is shown even at zero so the
/// bar does not reflow the first time something is added.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.cartCount = 0,
    this.savedCount = 0,
    this.isSignedIn = false,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final int cartCount;

  /// Saved products, shown so the tab is worth returning to.
  final int savedCount;

  /// Drives the account destination's wording. Passed in rather than read from
  /// the store here so this stays a presentational widget.
  final bool isSignedIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onSelected,
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Badge.count(
            count: savedCount,
            isLabelVisible: savedCount > 0,
            child: const Icon(Icons.favorite_border),
          ),
          selectedIcon: Badge.count(
            count: savedCount,
            isLabelVisible: savedCount > 0,
            child: const Icon(Icons.favorite),
          ),
          label: 'Saved',
        ),
        // "Sign in" rather than the full "Sign In / Sign Up": a five-slot bar
        // gives each label about 78dp, and the longer string truncates on a
        // normal phone -- worse still at large text sizes. The full wording is
        // the heading of the screen this opens, where there is room for it.
        NavigationDestination(
          icon: Icon(
            isSignedIn ? Icons.account_circle_outlined : Icons.person_outline,
          ),
          selectedIcon: Icon(
            isSignedIn ? Icons.account_circle : Icons.person,
          ),
          label: isSignedIn ? 'Account' : 'Sign in',
        ),
        NavigationDestination(
          icon: Badge.count(
            count: cartCount,
            isLabelVisible: true,
            child: const Icon(Icons.shopping_cart_outlined),
          ),
          selectedIcon: Badge.count(
            count: cartCount,
            isLabelVisible: true,
            child: const Icon(Icons.shopping_cart),
          ),
          label: 'Cart',
        ),
        const NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view),
          label: 'Browse',
        ),
      ],
    );
  }
}

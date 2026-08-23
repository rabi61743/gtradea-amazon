import 'package:flutter/material.dart';

/// Four-destination bottom bar: Home, Account, Cart, Menu.
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
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final int cartCount;

  /// Saved products, shown so the tab is worth returning to.
  final int savedCount;

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
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Account',
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
          icon: Icon(Icons.menu),
          label: 'Menu',
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../../core/l10n/app_strings.dart';
import '../../address/data/address_store.dart';
import '../../address/presentation/address_list_screen.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../notifications/presentation/notification_settings_screen.dart';
import '../../orders/data/order_store.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../catalog/data/product.dart';
import '../../product/presentation/product_detail_screen.dart';
import '../../settings/presentation/language_screen.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../../wishlist/presentation/wishlist_screen.dart';
import '../data/recently_viewed_store.dart';

/// The account tab: who you are, what you were looking at, and your settings.
///
/// Structured as labelled groups of cards rather than one long flat list. The
/// groups are what make a settings page scannable -- a shopper looking for
/// notifications should find it by reading four headings, not sixteen rows.
///
/// Deliberately carries nothing about selling. This is the customer's page.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  @override
  void initState() {
    super.initState();
    AuthStore.instance.load();
    WishlistStore.instance.load();
    CartStore.instance.load();
    RecentlyViewedStore.instance.load();
    OrderStore.instance.load();
    LanguageStore.instance.load();
    AddressStore.instance.load();
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openAuth(AuthMode mode) => _push(AuthScreen(initialMode: mode));

  void _todo(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label is not built yet')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Every section here reflects some store, and all of them have to be
      // right the moment the shopper arrives from anywhere else.
      listenable: Listenable.merge([
        AuthStore.instance,
        WishlistStore.instance,
        CartStore.instance,
        RecentlyViewedStore.instance,
        OrderStore.instance,
        LanguageStore.instance,
        AddressStore.instance,
      ]),
      builder: (context, _) {
        final account = AuthStore.instance.account;
        final viewed = RecentlyViewedStore.instance.items;

        return Scaffold(
          appBar: AppBar(
            title: Text(account == null ? 'Sign In / Sign Up' : 'Account'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              if (account == null)
                _GuestCard(
                  onSignIn: () => _openAuth(AuthMode.signIn),
                  onSignUp: () => _openAuth(AuthMode.signUp),
                )
              else
                _ProfileCard(account: account),

              const SizedBox(height: 18),

              // Four things a shopper actually came here to reach, as targets
              // rather than list rows. Two of them carry live counts, which is
              // the whole reason to surface them at this size.
              _QuickActions(
                savedCount: WishlistStore.instance.count,
                cartCount: CartStore.instance.count,
                // A guest has no orders to show, so the tile asks them to sign
                // in rather than promising a page that could never have
                // anything in it for them.
                onOrders: account == null
                    ? () => _openAuth(AuthMode.signIn)
                    : () => _push(const OrdersScreen()),
                onSaved: () => _push(const WishlistScreen()),
                onCart: () => _push(const CartScreen()),
                onHelp: () => _todo('Help centre'),
              ),

              if (viewed.isNotEmpty) ...[
                const SizedBox(height: 22),
                _GroupLabel(
                  'Recently viewed',
                  action: 'Clear',
                  onAction: RecentlyViewedStore.instance.clear,
                ),
                _RecentlyViewedRail(
                  items: viewed,
                  onTap: (product) => _push(ProductDetailScreen(
                    product: productStub(
                      numIid: product.id,
                      title: product.title,
                      imageUrl: product.imageUrl,
                      displayPrice: product.price,
                    ),
                  )),
                ),
              ],

              const SizedBox(height: 22),
              const _GroupLabel('Account settings'),
              _RowGroup(
                rows: [
                  _RowSpec(
                    icon: Icons.translate,
                    label: LanguageStore.instance.strings.language,
                    trailing: LanguageStore.instance.language.nativeName,
                    onTap: () => _push(const LanguageScreen()),
                  ),
                  _RowSpec(
                    icon: Icons.notifications_none,
                    label: 'Notifications',
                    onTap: () =>
                        _push(const NotificationSettingsScreen()),
                  ),
                  _RowSpec(
                    icon: Icons.location_on_outlined,
                    label: 'Delivery addresses',
                    trailing: AddressStore.instance.count == 0
                        ? null
                        : '${AddressStore.instance.count}',
                    onTap: () => _push(const AddressListScreen()),
                  ),
                  _RowSpec(
                    icon: Icons.payments_outlined,
                    label: 'Payment methods',
                    onTap: () => _todo('Payment methods'),
                  ),
                ],
              ),

              const SizedBox(height: 22),
              const _GroupLabel('Help and information'),
              _RowGroup(
                rows: [
                  _RowSpec(
                    icon: Icons.support_agent,
                    label: 'Help centre',
                    onTap: () => _todo('Help centre'),
                  ),
                  _RowSpec(
                    icon: Icons.description_outlined,
                    label: 'Terms and policies',
                    onTap: () => _todo('Terms and policies'),
                  ),
                  _RowSpec(
                    icon: Icons.info_outline,
                    label: 'About GtradeA',
                    onTap: () => _todo('About'),
                  ),
                ],
              ),

              if (account != null) ...[
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: _confirmSignOut,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Signing out is confirmed rather than undoable. Unlike removing one saved
  /// product, getting back in costs the shopper a password.
  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to see your orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) AuthStore.instance.signOut();
  }
}

/// The guest state: what an account buys you, then both ways in.
class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.onSignIn, required this.onSignUp});

  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          // A wash of the brand colour rather than a plain card: this is the
          // one block on the page asking for something, so it should read as
          // an invitation instead of another settings row.
          color: theme.colorScheme.primary.withValues(alpha: 0.07),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primary,
                  child: Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome to GtradeA',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Track orders, save addresses and keep your list '
                        'across devices.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Wrap, not Row: at large text sizes two buttons side by side stop
            // fitting, and this is the one screen where a clipped control
            // costs the shopper the account.
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: onSignIn,
                  style: FilledButton.styleFrom(minimumSize: const Size(132, 44)),
                  child: const Text('Sign In'),
                ),
                OutlinedButton(
                  onPressed: onSignUp,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(132, 44),
                  ),
                  child: const Text('Sign Up'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The signed-in state: who you are, at a glance.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = account.displayName;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          color: theme.colorScheme.primary.withValues(alpha: 0.07),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                initial,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four destinations as equal-weight tiles, two of them badged.
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.savedCount,
    required this.cartCount,
    required this.onOrders,
    required this.onSaved,
    required this.onCart,
    required this.onHelp,
  });

  final int savedCount;
  final int cartCount;
  final VoidCallback onOrders;
  final VoidCallback onSaved;
  final VoidCallback onCart;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _QuickAction(
            icon: Icons.receipt_long_outlined,
            label: 'Orders',
            onTap: onOrders,
          ),
          _QuickAction(
            icon: Icons.favorite_border,
            label: 'Saved',
            count: savedCount,
            onTap: onSaved,
          ),
          _QuickAction(
            icon: Icons.shopping_cart_outlined,
            label: 'Cart',
            count: cartCount,
            onTap: onCart,
          ),
          _QuickAction(
            icon: Icons.support_agent,
            label: 'Support',
            onTap: onHelp,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Badge.count(
                count: count,
                isLabelVisible: count > 0,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  ),
                  child: Icon(icon, size: 22, color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section heading, with an optional action on the right.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {this.action, this.onAction});

  final String label;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Outside the card it labels, so the card stays a clean block and the
      // hierarchy is readable without a divider.
      padding: EdgeInsets.fromLTRB(20, 0, action == null ? 20 : 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class _RowSpec {
  const _RowSpec({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
}

/// Rows sharing one bordered card, hairline-separated.
class _RowGroup extends StatelessWidget {
  const _RowGroup({required this.rows});

  final List<_RowSpec> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              _SettingsRow(
                spec: rows[i],
                // No rule under the last row: the card border already closes
                // the group.
                showDivider: i != rows.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.spec, required this.showDivider});

  final _RowSpec spec;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: spec.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    ),
                    child: Icon(
                      spec.icon,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(spec.label, style: theme.textTheme.bodyMedium),
                  ),
                  if (spec.trailing != null) ...[
                    Text(
                      spec.trailing!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                // Indented to clear the icon, so the rows read as one group
                // rather than four separate blocks.
                indent: 46,
                color: theme.colorScheme.outlineVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// Products the shopper opened, as a horizontal rail of small cards.
class _RecentlyViewedRail extends StatelessWidget {
  const _RecentlyViewedRail({required this.items, required this.onTap});

  final List<SavedProduct> items;
  final ValueChanged<SavedProduct> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      // Grows with the device text scale, like the home rails: a fixed height
      // clips the price line on a phone set to larger text.
      height: 168 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          return SizedBox(
            width: 104,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              onTap: () => onTap(item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    child: SizedBox(
                      width: 104,
                      height: 104,
                      child: ArtworkPanel(
                        icon: Icons.checkroom,
                        tint: theme.colorScheme.primary,
                        imageUrl: item.imageUrl,
                        iconScale: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    formatRupees(item.price),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

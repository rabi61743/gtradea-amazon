import 'package:cached_network_image/cached_network_image.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/audio/sound_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/state_toggle.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../../shared/widgets/brand_wordmark.dart';
import '../../../core/l10n/app_strings.dart';
import '../../address/data/address_store.dart';
import '../../address/presentation/address_list_screen.dart';
import '../../checkout/data/saved_payment_store.dart';
import '../../checkout/presentation/payment_methods_screen.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../help/presentation/contact_screen.dart';
import '../../help/presentation/help_center_screen.dart';
import '../../legal/presentation/legal_page_screen.dart';
import '../../legal/presentation/terms_policies_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../notifications/presentation/notification_settings_screen.dart';
import '../../orders/data/order_store.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../catalog/data/product.dart';
import '../../product/presentation/product_detail_screen.dart';
import '../../profile/data/profile_store.dart';
import '../../profile/presentation/profile_settings_screen.dart';
import '../../security/presentation/login_activity_screen.dart';
import '../../quotes/presentation/quote_requests_screen.dart';
import 'product_history_screen.dart';
import '../../settings/presentation/language_screen.dart';
import '../../settings/presentation/theme_screen.dart';
import '../../../core/theme/theme_settings.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../../wishlist/presentation/wishlist_screen.dart';
import '../data/recently_viewed_store.dart';
import 'accounts_sheet.dart';

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
    // Only does anything for a signed-in shopper, and only once -- it is what
    // puts their photograph and their saved name on the header card.
    ProfileStore.instance.load();
    WishlistStore.instance.load();
    CartStore.instance.load();
    RecentlyViewedStore.instance.load();
    OrderStore.instance.load();
    LanguageStore.instance.load();
    AddressStore.instance.load();
    SavedPaymentStore.instance.load();
    SoundSettings.instance.load();
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openAuth(AuthMode mode) => _push(AuthScreen(initialMode: mode));

  /// The Support button beside Cart. Contact, not the Help Center: it is the
  /// page with the address, the number and the way to track an order, which is
  /// what somebody pressing "Support" is after.
  void _openContact() => _push(const ContactScreen());

  /// The row was already here, wired to the not-built-yet placeholder. This
  /// is what it was waiting for.
  void _openHelpCenter() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const HelpCenterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Every section here reflects some store, and all of them have to be
      // right the moment the shopper arrives from anywhere else.
      listenable: Listenable.merge([
        AuthStore.instance,
        ProfileStore.instance,
        WishlistStore.instance,
        CartStore.instance,
        RecentlyViewedStore.instance,
        OrderStore.instance,
        LanguageStore.instance,
        AddressStore.instance,
        SavedPaymentStore.instance,
        SoundSettings.instance,
        ThemeSettings.instance,
      ]),
      builder: (context, _) {
        final account = AuthStore.instance.account;
        final viewed = RecentlyViewedStore.instance.items;

        // Account settings and Help and information, written once and placed
        // either inside the one card or in the second card below Recently
        // viewed -- the same widgets either way.
        final settingsAndHelp = <Widget>[
          const SizedBox(height: 22),
          const _GroupLabel('Account settings'),
          _RowGroup(
            rows: [
              // Only for a signed-in shopper. Offering it to a guest would
              // open a page whose every field is about an account they do
              // not have.
              if (account != null)
                _RowSpec(
                  icon: Icons.manage_accounts_outlined,
                  label: 'Profile settings',
                  onTap: () => _push(const ProfileSettingsScreen()),
                ),
              if (account != null)
                _RowSpec(
                  icon: Icons.shield_outlined,
                  label: 'Login activity',
                  onTap: () => _push(const LoginActivityScreen()),
                ),
              _RowSpec(
                icon: Icons.translate,
                label: LanguageStore.instance.strings.language,
                trailing: LanguageStore.instance.language.nativeName,
                onTap: () => _push(const LanguageScreen()),
              ),
              _RowSpec(
                icon: Icons.contrast,
                label: 'Theme',
                trailing: ThemeScreen.labelFor(ThemeSettings.instance.mode),
                onTap: () => _push(const ThemeScreen()),
              ),
              _RowSpec(
                icon: Icons.notifications_none,
                label: 'Notifications',
                onTap: () => _push(const NotificationSettingsScreen()),
              ),
              // In the list rather than behind a page of its own: it is
              // one switch, and a page containing one switch is a tap
              // spent on nothing.
              _RowSpec(
                icon: SoundSettings.instance.enabled
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
                label: 'Sound',
                // The word beside the switch is the toggle's own now --
                // see StateToggle, the same control the notification
                // groups use. Kept here as well it would print "On"
                // twice on one row.
                toggle: SoundSettings.instance.enabled,
                onToggle: SoundSettings.instance.setEnabled,
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
                icon: Icons.history,
                label: 'Product history',
                onTap: () => _push(const ProductHistoryScreen()),
              ),
              _RowSpec(
                icon: Icons.request_quote_outlined,
                label: 'My quote requests',
                onTap: () => _push(const QuoteRequestsScreen()),
              ),
              _RowSpec(
                icon: Icons.payments_outlined,
                label: 'Payment methods',
                // The count, like the address row above it, so the page
                // says what is there without being opened.
                trailing: SavedPaymentStore.instance.count == 0
                    ? null
                    : '${SavedPaymentStore.instance.count}',
                onTap: () => _push(const PaymentMethodsScreen()),
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
                onTap: _openHelpCenter,
              ),
              _RowSpec(
                icon: Icons.description_outlined,
                label: 'Terms and policies',
                onTap: () => _push(const TermsPoliciesScreen()),
              ),
              _RowSpec(
                icon: Icons.info_outline,
                label: 'About ${AppBrand.name}',
                // The shop's own About page, by the slug it publishes it
                // under, rather than a copy pasted into the app.
                onTap: () => _push(
                  const LegalPageScreen(
                    slug: 'about',
                    title: 'About ${AppBrand.name}',
                  ),
                ),
              ),
            ],
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(account == null ? 'Sign In / Sign Up' : 'Account'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              // The account's own items in one card, each exactly as it was.
              // Recently viewed stays outside it; Sign out stays below.
              _AccountCard(
                children: [
                  if (account == null)
                    // Google and Apple are offered on the sign-in and create
                    // account pages, which both buttons here open -- not repeated
                    // on this card.
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
                    onHelp: _openContact,
                  ),

                  // Recently viewed sits between the shortcuts and the
                  // settings, where it always did. It stays outside the card:
                  // with nothing viewed there is nothing between them and the
                  // card is one piece; with something viewed the card splits
                  // around the rail.
                  if (viewed.isEmpty) ...settingsAndHelp,
                ],
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
                  onTap: (product) => _push(
                    ProductDetailScreen(
                      product: productStub(
                        numIid: product.id,
                        title: product.title,
                        imageUrl: product.imageUrl,
                        displayPrice: product.price,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _AccountCard(
                  // Without its leading gap: the card's own top padding and
                  // the gap above it already separate it from the rail.
                  children: settingsAndHelp.skip(1).toList(),
                ),
              ],

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
                        color: Theme.of(context).colorScheme.error
                            .withValues(alpha: 0.4),
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
    final auth = AuthStore.instance;
    final current = auth.account;
    // Another account signed in here is where the app goes next, and the
    // dialog says so rather than surprising anyone with someone else's cart.
    final next = auth.savedAccounts
        .where((saved) => saved.id != current?.id)
        .map((saved) => saved.account)
        .firstOrNull;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          next == null
              ? 'You will need to sign in again to see your orders.'
              : 'You will be signed out of ${current?.email}. '
                    '${next.email} is also signed in on this device, so you '
                    'will switch to it.',
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

    if (!(confirmed ?? false) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await auth.signOut();
    final now = result.switchedTo;
    final note = now != null
        ? 'Signed out. Now using ${now.email}.'
        : result.revoked
        ? null
        : 'Signed out on this device. The server could not be reached, so '
              'the session will expire on its own.';
    if (note != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(note)));
    }
  }
}

/// The guest state: what an account buys you, then both ways in.
/// The lift on this page's four cards, and nowhere else.
///
/// Account, Account settings, Help and information and Recently viewed carry
/// it; the quick-action tiles, the rows inside a card and every button stay
/// flat, which is what keeps the shadow meaning "this is a block" rather than
/// becoming the page's default texture.
/// The cards run edge to edge.
///
/// No side margin: each card is the full width of the page it is on, and only
/// its own padding keeps the words off the glass. The corners go with the
/// margin -- a rounded corner hard against the screen edge reads as a card
/// that failed to reach it -- so these are square-cornered bands closed top
/// and bottom by a hairline.
const BorderRadius _cardShape = BorderRadius.zero;

const List<BoxShadow> _cardLift = [
  BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 2)),
];

/// The brand wash both header cards are drawn in, laid over white.
///
/// It used to be the brand colour at 7% with nothing under it, so it took on
/// the grey of the page: a dull blue-grey panel that the secondary text and
/// the outlined button's pale edge all but disappeared into. Laid over white
/// it is the same wash, a clear step lighter, and everything on it reads.
Color _cardWash(ThemeData theme) => Color.alphaBlend(
  theme.colorScheme.primary.withValues(alpha: 0.06),
  theme.colorScheme.surface,
);

/// Supporting text on the wash: the body ink, softened a little, rather than
/// the secondary grey, which measured too faint against the tint.
Color _cardSubtext(ThemeData theme) =>
    theme.colorScheme.onSurface.withValues(alpha: 0.8);

/// One card around the account's items.
///
/// It only wraps: every item inside keeps its own layout, spacing and
/// decoration, and no horizontal padding is added, so nothing inside moves
/// sideways or changes width. The surface, edge and lift are the page's own
/// card style ([_cardShape], [_cardLift]), so this reads as the same kind of
/// card as the blocks it holds.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: _cardShape,
        border: Border.symmetric(
          horizontal: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        boxShadow: _cardLift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.onSignIn, required this.onSignUp});

  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: _cardShape,
          // A wash of the brand colour rather than a plain card: this is the
          // one block on the page asking for something, so it should read as
          // an invitation instead of another settings row.
          color: _cardWash(theme),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
          boxShadow: _cardLift,
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
                        'Welcome to ${AppBrand.name}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Track orders, save addresses and keep your list '
                        'across devices.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _cardSubtext(theme),
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
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(132, 44),
                  ),
                  child: const Text('Sign In'),
                ),
                OutlinedButton(
                  onPressed: onSignUp,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(132, 44),
                    // The brand blue for the edge and the words: the theme's
                    // hairline edge was lost against the tinted card, and the
                    // button read as a faint box beside the filled one.
                    foregroundColor: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surface,
                    side: BorderSide(color: theme.colorScheme.primary),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
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
    // The profile row when it has arrived, the session's copy until then. The
    // settings page writes the row, so this is what makes a saved name and
    // photograph show up here the moment they are saved.
    final name = ProfileStore.instance.displayName ?? account.displayName;
    final photo = ProfileStore.instance.avatarUrl;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: _cardShape,
          color: _cardWash(theme),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
          boxShadow: _cardLift,
        ),
        child: Row(
          children: [
            _AccountAvatar(url: photo, initial: initial),
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
                      color: _cardSubtext(theme),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Beside the account it changes: whose account this is, and the
            // way to another one, in the same glance.
            OutlinedButton.icon(
              onPressed: () => showAccountsSheet(context),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Switch'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surface,
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The header photograph, or the initial when there is none.
///
/// Falls back to the initial on a failed load as well as on a missing URL: an
/// avatar that 404s must not leave a broken-image glyph where a face was.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.url, required this.initial});

  final String? url;
  final String initial;

  static const _radius = 26.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = CircleAvatar(
      radius: _radius,
      backgroundColor: theme.colorScheme.primary,
      child: Text(
        initial,
        style: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final address = url;
    if (address == null || address.isEmpty) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: address,
        width: _radius * 2,
        height: _radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
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
    this.onTap,
    this.trailing,
    this.toggle,
    this.onToggle,
  }) : assert(
         onTap != null || onToggle != null,
         'a row either opens something or switches something',
       );

  final IconData icon;
  final String label;

  /// What opening the row does. Null on a row that only carries a switch.
  final VoidCallback? onTap;

  final String? trailing;

  /// The switch state, when this row is a setting rather than a link.
  final bool? toggle;
  final ValueChanged<bool>? onToggle;
}

/// Rows sharing one bordered card, hairline-separated.
class _RowGroup extends StatelessWidget {
  const _RowGroup({required this.rows});

  final List<_RowSpec> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // The card the rows share, lifted off the page and run to both
          // edges of it.
          color: theme.colorScheme.surface,
          borderRadius: _cardShape,
          border: Border.symmetric(
            horizontal: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          boxShadow: _cardLift,
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

    final toggle = spec.toggle;
    final onToggle = spec.onToggle;

    return InkWell(
      // The whole row flips the switch, not only the switch itself: a 34pt
      // target at the end of a row is the hardest thing on this page to hit.
      onTap: onToggle != null && toggle != null
          ? () => onToggle(!toggle)
          : spec.onTap,
      child: Padding(
        // The page margin, since the card around these rows no longer holds
        // one of its own.
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  if (toggle != null && onToggle != null)
                    // Excluded from semantics above and labelled here, so a
                    // screen reader announces one control -- "Sound, on" --
                    // rather than a row and a switch it has to relate.
                    Semantics(
                      label: spec.label,
                      toggled: toggle,
                      child: ExcludeSemantics(
                        // The notification screen's toggle, shared rather than
                        // approximated: same thumb icon, same colours, same
                        // word beside it, so one kind of decision has one
                        // control across the app.
                        child: StateToggle(
                          enabled: toggle,
                          onChanged: onToggle,
                        ),
                      ),
                    )
                  else
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
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: _cardShape,
          border: Border.symmetric(
            horizontal: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          boxShadow: _cardLift,
        ),
        // So a thumbnail cannot paint over the rounded corner as it scrolls
        // past the edge.
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          // Grows with the device text scale, like the home rails: a fixed
          // height clips the price line on a phone set to larger text.
          height:
              168 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // The card runs to the screen edges, so the rail carries the page
            // margin itself and the first thumbnail lines up with the words
            // above it.
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
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusControl,
                        ),
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
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../../wishlist/presentation/wishlist_screen.dart';

/// The account tab, in both of its states.
///
/// One screen rather than two routes: signing in from here should leave the
/// customer where they were, with the page simply becoming their account. The
/// [ListenableBuilder] on [AuthStore] is what makes that happen -- the moment
/// the store changes, this rebuilds, so there is nothing to navigate back to.
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
  }

  void _openAuth(AuthMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthScreen(initialMode: mode)),
    );
  }

  void _openSaved() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WishlistScreen()),
    );
  }

  void _todo(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label is not built yet')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        final account = AuthStore.instance.account;

        return Scaffold(
          appBar: AppBar(
            title: Text(account == null ? 'Sign In / Sign Up' : 'Account'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (account == null)
                _SignedOutHeader(
                  onSignIn: () => _openAuth(AuthMode.signIn),
                  onSignUp: () => _openAuth(AuthMode.signUp),
                )
              else
                _SignedInHeader(account: account),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Orders and addresses need an identity to hang off, so they are
              // only offered once there is one. Saved and Help work either way
              // and stay visible -- putting the whole page behind a sign-in
              // wall would make the tab useless to a browsing customer.
              if (account != null) ...[
                _AccountRow(
                  icon: Icons.receipt_long_outlined,
                  label: 'Your orders',
                  onTap: () => _todo('Orders'),
                ),
                _AccountRow(
                  icon: Icons.location_on_outlined,
                  label: 'Addresses',
                  onTap: () => _todo('Addresses'),
                ),
              ],
              ListenableBuilder(
                listenable: WishlistStore.instance,
                builder: (context, _) {
                  final count = WishlistStore.instance.count;
                  return _AccountRow(
                    icon: Icons.favorite_border,
                    label: 'Saved products',
                    trailing: count == 0 ? null : '$count',
                    onTap: _openSaved,
                  );
                },
              ),
              _AccountRow(
                icon: Icons.help_outline,
                label: 'Help and support',
                onTap: () => _todo('Help'),
              ),

              if (account != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                _AccountRow(
                  icon: Icons.logout,
                  label: 'Sign out',
                  destructive: true,
                  onTap: _confirmSignOut,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Signing out is confirmed rather than undoable. Unlike removing one saved
  /// product, getting back in costs the customer a password.
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

    if (confirmed ?? false) {
      AuthStore.instance.signOut();
    }
  }
}

/// The guest state: what an account is for, then both ways in.
class _SignedOutHeader extends StatelessWidget {
  const _SignedOutHeader({required this.onSignIn, required this.onSignUp});

  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Not a second "Sign In / Sign Up": the app bar already says that,
          // and so do the two buttons below. Repeating it three times on one
          // screen is noise.
          Text(
            'Welcome to GtradeA',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Track your orders, save addresses and keep your list across '
            'devices.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          // Wrap, not Row: at large text sizes two buttons side by side stop
          // fitting, and this screen is the one place a customer cannot afford
          // a clipped control.
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: onSignIn,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(140, 46),
                ),
                child: const Text('Sign In'),
              ),
              OutlinedButton(
                onPressed: onSignUp,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(140, 46),
                ),
                child: const Text('Sign Up'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The signed-in state: who you are, at a glance.
class _SignedInHeader extends StatelessWidget {
  const _SignedInHeader({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = account.displayName;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              initial,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, $name',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  account.email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = destructive ? theme.colorScheme.error : null;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(color: color),
      ),
      trailing: destructive
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailing != null)
                  Text(
                    trailing!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
      onTap: onTap,
    );
  }
}

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../profile/data/profile_store.dart';
import '../../profile/presentation/profile_settings_screen.dart';
import '../../security/presentation/login_activity_screen.dart';
import '../data/account_data_purge.dart';

/// Opens the list of accounts signed in on this device.
Future<void> showAccountsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const AccountsSheet(),
  );
}

/// Every account on this device: which one is active, and how to switch,
/// add, manage or remove one.
///
/// Nothing here is a second sign-in system. Adding opens the app's own
/// sign-in page; switching makes a saved session active once the server has
/// accepted it; removing ends that session on the server and forgets it here.
/// The only things shown about an account are its name, photograph and
/// address -- never a token, never anything that would let the page act as it.
class AccountsSheet extends StatefulWidget {
  const AccountsSheet({super.key});

  @override
  State<AccountsSheet> createState() => _AccountsSheetState();
}

class _AccountsSheetState extends State<AccountsSheet> {
  /// The account a switch or removal is running for, so only its row spins.
  String? _busyId;

  /// Why the last action did not happen, said inside the sheet rather than
  /// behind it.
  String? _error;

  /// Set when the failed switch was to an account whose session has ended,
  /// so the error can offer the way back in.
  String? _expiredEmail;

  bool _listed = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      await AuthStore.instance.refreshSavedAccounts();
      if (mounted) setState(() => _listed = true);
    }());
  }

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _switch(SavedAccount saved) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = saved.id;
      _error = null;
      _expiredEmail = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      await AuthStore.instance.switchAccount(saved.id);
      navigator.pop();
      messenger?.showSnackBar(
        SnackBar(content: Text('Switched to ${saved.account.email}')),
      );
    } on SavedSessionExpired catch (e) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _expiredEmail = e.email;
        _error =
            'The session for ${e.email} has ended, so it was removed from '
            'this device. Sign in to add it again.';
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      final current = AuthStore.instance.account?.email;
      setState(() {
        _busyId = null;
        _error = e.isNetwork
            ? 'Could not reach the server. '
                  '${current == null ? '' : 'You are still using $current.'}'
            : e.message;
      });
    }
  }

  Future<void> _add({String? email}) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = await navigator.push<String>(
      MaterialPageRoute(
        builder: (_) => AuthScreen(addingAccount: true, initialEmail: email),
      ),
    );
    if (outcome == null) return; // Backed out: nothing changed.
    if (mounted) navigator.pop();
    messenger?.showSnackBar(SnackBar(content: Text(outcome)));
  }

  Future<void> _remove(SavedAccount saved) async {
    final auth = AuthStore.instance;
    final active = saved.id == auth.account?.id;
    final others = auth.savedAccounts.where((a) => a.id != saved.id).toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Remove from this device?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${saved.account.email} will be signed out on this phone and '
                'taken off this list, and what this phone kept for it -- its '
                'cart, saved items and history -- is cleared from here.',
              ),
              const SizedBox(height: 10),
              Text(
                'The account itself is not deleted. Its orders, cart and '
                'saved items stay with it, and you can sign back in at any '
                'time.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (active && others.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'You will switch to ${others.first.account.email}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busyId = saved.id;
      _error = null;
      _expiredEmail = null;
    });
    final result = await auth.removeAccount(saved.id);
    await purgeAccountData(email: saved.account.email, accountId: saved.id);
    if (!mounted) return;
    setState(() => _busyId = null);

    final ended = result.revoked
        ? ''
        : ' The server could not be reached, so its session will expire on '
              'its own.';
    final now = result.switchedTo == null
        ? ''
        : ' Now using ${result.switchedTo!.email}.';
    _say('Removed ${saved.account.email} from this device.$ended$now');
    if (auth.savedAccounts.isEmpty && mounted) Navigator.of(context).pop();
  }

  void _manage(Widget page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        final auth = AuthStore.instance;
        final accounts = auth.savedAccounts;
        final activeId = auth.account?.id;

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Accounts on this device',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Switch without signing out. Each account keeps its own '
                    'cart, orders, saved items and notifications.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    _ErrorNote(
                      message: _error!,
                      action: _expiredEmail == null
                          ? null
                          : TextButton(
                              onPressed: () => _add(email: _expiredEmail),
                              child: const Text('Sign in'),
                            ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (accounts.isEmpty && !_listed)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (accounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No accounts are signed in on this device yet.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  else
                    for (final saved in accounts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AccountRow(
                          saved: saved,
                          active: saved.id == activeId,
                          busy: _busyId == saved.id,
                          enabled: _busyId == null,
                          onSwitch: () => _switch(saved),
                          onRemove: () => _remove(saved),
                          onManageProfile: () =>
                              _manage(const ProfileSettingsScreen()),
                          onManageSecurity: () =>
                              _manage(const LoginActivityScreen()),
                        ),
                      ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _busyId == null ? () => _add() : null,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Add another account'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One account in the list.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.saved,
    required this.active,
    required this.busy,
    required this.enabled,
    required this.onSwitch,
    required this.onRemove,
    required this.onManageProfile,
    required this.onManageSecurity,
  });

  final SavedAccount saved;
  final bool active;
  final bool busy;
  final bool enabled;
  final VoidCallback onSwitch;
  final VoidCallback onRemove;
  final VoidCallback onManageProfile;
  final VoidCallback onManageSecurity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final account = saved.account;
    final radius = BorderRadius.circular(AppTheme.radiusCard);

    return Semantics(
      button: !active,
      selected: active,
      label: active
          ? '${account.displayName}, ${account.email}, active account'
          : 'Switch to ${account.displayName}, ${account.email}',
      child: Material(
        color: active
            ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.07), scheme.surface)
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: active
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outlineVariant,
            width: active ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active || !enabled ? null : onSwitch,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  _Avatar(account: account),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            account.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(height: 4),
                            const _ActiveTag(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (active)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.check_circle, color: scheme.primary),
                    ),
                  PopupMenuButton<String>(
                    enabled: enabled,
                    tooltip: 'Options for ${account.email}',
                    onSelected: (value) => switch (value) {
                      'profile' => onManageProfile(),
                      'security' => onManageSecurity(),
                      'switch' => onSwitch(),
                      _ => onRemove(),
                    },
                    itemBuilder: (_) => [
                      if (active) ...const [
                        PopupMenuItem(
                          value: 'profile',
                          child: ListTile(
                            leading: Icon(Icons.manage_accounts_outlined),
                            title: Text('Edit profile and password'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'security',
                          child: ListTile(
                            leading: Icon(Icons.shield_outlined),
                            title: Text('Login activity and sessions'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ] else
                        const PopupMenuItem(
                          value: 'switch',
                          child: ListTile(
                            leading: Icon(Icons.swap_horiz),
                            title: Text('Switch to this account'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                          leading: Icon(Icons.logout, color: scheme.error),
                          title: Text(
                            'Remove from this device',
                            style: TextStyle(color: scheme.error),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveTag extends StatelessWidget {
  const _ActiveTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Active',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The account's photograph, or its initial.
///
/// The active account's is its profile photo -- the one the account page's
/// header shows -- so a photo just saved appears here at once. The others
/// show the copy saved with their sign-in, which a saved photo also updates.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.account});

  final Account account;

  static const _radius = 20.0;

  @override
  Widget build(BuildContext context) {
    final active = AuthStore.instance.account?.id == account.id;
    if (!active) return _photo(context, account.avatarUrl);
    return ListenableBuilder(
      listenable: ProfileStore.instance,
      builder: (context, _) =>
          _photo(context, ProfileStore.instance.avatarUrl ?? account.avatarUrl),
    );
  }

  Widget _photo(BuildContext context, String? url) {
    final theme = Theme.of(context);
    final name = account.displayName;
    final fallback = CircleAvatar(
      radius: _radius,
      backgroundColor: theme.colorScheme.primary,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: _radius * 2,
        height: _radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          ?action,
        ],
      ),
    );
  }
}

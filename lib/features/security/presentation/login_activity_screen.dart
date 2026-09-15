import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loadable_view.dart' show LoadFailed;
import '../../auth/data/auth_store.dart';

/// Security → Login activity.
///
/// Everything on this page comes from the auth server. What it can say is
/// what GoTrue tells a signed-in user about themselves -- when and how this
/// account last signed in -- and what it can do is what GoTrue lets them do:
/// sign out every other session, or this one.
///
/// A history of sign-ins, a per-device list with locations and new-login
/// alerts need server endpoints that do not exist yet. The page says so
/// rather than drawing any of them from guesses: an invented device list on a
/// security page is worse than none, because it would be trusted.
class LoginActivityScreen extends StatefulWidget {
  const LoginActivityScreen({super.key});

  @override
  State<LoginActivityScreen> createState() => _LoginActivityScreenState();
}

class _LoginActivityScreenState extends State<LoginActivityScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await AuthStore.instance.loginDetails();
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _expired = e.isUnauthorized;
        _error = e.message;
      });
    }
  }

  /// Whether the account has a password to confirm with. One that only ever
  /// signed in with Google has none, and is asked to confirm instead.
  bool get _hasPassword {
    final user = _user;
    if (user == null) return true;
    final providers = <String>{
      for (final identity in (user['identities'] as List?) ?? const [])
        if (identity is Map && identity['provider'] is String)
          identity['provider'] as String,
      ...(((user['app_metadata'] as Map?)?['providers'] as List?) ?? const [])
          .whereType<String>(),
    };
    return providers.isEmpty || providers.contains('email');
  }

  void _say(String message, {bool bad = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: bad ? theme.colorScheme.error : null,
        ),
      );
  }

  Future<void> _signOutOthers() async {
    final outcome = await showDialog<_Outcome>(
      context: context,
      builder: (_) => _SignOutOthersDialog(needsPassword: _hasPassword),
    );
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case _Outcome.done:
        _say('Signed out of all other devices.');
      case _Outcome.expired:
        setState(() {
          _expired = true;
          _error = 'Your session has expired. Sign in again.';
        });
    }
  }

  Future<void> _signOutHere() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of this device?'),
        content: const Text(
          'You will need to sign in again to use your account here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await AuthStore.instance.signOut();
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login activity')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _expired ? _expiredView() : _content(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _expiredView() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(Icons.lock_clock_outlined, size: 40, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            'Your session has expired',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in again to see your login activity.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            child: const Text('Back to account'),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final account = AuthStore.instance.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'This device',
          icon: Icons.smartphone_outlined,
          trailing: const _Tag('Current device'),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
              ? LoadFailed(
                  message: 'Login details could not be loaded.',
                  onRetry: () => unawaited(_load()),
                  compact: true,
                )
              : _Details(user: _user!, email: account?.email),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Session management',
          icon: Icons.devices_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Signing out other devices ends every session except this '
                'one. They stop working within an hour and cannot renew.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _signOutOthers,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out all other devices'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _signOutHere,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Sign out of this device'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Section(
          title: 'Login history and alerts',
          icon: Icons.history_toggle_off,
          child: _Unavailable(),
        ),
      ],
    );
  }
}

/// What the server knows about this account's sign-ins.
class _Details extends StatelessWidget {
  const _Details({required this.user, required this.email});

  final Map<String, dynamic> user;
  final String? email;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Local time, in words a shopper reads without thinking.
  static String? when(Object? iso) {
    if (iso is! String) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return null;
    final t = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day} ${_months[t.month - 1]} ${t.year}, '
        '${two(t.hour)}:${two(t.minute)}';
  }

  static String method(Map<String, dynamic> user) {
    final provider = (user['app_metadata'] as Map?)?['provider'];
    return switch (provider) {
      'email' => 'Email and password',
      'google' => 'Google',
      'apple' => 'Apple',
      String p when p.isNotEmpty => p[0].toUpperCase() + p.substring(1),
      _ => 'Not recorded',
    };
  }

  @override
  Widget build(BuildContext context) {
    final address = user['email'] is String ? user['email'] as String : email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(label: 'Account', value: address ?? 'Not recorded'),
        _Line(
          label: 'Last sign-in',
          value: when(user['last_sign_in_at']) ?? 'Not recorded',
        ),
        _Line(label: 'Signed in with', value: method(user)),
        _Line(label: 'Status', value: 'Active'),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            // One line, shrunk if it must: an address broken mid-word
            // ("gmail.c / om") reads as a different address.
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'A list of past sign-ins, your other signed-in devices with their '
            'locations, and new-login alerts are not available yet. They '
            'need server support that is still to come, and nothing is '
            'shown here until it is real.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

enum _Outcome { done, expired }

/// Confirms, verifies, and does it -- in one place, so a wrong password or a
/// failed request is shown beside the field and the dialog stays open.
class _SignOutOthersDialog extends StatefulWidget {
  const _SignOutOthersDialog({required this.needsPassword});

  final bool needsPassword;

  @override
  State<_SignOutOthersDialog> createState() => _SignOutOthersDialogState();
}

class _SignOutOthersDialogState extends State<_SignOutOthersDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (widget.needsPassword && _password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthStore.instance.signOutOtherDevices(
        password: widget.needsPassword ? _password.text : null,
      );
      _password.clear();
      if (mounted) Navigator.of(context).pop(_Outcome.done);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pop(_Outcome.expired);
        return;
      }
      setState(() {
        _busy = false;
        _error = e.isNetwork
            ? 'Could not reach the server. Nothing was changed; try again.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Sign out all other devices?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.needsPassword
                  ? 'Every other phone, tablet and browser will be signed '
                        'out. This device stays signed in. Enter your password '
                        'to confirm.'
                  : 'Every other phone, tablet and browser will be signed '
                        'out. This device stays signed in.',
            ),
            if (widget.needsPassword) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _hidden,
                autocorrect: false,
                enableSuggestions: false,
                autofocus: true,
                enabled: !_busy,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hidden ? Icons.visibility_off : Icons.visibility,
                    ),
                    tooltip: _hidden ? 'Show' : 'Hide',
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : const Text('Sign out others'),
        ),
      ],
    );
  }
}

/// One titled card, in the same shape as the profile settings page.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

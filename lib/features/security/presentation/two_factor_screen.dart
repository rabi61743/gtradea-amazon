import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../data/mfa_repository.dart';
import '../data/mfa_store.dart';
import 'totp_code_field.dart';

/// Security → Two-Factor Authentication.
///
/// Shows the status GoTrue holds and turns it on or off through GoTrue:
///
///   * **On:** password → the server generates a secret → scan the QR code (or
///     type the key) into an authenticator app → a code from the app, checked
///     by the server → on. Nothing says "on" until the server has verified.
///   * **Off:** password and a current code → confirm → the factor is removed
///     on the server → the status is read back.
///
/// The secret appears on screen once, during setup. It lives in this widget's
/// state only and is dropped when the setup ends or the page closes.
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

enum _Stage { status, confirmIdentity, setup, disable }

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _store = MfaStore.instance;
  final _password = TextEditingController();
  final _code = TextEditingController();

  _Stage _stage = _Stage.status;
  TotpEnrollment? _setup;
  bool _hasPassword = true;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _store.load();
    _store.currentSession().then((session) {
      if (mounted) setState(() => _hasPassword = MfaStore.hasPassword(session));
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    // An abandoned setup leaves nothing half-done on the server.
    final setup = _setup;
    if (setup != null) _store.cancelEnable(setup.factorId);
    _setup = null;
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _go(_Stage stage) {
    setState(() {
      _stage = stage;
      _error = null;
      _password.clear();
      _code.clear();
    });
  }

  // ── Enable ──────────────────────────────────────────────────────────────

  Future<void> _startEnable() async {
    if (_hasPassword && _password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() => _error = null);
    try {
      final setup = await _store.startEnable(
        password: _hasPassword ? _password.text : null,
      );
      if (!mounted) return;
      setState(() {
        _setup = setup;
        _stage = _Stage.setup;
        _password.clear();
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _confirmEnable([String? _]) async {
    final setup = _setup;
    if (setup == null || _store.busy) return;
    if (_code.text.length != TotpCodeField.length) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }
    setState(() => _error = null);
    try {
      await _store.confirmEnable(setup.factorId, _code.text);
      if (!mounted) return;
      _setup = null; // Verified: the secret is no longer needed anywhere here.
      _go(_Stage.status);
      if (_store.status == MfaStatus.enabled) {
        _say('Two-factor authentication is on');
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _error = e.message);
    }
  }

  Future<void> _cancelSetup() async {
    final setup = _setup;
    _setup = null;
    _go(_Stage.status);
    if (setup != null) await _store.cancelEnable(setup.factorId);
  }

  // ── Disable ─────────────────────────────────────────────────────────────

  Future<void> _disable() async {
    if (_hasPassword && _password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    if (_code.text.length != TotpCodeField.length) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off two-factor authentication?'),
        content: const Text(
          'Signing in will only need your password. Your account will be '
          'easier to get into if your password is ever stolen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it on'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _error = null);
    try {
      await _store.disable(
        password: _hasPassword ? _password.text : null,
        code: _code.text,
      );
      if (!mounted) return;
      _go(_Stage.status);
      if (_store.status == MfaStatus.disabled) {
        _say('Two-factor authentication is off');
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _Stage.status,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _stage == _Stage.setup ? _cancelSetup() : _go(_Stage.status);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Two-Factor Authentication')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: switch (_stage) {
                    _Stage.status => _statusView(),
                    _Stage.confirmIdentity => _identityView(),
                    _Stage.setup => _setupView(),
                    _Stage.disable => _disableView(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Views ───────────────────────────────────────────────────────────────

  Widget _statusView() {
    final theme = Theme.of(context);
    final status = _store.status;
    final muted = theme.colorScheme.onSurfaceVariant;

    if (status == MfaStatus.loading || status == MfaStatus.unknown) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (status == MfaStatus.error) {
      return _Card(
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, color: muted, size: 32),
            const SizedBox(height: 10),
            Text(
              _store.error ?? 'Your 2FA status could not be loaded.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _store.load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final on = status == MfaStatus.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Row(
            children: [
              _Disc(icon: on ? Icons.verified_user : Icons.shield_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Authenticator app',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      on
                          ? 'A code from your authenticator app is required '
                                'each time you sign in.'
                          : 'Add a code from an authenticator app to your '
                                'sign-in.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              MfaStatusChip(status: status),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (status == MfaStatus.setupIncomplete) ...[
          _Notice(
            text:
                'A setup was started but not finished, so two-factor '
                'authentication is not on yet. Start again to finish it.',
          ),
          const SizedBox(height: 14),
        ],
        if (on)
          OutlinedButton.icon(
            onPressed: _store.busy ? null : () => _go(_Stage.disable),
            icon: const Icon(Icons.remove_moderator_outlined),
            label: const Text('Turn off two-factor authentication'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.4),
              ),
            ),
          )
        else
          FilledButton.icon(
            onPressed: _store.busy ? null : () => _go(_Stage.confirmIdentity),
            icon: const Icon(Icons.add_moderator_outlined),
            label: Text(
              status == MfaStatus.setupIncomplete
                  ? 'Finish setting up'
                  : 'Turn on two-factor authentication',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        const SizedBox(height: 18),
        Text(
          'Works with Microsoft Authenticator, Google Authenticator and other '
          'apps that generate 6-digit codes. Keep access to your authenticator: '
          'if you lose it while this is on, contact support to recover your '
          'account.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }

  Widget _identityView() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeading(
          step: 'Step 1 of 2',
          title: 'Confirm it is you',
        ),
        const SizedBox(height: 6),
        Text(
          _hasPassword
              ? 'Enter your password to continue.'
              : 'Your account signs in with a provider. Continue to generate '
                    'your setup key.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (_hasPassword)
          _PasswordBox(
            controller: _password,
            hidden: _hidePassword,
            enabled: !_store.busy,
            onToggle: () => setState(() => _hidePassword = !_hidePassword),
            onSubmitted: _startEnable,
          ),
        _ErrorText(_error),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: 'Continue',
          busy: _store.busy,
          onPressed: _startEnable,
        ),
        TextButton(
          onPressed: _store.busy ? null : () => _go(_Stage.status),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _setupView() {
    final theme = Theme.of(context);
    final setup = _setup!;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeading(step: 'Step 2 of 2', title: 'Set up your authenticator'),
        const SizedBox(height: 6),
        Text(
          '1. Open Microsoft Authenticator (or any authenticator app) and add '
          'an account.\n2. Scan this QR code, or enter the key below.\n3. '
          'Enter the 6-digit code the app shows.',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            children: [
              Container(
                width: 196,
                height: 196,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: SvgPicture.string(
                  setup.qrSvg,
                  semanticsLabel: 'QR code for your authenticator app',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Can’t scan? Enter this key',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: SelectableText(
                      _grouped(setup.secret),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy key',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: setup.secret));
                      if (mounted) _say('Key copied');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Code from your app',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TotpCodeField(
          controller: _code,
          enabled: !_store.busy,
          autofocus: false,
          onCompleted: _confirmEnable,
        ),
        _ErrorText(_error),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: 'Verify and turn on',
          busy: _store.busy,
          onPressed: _confirmEnable,
        ),
        TextButton(
          onPressed: _store.busy ? null : _cancelSetup,
          child: const Text('Cancel setup'),
        ),
      ],
    );
  }

  Widget _disableView() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeading(step: 'Security check', title: 'Turn off 2FA'),
        const SizedBox(height: 6),
        Text(
          _hasPassword
              ? 'Enter your password and a current code from your '
                    'authenticator app.'
              : 'Enter a current code from your authenticator app.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (_hasPassword) ...[
          _PasswordBox(
            controller: _password,
            hidden: _hidePassword,
            enabled: !_store.busy,
            onToggle: () => setState(() => _hidePassword = !_hidePassword),
          ),
          const SizedBox(height: 16),
        ],
        TotpCodeField(
          controller: _code,
          enabled: !_store.busy,
          autofocus: !_hasPassword,
        ),
        _ErrorText(_error),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _store.busy ? null : _disable,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: theme.colorScheme.error,
          ),
          child: _store.busy
              ? const _Spinner()
              : const Text('Turn off two-factor authentication'),
        ),
        TextButton(
          onPressed: _store.busy ? null : () => _go(_Stage.status),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  /// "JBSW Y3DP EHPK 3PXP" -- groups of four are how every authenticator app
  /// shows a key, and how people copy one by eye without losing their place.
  static String _grouped(String secret) {
    final clean = secret.replaceAll(' ', '');
    final parts = <String>[];
    for (var i = 0; i < clean.length; i += 4) {
      parts.add(clean.substring(i, i + 4 > clean.length ? clean.length : i + 4));
    }
    return parts.join(' ');
  }
}

/// The status as a chip: Enabled (green), Not enabled (grey), Setup incomplete
/// (amber). Shared with the Profile Settings row, so both say the same thing.
class MfaStatusChip extends StatelessWidget {
  const MfaStatusChip({super.key, required this.status, this.style});

  final MfaStatus status;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, ink) = switch (status) {
      MfaStatus.enabled => ('Enabled', AppColors.successInk),
      MfaStatus.setupIncomplete => ('Setup incomplete', AppColors.warning),
      MfaStatus.error => ('Unavailable', theme.colorScheme.onSurfaceVariant),
      MfaStatus.loading || MfaStatus.unknown => (
        'Checking…',
        theme.colorScheme.onSurfaceVariant,
      ),
      MfaStatus.disabled => ('Not enabled', theme.colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: (style ?? theme.textTheme.labelMedium)?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

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
      child: child,
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tint = Theme.of(context).colorScheme.primary;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.10),
      ),
      child: Icon(icon, color: tint, size: 22),
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.step, required this.title});

  final String step;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _PasswordBox extends StatelessWidget {
  const _PasswordBox({
    required this.controller,
    required this.hidden,
    required this.enabled,
    required this.onToggle,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool hidden;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: hidden,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.password],
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: hidden ? 'Show' : 'Hide',
          icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: busy ? const _Spinner() : Text(label),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

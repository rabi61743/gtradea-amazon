import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../data/auth_repository.dart';
import '../data/auth_store.dart';
import 'forgot_password_screen.dart' show AuthFurniture;

/// Setting the new password, from the link in the email.
///
/// The link opens the shop's own reset page in a browser, and it also works
/// here: paste it in and this does the same two calls that page does --
/// `POST /verify` to trade the one-time token for a short-lived session, then
/// `PUT /user` to set the password. Both are the server's; nothing about a
/// password is decided in this app.
///
/// The token is read out of whatever is pasted and is never shown back, never
/// logged and never stored. The password is sent once and not written down at
/// all.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});

  /// For a link the app already has in hand.
  final String? initialToken;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _link = TextEditingController(text: widget.initialToken ?? '');
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The requirement list ticks as it is typed.
    _password.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final token = AuthRepository.tokenFromLink(_link.text);
    if (token == null) {
      setState(() => _error = 'That does not look like a reset link.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AuthStore.instance.resetPassword(
        token: token,
        password: _password.text,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  /// The two refusals that actually happen, in words that say what to do.
  static String _friendly(ApiError e) {
    final raw = e.message.toLowerCase();
    if (raw.contains('expired') ||
        raw.contains('invalid') ||
        raw.contains('not found')) {
      return 'That link has already been used or has expired. Ask for a new '
          'one and try again.';
    }
    if (e.isNetwork) {
      return 'No connection, so the password could not be changed.';
    }
    // Anything else is the server's own words -- a password policy it enforces
    // and this app does not know about belongs here verbatim.
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
        title: const Text('Set a new password'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _done ? _success(theme) : _form(theme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _form(ThemeData theme) => [
    const SizedBox(height: 8),
    AuthFurniture.mark(
      icon: Icons.password_outlined,
      tone: theme.colorScheme.primary,
    ),
    const SizedBox(height: 20),
    Text(
      'Set a new password',
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    const SizedBox(height: 8),
    Text(
      'Paste the link from the email, then choose the password you want.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 24),
    TextFormField(
      controller: _link,
      enabled: !_busy,
      autofocus: widget.initialToken == null,
      keyboardType: TextInputType.url,
      autocorrect: false,
      maxLines: 2,
      minLines: 1,
      decoration: const InputDecoration(
        hintText: 'Paste the reset link',
        prefixIcon: Icon(Icons.link),
      ),
      validator: (value) =>
          (value ?? '').trim().isEmpty ? 'Paste the link from the email' : null,
    ),
    const SizedBox(height: 14),
    TextFormField(
      controller: _password,
      enabled: !_busy,
      obscureText: _obscure,
      decoration: InputDecoration(
        hintText: 'New password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: validatePassword,
    ),
    const SizedBox(height: 14),
    TextFormField(
      controller: _confirm,
      enabled: !_busy,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submit(),
      decoration: const InputDecoration(
        hintText: 'Confirm new password',
        prefixIcon: Icon(Icons.lock_outline),
      ),
      validator: (value) =>
          value == _password.text ? null : 'Both passwords must match',
    ),
    const SizedBox(height: 14),
    _Requirements(password: _password.text, confirm: _confirm.text),
    if (_error != null) ...[
      const SizedBox(height: 14),
      AuthFurniture.notice(message: _error!, tone: theme.colorScheme.error),
    ],
    const SizedBox(height: 18),
    AuthFurniture.primaryButton(
      label: 'Update password',
      busy: _busy,
      onPressed: _busy ? null : _submit,
    ),
    Center(
      child: TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Back'),
      ),
    ),
  ];

  List<Widget> _success(ThemeData theme) => [
    const SizedBox(height: 8),
    AuthFurniture.mark(
      icon: Icons.check_circle_outline,
      tone: AppColors.success,
    ),
    const SizedBox(height: 20),
    Text(
      'Password updated',
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    const SizedBox(height: 8),
    Text(
      'You are signed in with the new password. It is what to use next time.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 24),
    AuthFurniture.primaryButton(
      label: 'Continue shopping',
      busy: false,
      // True: the password was set and the session adopted, so the pages
      // stacked behind this one are done with.
      onPressed: () => Navigator.of(context).pop(true),
    ),
  ];
}

/// The app's own floor, which is above the server's.
///
/// GoTrue enforces its own minimum and will refuse anything under it; this
/// stops a password the server would reject from costing a round trip, and
/// never accepts one it would refuse.
String? validatePassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Enter a password';
  if (password.length < 8) return 'Use at least 8 characters';
  return null;
}

/// What the password still needs, ticking as it is typed.
class _Requirements extends StatelessWidget {
  const _Requirements({required this.password, required this.confirm});

  final String password;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only what is actually enforced. A list that asks for a capital and a
    // number while accepting a password without either is decoration.
    final rules = [
      ('At least 8 characters', password.length >= 8),
      ('Both passwords match', confirm.isNotEmpty && confirm == password),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, met) in rules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  met ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: met
                      ? AppColors.success
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: met
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

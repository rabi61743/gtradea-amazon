import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../data/auth_store.dart';
import 'reset_password_screen.dart';

/// "Forgot password": ask for the address, send the link.
///
/// A page rather than the dialog this used to be. The step it opens is a real
/// one -- go to your inbox, come back with a link -- and a dialog is the wrong
/// shape for something you have to leave the app to finish.
///
/// **What it will not do is tell you whether the address has an account.**
/// GoTrue answers the same either way, deliberately: a form that says "no such
/// account" is a way to find out who shops here. So the confirmation says what
/// is true -- if there is an account, a link is on its way -- and says it for
/// every address that is shaped like one.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// Carried over from the sign-in form, so the address is not typed twice.
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);

  bool _busy = false;
  String? _error;

  /// The address the link was sent to, once one has been. Null until then,
  /// which is what tells the two halves of this page apart.
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // The guard that makes a second tap do nothing: the button is disabled
    // while this runs, and this refuses anyway in case a hardware keyboard
    // submits the form under it.
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AuthStore.instance.recover(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sentTo = email;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Rate limiting is the one refusal worth its own words: asking twice
        // in a minute is a normal thing to do and is not an error on the
        // shopper's part.
        _error = e.message.toLowerCase().contains('rate limit')
            ? 'That link was requested a moment ago. Wait a minute and try '
                  'again -- the first email is still on its way.'
            : e.isNetwork
            ? 'No connection, so the reset link could not be requested.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _openReset() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
    );
    // The password was set and the session adopted: this page and the sign-in
    // page behind it have nothing left to do.
    if (done == true && mounted) Navigator.of(context).pop();
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
        title: const Text('Forgot password'),
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
                  children: _sentTo == null ? _ask(theme) : _sent(theme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Before the link is asked for.
  List<Widget> _ask(ThemeData theme) => [
    const SizedBox(height: 8),
    _Mark(icon: Icons.lock_reset_outlined, tone: theme.colorScheme.primary),
    const SizedBox(height: 20),
    Text(
      'Forgot your password?',
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    const SizedBox(height: 8),
    Text(
      'Enter the email address on your account and we will send you a link to '
      'set a new password.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 24),
    TextFormField(
      controller: _email,
      enabled: !_busy,
      autofocus: widget.initialEmail.isEmpty,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      onFieldSubmitted: (_) => _send(),
      decoration: const InputDecoration(
        hintText: 'Email address',
        prefixIcon: Icon(Icons.mail_outline),
      ),
      validator: validateEmail,
    ),
    if (_error != null) ...[
      const SizedBox(height: 14),
      _Notice(message: _error!, tone: theme.colorScheme.error),
    ],
    const SizedBox(height: 18),
    _PrimaryButton(
      label: 'Send reset link',
      busy: _busy,
      onPressed: _busy ? null : _send,
    ),
    const SizedBox(height: 6),
    Center(
      child: TextButton(
        onPressed: _busy ? null : _openReset,
        child: const Text('I already have a reset link'),
      ),
    ),
    Center(
      child: TextButton.icon(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Back to sign in'),
      ),
    ),
  ];

  /// After it has been sent.
  List<Widget> _sent(ThemeData theme) => [
    const SizedBox(height: 8),
    const _Mark(icon: Icons.mark_email_read_outlined, tone: AppColors.success),
    const SizedBox(height: 20),
    Text(
      'Check your email',
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    const SizedBox(height: 8),
    Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'If '),
          TextSpan(
            text: _sentTo,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const TextSpan(
            text:
                ' has an account, a link to set a new password is on its way. '
                'It is good for one use and expires after a while.',
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 24),
    _PrimaryButton(
      label: 'I have the link',
      busy: false,
      onPressed: _openReset,
    ),
    const SizedBox(height: 6),
    Center(
      child: TextButton(
        // Back to the form with the address still in it, for a typo or a
        // second attempt.
        onPressed: () => setState(() => _sentTo = null),
        child: const Text('Send it again'),
      ),
    ),
    Center(
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Back to sign in'),
      ),
    ),
  ];
}

/// Shape only. Whether the address exists is the server's business, and the
/// server will not say -- see the note on [ForgotPasswordScreen].
String? validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) return 'Enter your email';
  final at = email.indexOf('@');
  final dot = email.lastIndexOf('.');
  if (at < 1 || dot < at + 2 || dot == email.length - 1) {
    return 'Enter a valid email address';
  }
  return null;
}

/// The round icon at the head of each state.
class _Mark extends StatelessWidget {
  const _Mark({required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 34, color: tone),
      ),
    );
  }
}

/// The brand-band button the sign-in page uses, so the two pages carry the
/// same primary action rather than two different ones.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppTheme.radiusCard);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppColors.brandBand,
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 54,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(
                            AppColors.onPrimary,
                          ),
                        ),
                      )
                    : Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A message in the page's own colours: what went wrong, or what happened.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.tone});

  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared with the reset page, which needs the same two pieces.
class AuthFurniture {
  const AuthFurniture._();

  static Widget mark({required IconData icon, required Color tone}) =>
      _Mark(icon: icon, tone: tone);

  static Widget notice({required String message, required Color tone}) =>
      _Notice(message: message, tone: tone);

  static Widget primaryButton({
    required String label,
    required bool busy,
    required VoidCallback? onPressed,
  }) => _PrimaryButton(label: label, busy: busy, onPressed: onPressed);
}

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../shared/widgets/brand_wordmark.dart';
import '../data/auth_store.dart';

/// Which half of the screen opens first.
enum AuthMode { signIn, signUp }

/// Sign in and sign up, as two modes of one screen.
///
/// One screen rather than two: the fields are almost the same, and someone who
/// taps the wrong button should be able to switch without losing what they have
/// typed or backing out to the account page.
///
/// Submits to GoTrue. The password is sent and never stored -- what comes back
/// is a token pair, which lives in the keystore, not here.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.initialMode = AuthMode.signIn});

  final AuthMode initialMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late AuthMode _mode = widget.initialMode;
  bool _obscure = true;
  bool _busy = false;

  /// The server's own words, shown above the button rather than in a snack bar:
  /// a wrong password belongs beside the password, and a message that slides
  /// away while someone is still reading it is no use.
  String? _error;
  String? _notice;

  bool get _isSignUp => _mode == AuthMode.signUp;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchTo(AuthMode mode) {
    if (mode == _mode) return;
    // Deliberately keeps the controllers: switching modes should not throw away
    // an email that was already typed.
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_isSignUp) {
        final (first, last) = _splitName(_name.text);
        final needsConfirmation = await AuthStore.instance.signUp(
          email: _email.text,
          password: _password.text,
          firstName: first,
          lastName: last,
        );
        if (!mounted) return;
        if (needsConfirmation) {
          // The account exists but cannot be used yet. Popping here would drop
          // them back on a signed-out account page with no explanation.
          setState(() {
            _busy = false;
            _mode = AuthMode.signIn;
            _password.clear();
            _notice =
                'Account created. Check ${_email.text.trim()} for the '
                'confirmation link, then sign in.';
          });
          return;
        }
      } else {
        await AuthStore.instance.signIn(
          email: _email.text,
          password: _password.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
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

  /// GoTrue's wording is accurate but terse. Two cases are worth rephrasing,
  /// because they are the two that actually happen.
  String _friendly(ApiError e) {
    final raw = e.message.toLowerCase();
    if (raw.contains('invalid login credentials')) {
      return 'That email and password do not match an account.';
    }
    if (raw.contains('email not confirmed')) {
      return 'Confirm your email first - check your inbox for the link.';
    }
    return e.message;
  }

  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _RecoverDialog(initialEmail: _email.text),
    );
    if (email == null || !mounted) return;

    try {
      await AuthStore.instance.recover(email);
    } on ApiError {
      // Deliberately swallowed. GoTrue answers the same for an address with an
      // account and one without, and a visible failure here would leak which is
      // which -- so the message below is the only answer, either way.
    }
    if (!mounted) return;
    setState(() {
      _notice = 'If $email has an account, a reset link is on its way.';
    });
  }

  static (String?, String?) _splitName(String value) {
    final parts = value.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return (null, null);
    if (parts.length == 1) return (parts.first, null);
    return (parts.first, parts.sublist(1).join(' '));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Create account' : 'Sign in')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _ModeToggle(mode: _mode, onChanged: _busy ? null : _switchTo),
            const SizedBox(height: 24),
            Text(
              _isSignUp ? 'Join ${AppBrand.name}' : 'Welcome back',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSignUp
                  ? 'Create an account to track orders and save what you like.'
                  : 'Sign in to pick up where you left off.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (_isSignUp) ...[
              TextFormField(
                controller: _name,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter your name' : null,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: _validateEmail,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
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
              validator: _validatePassword,
            ),
            if (!_isSignUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _Banner(message: _error!, tone: theme.colorScheme.error),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 16),
              _Banner(message: _notice!, tone: theme.colorScheme.primary),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(_isSignUp ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _switchTo(
                        _isSignUp ? AuthMode.signIn : AuthMode.signUp,
                      ),
                child: Text(
                  _isSignUp
                      ? 'Already have an account? Sign in'
                      : 'New to ${AppBrand.name}? Create an account',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shape only. Whether the address exists is the server's business, and
  /// rejecting valid-but-unusual addresses locally is worse than accepting one
  /// the server will bounce.
  static String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter your email';
    final at = email.indexOf('@');
    final dot = email.lastIndexOf('.');
    if (at < 1 || dot < at + 2 || dot == email.length - 1) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password';
    if (password.length < 8) return 'Use at least 8 characters';
    return null;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.tone});

  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
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

class _RecoverDialog extends StatefulWidget {
  const _RecoverDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_RecoverDialog> createState() => _RecoverDialogState();
}

class _RecoverDialogState extends State<_RecoverDialog> {
  late final _controller = TextEditingController(text: widget.initialEmail);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final error = _AuthScreenState._validateEmail(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset your password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('We will email you a link to set a new one.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Email', errorText: _error),
            onSubmitted: (_) => _send(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _send, child: const Text('Send link')),
      ],
    );
  }
}

/// Segmented Sign in / Sign up switch.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final AuthMode mode;
  final ValueChanged<AuthMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AuthMode>(
      segments: const [
        ButtonSegment(value: AuthMode.signIn, label: Text('Sign In')),
        ButtonSegment(value: AuthMode.signUp, label: Text('Sign Up')),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged!(selection.first),
    );
  }
}

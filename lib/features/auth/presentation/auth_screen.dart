import 'package:flutter/material.dart';

import '../data/auth_store.dart';

/// Which half of the screen opens first.
enum AuthMode { signIn, signUp }

/// Sign in and sign up, as two modes of one screen.
///
/// One screen rather than two: the fields are almost the same, and someone who
/// taps the wrong button should be able to switch without losing what they have
/// typed or backing out to the account page.
///
/// **The submit is a local placeholder.** Nothing is sent anywhere and no
/// password is checked or kept -- it validates the shape of the input and calls
/// [AuthStore.signIn]. The sibling storefront posts to GoTrue at
/// `/auth/v1/token` and `/auth/v1/signup`; wiring that up replaces [_submit]
/// and nothing else on this screen.
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
    setState(() => _mode = mode);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    AuthStore.instance.signIn(
      email: _email.text,
      name: _isSignUp ? _name.text : null,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
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
            _ModeToggle(mode: _mode, onChanged: _switchTo),
            const SizedBox(height: 24),
            Text(
              _isSignUp ? 'Join GtradeA' : 'Welcome back',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
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
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter your name'
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
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
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password recovery is not wired up yet'),
                    ),
                  ),
                  child: const Text('Forgot password?'),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(_isSignUp ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () =>
                    _switchTo(_isSignUp ? AuthMode.signIn : AuthMode.signUp),
                child: Text(
                  _isSignUp
                      ? 'Already have an account? Sign in'
                      : 'New to GtradeA? Create an account',
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

/// Segmented Sign in / Sign up switch.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AuthMode>(
      segments: const [
        ButtonSegment(value: AuthMode.signIn, label: Text('Sign In')),
        ButtonSegment(value: AuthMode.signUp, label: Text('Sign Up')),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

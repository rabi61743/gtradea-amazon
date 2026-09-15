import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/brand_wordmark.dart';
import '../data/auth_store.dart';
import 'provider_sign_in.dart';
import '../data/remembered_email.dart';
import 'forgot_password_screen.dart';

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
  const AuthScreen({
    super.key,
    this.initialMode = AuthMode.signIn,
    this.addingAccount = false,
    this.initialEmail,
  });

  final AuthMode initialMode;

  /// Opened to add another account beside the one already signed in. The
  /// same sign-in, sign-up and provider flows; the screen says what it is for
  /// and hands back what happened so the account page can say it.
  final bool addingAccount;

  /// Filled in, for a saved account whose session ended and needs its
  /// password again.
  final String? initialEmail;

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

  /// Ticked by default, which is what the design shows. It decides one thing
  /// and says so: whether this handset fills the address in next time. See
  /// [RememberedEmail].
  bool _remember = true;

  /// Whether the server actually has Google configured.
  ///
  /// Asked rather than assumed. A provider button that opens a page saying
  /// "Unsupported provider" is worse than no button, and the answer is a single
  /// call the sign-in screen can afford to make while somebody types.
  bool _googleEnabled = false;

  /// The server's own words, shown above the button rather than in a snack bar:
  /// a wrong password belongs beside the password, and a message that slides
  /// away while someone is still reading it is no use.
  String? _error;
  String? _notice;

  bool get _isSignUp => _mode == AuthMode.signUp;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreEmail());
    unawaited(_loadProviders());
  }

  Future<void> _restoreEmail() async {
    // A saved account signing in again: its own address, not the last one
    // typed on this device.
    final given = widget.initialEmail;
    if (given != null && given.isNotEmpty) {
      _email.text = given;
      return;
    }
    // Adding another account: the remembered address is the one already
    // signed in, which is exactly the one not being added.
    if (widget.addingAccount) return;
    final remembered = await RememberedEmail.read();
    if (!mounted || remembered == null || _email.text.isNotEmpty) return;
    setState(() {
      _email.text = remembered;
      _remember = true;
    });
  }

  Future<void> _loadProviders() async {
    final providers = await AuthStore.instance.enabledProviders();
    if (!mounted) return;
    setState(() {
      _googleEnabled = providers.contains('google');
    });
  }

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
      // Only once the address is known to be one the server accepts. Keeping a
      // typo would prefill the mistake every time from then on.
      await _saveRemembered();
      if (!mounted) return;
      Navigator.of(context).pop(_outcome());
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

  /// What the account page should say once this screen closes signed in.
  ///
  /// Only when adding an account: an ordinary sign-in says nothing, as it
  /// never did. An account that was already on the device is reported as
  /// such -- it was switched to, not added twice.
  String? _outcome() {
    final already = AuthStore.instance.takeWasAlreadySaved();
    if (!widget.addingAccount) return null;
    final email = AuthStore.instance.account?.email ?? _email.text.trim();
    return already
        ? '$email was already on this device. Switched to it.'
        : 'Added $email and switched to it.';
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

  /// Persists, or forgets, the address the box is about.
  Future<void> _saveRemembered() async {
    if (_remember) {
      await RememberedEmail.write(_email.text);
    } else {
      await RememberedEmail.clear();
    }
  }

  /// Google, through the provider handshake the server already speaks.
  ///
  /// The page is Google's own, in a WebView; what comes back is the redirect
  /// URL with the tokens in its fragment, which [AuthStore.completeOAuth]
  /// turns into a session. Backing out of it is a cancellation, not a failure,
  /// and says nothing.
  Future<void> _continueWithGoogle() =>
      _continueWithProvider('google', 'Google');

  /// Apple, through the same handshake. Nothing here is Apple-specific: the
  /// server names its providers and GoTrue speaks the same flow for each, so
  /// the only difference between this and Google is the word on the button.
  Future<void> _continueWithApple() => _continueWithProvider('apple', 'Apple');

  /// One provider handshake, whichever provider it is.
  ///
  /// Shared rather than copied so the second provider cannot drift from the
  /// first: the same busy state, the same cancellation-is-not-a-failure rule,
  /// and the same place errors are shown.
  Future<void> _continueWithProvider(String provider, String label) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    final result = await startProviderSignIn(
      context,
      provider: provider,
      label: label,
    );
    if (!mounted) return;

    switch (result.outcome) {
      case ProviderSignInOutcome.signedIn:
        Navigator.of(context).pop(_outcome());
      case ProviderSignInOutcome.cancelled:
        setState(() => _busy = false);
      case ProviderSignInOutcome.failed:
        setState(() {
          _busy = false;
          _error = result.message;
        });
    }
  }

  /// Opens the reset page, carrying whatever address is already typed.
  ///
  /// A page rather than the dialog this was: sending the link is only the
  /// first half, and what follows -- go to the inbox, come back with the link,
  /// set a password -- does not fit in a dialog. It owns its own errors and
  /// its own confirmation, so nothing comes back here to display.
  Future<void> _forgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialEmail: _email.text),
      ),
    );
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
      appBar: AppBar(
        // The page is its own headline -- the mark, the name and the line
        // under it -- so the bar carries nothing but the way back.
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
        title: const SizedBox.shrink(),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            // Centred and capped: on a tablet or a desktop window the column
            // stays a form rather than stretching into a banner.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The mark and the line under it are the page's headline,
                    // so they stay on the page.
                    ..._header(theme),
                    const SizedBox(height: 28),
                    // The form sits on the page itself, not in a card: the
                    // fields are white and outlined, so they read against the
                    // page ground without a second white surface around them.
                    // The column above already caps and centres the width.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _form(theme),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The page's headline: the lockup, and the line that says which mode this
  /// is. Above the card rather than inside it.
  List<Widget> _header(ThemeData theme) {
    return [
      const SizedBox(height: 8),
      // The supplied lockup, which carries the mark and the name together --
      // so the name is not set again underneath it. Sized by width and left to
      // find its own height from the artwork's ratio: it never stretches, and
      // on a narrow phone it takes the column's width rather than overflowing
      // it.
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: AspectRatio(
            aspectRatio: AppBrand.lockupAspectRatio,
            child: Image.asset(
              AppBrand.lockupAsset,
              fit: BoxFit.contain,
              semanticLabel: AppBrand.name,
              // Decoded at the size it is drawn, not at the artwork's.
              cacheWidth: (300 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        _isSignUp
            ? 'Create an account to start shopping'
            : 'Sign in to continue shopping',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  /// What the card holds: the fields, the submit, whatever providers the
  /// server offers, and the way across to the other mode.
  List<Widget> _form(ThemeData theme) {
    return [
      if (_isSignUp) ...[
        TextFormField(
          controller: _name,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Full name',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Enter your name' : null,
        ),
        const SizedBox(height: 14),
      ],
      TextFormField(
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        decoration: const InputDecoration(
          hintText: 'Email address',
          prefixIcon: Icon(Icons.mail_outline),
        ),
        validator: _validateEmail,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _password,
        enabled: !_busy,
        obscureText: _obscure,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Password',
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
      if (!_isSignUp) ...[
        const SizedBox(height: 4),
        // A Wrap rather than a Row: side by side while they fit, stacked when
        // they do not. As a Row the pair overflowed by 22pt at the widest
        // metrics -- a large text size, or a narrow handset, would have put a
        // striped bar across the sign-in form.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _RememberMe(
              value: _remember,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() => _remember = value);
                      // Untick and the address is gone now, not at the next
                      // successful sign-in: somebody clearing it on a shared
                      // handset means now.
                      if (!value) unawaited(RememberedEmail.clear());
                    },
            ),
            TextButton(
              onPressed: _busy ? null : _forgotPassword,
              child: const Text('Forgot password?'),
            ),
          ],
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        _Banner(message: _error!, tone: theme.colorScheme.error),
      ],
      if (_notice != null) ...[
        const SizedBox(height: 12),
        _Banner(message: _notice!, tone: theme.colorScheme.primary),
      ],
      const SizedBox(height: 16),
      _SubmitButton(
        label: _isSignUp ? 'Create account' : 'Sign in',
        busy: _busy,
        onPressed: _busy ? null : _submit,
      ),
      // One divider for however many providers are offered, rather than one
      // each: it separates the form from the alternatives, and there is only
      // one form. Apple is always offered; whether the server will take it is
      // checked when it is tapped, and a refusal lands in the banner above.
      const SizedBox(height: 22),
      const _OrDivider(),
      const SizedBox(height: 16),
      if (_googleEnabled) ...[
        GoogleSignInButton(onPressed: _busy ? null : _continueWithGoogle),
        const SizedBox(height: 12),
      ],
      AppleSignInButton(onPressed: _busy ? null : _continueWithApple),
      const SizedBox(height: 22),
      const _SecurityNote(),
      const SizedBox(height: 10),
      Center(
        child: TextButton(
          onPressed: _busy
              ? null
              : () => _switchTo(_isSignUp ? AuthMode.signIn : AuthMode.signUp),
          child: Text(
            _isSignUp
                ? 'Already have an account? Sign in'
                : 'New to ${AppBrand.name}? Create an account',
          ),
        ),
      ),
    ];
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

/// "Remember me", and what it remembers.
class _RememberMe extends StatelessWidget {
  const _RememberMe({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;

    return InkWell(
      // The words are part of the target. A 20pt box on its own is a hard
      // thing to hit with a thumb.
      onTap: enabled ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Remember me',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The primary button: the brand band, with the arrow the design carries.
///
/// A gradient, so [Ink] rather than a filled button's own colour -- and the
/// ripple on top of it, which is why the Material is transparent.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
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
            // Faded rather than greyed while it works: the band is the button,
            // and a disabled fill would lose it.
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
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.arrow_forward,
                            size: 20,
                            color: AppColors.onPrimary,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "or continue with", ruled either side.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// What happens to what was typed.
///
/// Two sentences the app can stand behind: the password goes to the identity
/// provider over TLS and is never written down here, and nothing on this screen
/// is passed to anyone else.
class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              size: 20,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your data is 100% secure',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'We never share your information',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

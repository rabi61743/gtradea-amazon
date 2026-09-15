import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../auth/data/auth_store.dart';
import '../data/email_verification_store.dart';

/// Changing the address the account signs in with, and proving it.
///
/// The same three panels and the same visual language as the phone flow, for
/// the same reason: an address nobody proved is an address somebody else's
/// order confirmations go to.
///
/// **Nothing here decides whether an address is verified.** The code is made
/// and checked by GoTrue; this screen sends what was typed and reads the
/// answer. See [EmailVerificationStore].
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  /// Opens the flow and reports whether an address was actually confirmed.
  static Future<bool> open(BuildContext context) async {
    EmailVerificationStore.instance.reset();
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EmailVerificationScreen()),
    );
    return done ?? false;
  }

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _store = EmailVerificationStore.instance;
  final _email = TextEditingController();
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    // The store outlives this screen, and its countdown would outlive it too.
    _store.stopClocks();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    await _store.send(_email.text);
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    await _store.confirm(_code.text);
  }

  void _changeAddress() {
    _code.clear();
    _store.changeAddress();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: _store.done
          ? null
          : AppBar(
              backgroundColor: theme.colorScheme.surfaceContainerLowest,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Text(
                _store.entering
                    ? 'Change Email Address'
                    : 'Verify Email Address',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (EmailVerificationStore.demoActive) const _DemoBanner(),
                  if (_store.entering)
                    _EnterAddress(
                      controller: _email,
                      busy: _store.sending,
                      error: _store.error,
                      onSend: _send,
                      onCancel: () => Navigator.of(context).pop(false),
                    )
                  else if (_store.confirming)
                    _EnterCode(
                      controller: _code,
                      address: _store.pending ?? '',
                      expiresIn: _store.expiresIn,
                      resendIn: _store.resendIn,
                      canResend: _store.canResend,
                      busy: _store.checking,
                      sending: _store.sending,
                      error: _store.error,
                      onVerify: _verify,
                      onResend: _store.resend,
                      onChangeAddress: _changeAddress,
                    )
                  else
                    _Done(
                      address: _store.confirmed ?? '',
                      onBack: () => Navigator.of(context).pop(true),
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

// ── Panel one: the address ──────────────────────────────────────────────────

class _EnterAddress extends StatelessWidget {
  const _EnterAddress({
    required this.controller,
    required this.busy,
    required this.error,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool busy;
  final String? error;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = AuthStore.instance.account?.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Enter your new email address. We'll send you a verification code to "
          'confirm it.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.35,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (current != null) ...[
          const SizedBox(height: 4),
          Text(
            'You sign in with $current.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 26),
        const _Art(badge: Icons.shield),
        const SizedBox(height: 30),
        Text(
          'New email address',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSend(),
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'youremail@example.com',
              prefixIcon: Icon(Icons.mail_outline, size: 19),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          "We'll send a 6-digit code to this email address.",
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (error != null) ...[const SizedBox(height: 12), _ErrorLine(error!)],
        const SizedBox(height: 26),
        _PrimaryButton(
          label: 'Send Verification Code',
          busy: busy,
          onTap: onSend,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: busy ? null : onCancel,
          child: Text(
            'Cancel',
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Panel two: the code ─────────────────────────────────────────────────────

class _EnterCode extends StatelessWidget {
  const _EnterCode({
    required this.controller,
    required this.address,
    required this.expiresIn,
    required this.resendIn,
    required this.canResend,
    required this.busy,
    required this.sending,
    required this.error,
    required this.onVerify,
    required this.onResend,
    required this.onChangeAddress,
  });

  final TextEditingController controller;
  final String address;
  final int expiresIn;
  final int resendIn;
  final bool canResend;
  final bool busy;
  final bool sending;
  final String? error;
  final VoidCallback onVerify;
  final Future<bool> Function() onResend;
  final VoidCallback onChangeAddress;

  static const _digits = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the 6-digit code sent to',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          address,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 22),
        const _Art(code: true),
        const SizedBox(height: 26),
        _CodeBoxes(controller: controller, count: _digits),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            text: 'Code expires in ',
            children: [
              TextSpan(
                text: EmailVerificationStore.clock(expiresIn),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (error != null) ...[const SizedBox(height: 12), _ErrorLine(error!)],
        const SizedBox(height: 20),
        // Listening to the controller, because nothing else here does. This
        // screen repaints on *store* news, and typing is not store news: the
        // button read the text once, at build, and then never again. The
        // one-second clock was rebuilding the screen underneath it and hiding
        // that -- and the clock is now stopped when the screen closes.
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _PrimaryButton(
            label: 'Verify',
            busy: busy,
            onTap: controller.text.length == _digits ? onVerify : null,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: canResend
              ? TextButton(
                  onPressed: sending ? null : () => onResend(),
                  child: Text(
                    'Resend OTP',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Resend OTP in '
                    '${EmailVerificationStore.clock(resendIn)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
        ),
        Center(
          child: TextButton(
            onPressed: busy ? null : onChangeAddress,
            child: Text(
              'Change email',
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _HelpCard(),
      ],
    );
  }
}

/// The six boxes, one real field behind them.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.controller, required this.count});

  final TextEditingController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Same reason as the Verify button: the digits come from the controller,
    // and without listening to it the boxes stayed empty while the shopper
    // typed into them.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = controller.text;
        return Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < count; i++)
                  Container(
                    width: 46,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                      border: Border.all(
                        color: i < text.length
                            ? theme.colorScheme.primary.withValues(alpha: 0.55)
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      i < text.length ? text[i] : '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            Positioned.fill(
              child: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(count),
                ],
                showCursor: false,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  filled: false,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Panel three: done ───────────────────────────────────────────────────────

class _Done extends StatelessWidget {
  const _Done({required this.address, required this.onBack});

  final String address;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.successInk.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.successInk,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 34),
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Email Address Updated!',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your email address has been successfully verified and updated.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.35,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                ),
                child: Icon(
                  Icons.mail_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New email',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _PrimaryButton(label: 'Back to Profile', busy: false, onTap: onBack),
      ],
    );
  }
}

// ── Shared parts ────────────────────────────────────────────────────────────

/// Says, unmissably, that no server is checking anything.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.commerceOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(
          color: AppColors.commerceOrange.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.commerceOrange,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Demo mode — debug build only. No email is sent and no code is '
              'checked. Any 6 digits will pass, and your sign-in address is '
              'NOT changed.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: AppColors.commerceOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tinted envelope at the top of the first two panels.
class _Art extends StatelessWidget {
  const _Art({this.badge, this.code = false});

  final IconData? badge;
  final bool code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;

    return Center(
      child: SizedBox(
        width: 120,
        height: 104,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.08),
              ),
            ),
            Icon(Icons.mail_outline, size: 52, color: tint),
            if (code)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '∗∗∗',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: tint,
                  ),
                ),
              ),
            if (badge != null)
              Positioned(
                right: 12,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface,
                  ),
                  child: Icon(badge, size: 17, color: tint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: busy
            ? SizedBox(
                height: 19,
                width: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
            ),
            child: Icon(
              Icons.mail_outline,
              size: 17,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Didn't receive the code?",
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Check your email or request a new one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
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

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

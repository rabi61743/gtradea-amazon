import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../data/phone_number.dart';
import '../data/phone_repository.dart';
import '../data/phone_store.dart';
import '../data/profile_store.dart';

/// Changing the account's phone number, and proving it belongs to whoever
/// typed it.
///
/// Three panels on one route rather than three routes, because they are one
/// task and a back arrow in the middle of it should leave the task, not step
/// back into a code box for a number that has already been confirmed.
///
/// **Nothing here decides whether a number is verified.** The code is generated
/// by GoTrue and checked by GoTrue; this screen sends what was typed and reads
/// the answer. The clock is a courtesy -- the server expires a code whatever
/// this says -- and the resend wait is the server's own, taken off its refusal.
/// See [PhoneStore] and [PhoneRepository].
class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({super.key});

  /// Opens the flow and reports whether a number was actually confirmed, so
  /// the caller can refresh what it shows.
  static Future<bool> open(BuildContext context) async {
    PhoneStore.instance.reset();
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PhoneVerificationScreen()),
    );
    return done ?? false;
  }

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _store = PhoneStore.instance;
  final _number = TextEditingController();
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    // The store outlives this screen, and its countdown would outlive it too.
    _store.stopClocks();
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    await _store.sendCode('+977${_number.text}');
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    final ok = await _store.confirm(_code.text);
    if (ok) {
      // The settings page reads the profile row, which has just changed.
      await ProfileStore.instance.load(force: true);
    }
  }

  void _changeNumber() {
    _code.clear();
    _store.changeNumber();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = _store.stage;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: stage == PhoneVerificationStage.done
          // The success panel has no way back but its own button: a back arrow
          // there would return to a code box for a number already confirmed.
          ? null
          : AppBar(
              backgroundColor: theme.colorScheme.surfaceContainerLowest,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Text(
                stage == PhoneVerificationStage.entering
                    ? 'Change Phone Number'
                    : 'Verify Phone Number',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // A form, not a line of boxes stretched across a desktop window.
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (PhoneRepository.demoActive) const _DemoBanner(),
                  switch (stage) {
                    PhoneVerificationStage.entering => _EnterNumber(
                      controller: _number,
                      busy: _store.sending,
                      error: _store.error,
                      onSend: _send,
                      onCancel: () => Navigator.of(context).pop(false),
                    ),
                    PhoneVerificationStage.confirming => _EnterCode(
                      controller: _code,
                      number: _store.pending ?? '',
                      expiresIn: _store.expiresIn,
                      resendIn: _store.resendIn,
                      canResend: _store.canResend,
                      busy: _store.confirming,
                      sending: _store.sending,
                      error: _store.error,
                      onVerify: _verify,
                      onResend: _store.resend,
                      onChangeNumber: _changeNumber,
                    ),
                    PhoneVerificationStage.done => _Done(
                      number: _store.confirmed,
                      onBack: () => Navigator.of(context).pop(true),
                    ),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Panel one: the number ───────────────────────────────────────────────────

class _EnterNumber extends StatelessWidget {
  const _EnterNumber({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Enter your new phone number. We'll send you a verification code to "
          'confirm it.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.35,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 26),
        const _Art(icon: Icons.smartphone_outlined, badge: Icons.shield),
        const SizedBox(height: 30),
        Text(
          'New phone number',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            // Nepal only, and shown rather than offered: this shop delivers in
            // Nepal and a picker with one entry is a control that does nothing.
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Text(
                '🇳🇵  +977',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSend(),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: '9812345678',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          "We'll send a 6-digit OTP to this number.",
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (error != null) ...[const SizedBox(height: 12), _ErrorLine(error!)],
        const SizedBox(height: 26),
        _PrimaryButton(label: 'Send OTP', busy: busy, onTap: onSend),
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
    required this.number,
    required this.expiresIn,
    required this.resendIn,
    required this.canResend,
    required this.busy,
    required this.sending,
    required this.error,
    required this.onVerify,
    required this.onResend,
    required this.onChangeNumber,
  });

  final TextEditingController controller;
  final String number;
  final int expiresIn;
  final int resendIn;
  final bool canResend;
  final bool busy;
  final bool sending;
  final String? error;
  final VoidCallback onVerify;
  final Future<bool> Function() onResend;
  final VoidCallback onChangeNumber;

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
          PhoneNumber(e164: number).display,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 22),
        const _Art(icon: Icons.smartphone_outlined, code: true),
        const SizedBox(height: 26),
        _CodeBoxes(controller: controller, count: _digits),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            text: 'Code expires in ',
            children: [
              TextSpan(
                text: PhoneStore.clock(expiresIn),
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
        // button read the text once, at build, and then never again. It looked
        // like it worked only because the one-second clock was rebuilding the
        // screen underneath it -- so Verify lit up as much as a second late,
        // and not at all once that clock stopped.
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _PrimaryButton(
            label: 'Verify',
            busy: busy,
            // Off until there are six digits: a Verify that sends four is a
            // round trip whose answer was knowable here.
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
                    'Resend OTP in ${PhoneStore.clock(resendIn)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
        ),
        Center(
          child: TextButton(
            onPressed: busy ? null : onChangeNumber,
            child: Text(
              'Change number',
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

/// The six boxes.
///
/// One real field behind them rather than six: six fields mean six focus nodes,
/// and pasting a code from a message fills one box and drops five digits.
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
            // The field itself, invisible but real: it holds the value, takes the
            // keyboard and accepts a pasted code.
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
  const _Done({required this.number, required this.onBack});

  final PhoneNumber? number;
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
          'Phone Number Updated!',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your phone number has been successfully verified and updated.',
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
                  Icons.phone_outlined,
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
                      'New number',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      number?.display ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              // Shown only because the server said so: this comes from
              // GoTrue's phone_confirmed_at, not from having reached this
              // screen.
              if (number?.verified ?? false)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successInk.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 12,
                        color: AppColors.successInk,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Verified',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.successInk,
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

/// Says, unmissably, that no server is checking anything.
///
/// Drawn whenever [PhoneRepository.demoActive] is true, which can only happen
/// in a debug build. It exists so a walkthrough of these screens can never be
/// mistaken for a verification that took place.
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
              'Demo mode — debug build only. No SMS is sent and no code is '
              'checked. Any 6 digits will pass, and the number is saved '
              'WITHOUT being verified.',
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

// ── Shared parts ────────────────────────────────────────────────────────────

/// The tinted illustration at the top of the first two panels.
class _Art extends StatelessWidget {
  const _Art({required this.icon, this.badge, this.code = false});

  final IconData icon;
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
            Icon(icon, size: 52, color: tint),
            if (code)
              Text(
                '∗∗∗',
                style: TextStyle(
                  fontSize: 15,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: tint,
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

/// The full-width action on every panel.
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

/// The card at the foot of the code panel.
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
              Icons.phone_outlined,
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
                  'Check your SMS or request a new one.',
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

/// A refusal, in the server's own words, beside what it is about.
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

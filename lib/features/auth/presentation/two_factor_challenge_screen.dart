import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../security/presentation/totp_code_field.dart';
import '../data/auth_store.dart';

/// The second step of signing in to an account with two-factor
/// authentication: the password was right, and now the server wants the code
/// from the authenticator app.
///
/// Nothing is signed in while this is open. [AuthStore] holds the half-done
/// session in memory; this screen's only ways out are a code GoTrue accepts
/// ([AuthStore.completeMfa]) or giving up ([AuthStore.cancelMfa]), which ends
/// that session on the server as well. Popping it any other way -- the back
/// button -- cancels too.
class TwoFactorChallengeScreen extends StatefulWidget {
  const TwoFactorChallengeScreen({super.key, required this.email});

  final String email;

  /// Opens the challenge. Resolves true once the account is signed in, false
  /// when the person backed out (and the pending sign-in was abandoned).
  static Future<bool> open(BuildContext context, {required String email}) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TwoFactorChallengeScreen(email: email),
      ),
    );
    if (ok == true) return true;
    await AuthStore.instance.cancelMfa();
    return false;
  }

  @override
  State<TwoFactorChallengeScreen> createState() =>
      _TwoFactorChallengeScreenState();
}

class _TwoFactorChallengeScreenState extends State<TwoFactorChallengeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit([String? _]) async {
    final code = _code.text.trim();
    if (_busy) return;
    if (code.length != TotpCodeField.length) {
      setState(() => _error = 'Enter all 6 digits from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthStore.instance.completeMfa(code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      // The same code will not work twice; clear it so the next one is typed
      // fresh rather than edited.
      _code.clear();
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor verification')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.10,
                          ),
                        ),
                        child: Icon(
                          Icons.verified_user_outlined,
                          size: 34,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Enter your authenticator code',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open your authenticator app and enter the 6-digit code '
                      'for Gtradea${widget.email.isEmpty ? '' : ' (${widget.email})'}.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 24),
                    TotpCodeField(
                      controller: _code,
                      enabled: !_busy,
                      onCompleted: _submit,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
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
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel and use a different account'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Codes change every 30 seconds. If a code is rejected, '
                      'wait for the next one. Lost access to your authenticator '
                      'app? Contact support to recover your account.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
}

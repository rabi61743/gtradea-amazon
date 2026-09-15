import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_store.dart';
import 'oauth_webview_screen.dart';
import 'two_factor_challenge_screen.dart';

/// Signing in with an identity provider, and the buttons that start it.
///
/// One place for it because two screens offer it: the sign-in page and the
/// guest card on the account page. Copied, the two would drift on the thing
/// that matters least to look at and most to get right -- what counts as a
/// cancellation, and where the server's refusal is shown.

/// How a provider handshake ended.
enum ProviderSignInOutcome {
  signedIn,

  /// The shopper backed out of the provider's own page. Not a failure, and
  /// says nothing.
  cancelled,
  failed,
}

class ProviderSignInResult {
  const ProviderSignInResult(this.outcome, [this.message]);

  final ProviderSignInOutcome outcome;

  /// The server's own words, where there are any. Null unless [outcome] is
  /// [ProviderSignInOutcome.failed].
  final String? message;
}

/// Runs one provider handshake to its end.
///
/// The page is the provider's own, in a WebView; what comes back is the
/// redirect URL with the tokens in its fragment, which [AuthStore.completeOAuth]
/// turns into a session. Nothing here is provider-specific -- the server names
/// its providers and GoTrue speaks the same flow for each.
Future<ProviderSignInResult> startProviderSignIn(
  BuildContext context, {
  required String provider,
  required String label,
}) async {
  try {
    // Asked before the WebView opens. A provider the server has not switched
    // on answers /authorize with a bare 400 page, which is no way to learn it;
    // the banner, in words, is.
    final enabled = await AuthStore.instance.enabledProviders();
    if (!enabled.contains(provider)) {
      return ProviderSignInResult(
        ProviderSignInOutcome.failed,
        '$label sign-in is not available yet. Please use another sign-in '
        'option for now.',
      );
    }
    if (!context.mounted) {
      return const ProviderSignInResult(ProviderSignInOutcome.cancelled);
    }
    final returned = await OAuthWebViewScreen.show(
      context,
      title: 'Continue with $label',
      url: AuthStore.instance.authorizeUrl(provider),
    );
    if (returned == null) {
      return const ProviderSignInResult(ProviderSignInOutcome.cancelled);
    }
    try {
      await AuthStore.instance.completeOAuth(returned);
    } on MfaRequired catch (required) {
      // A provider proves who you are, not that you hold the authenticator.
      if (!context.mounted) {
        await AuthStore.instance.cancelMfa();
        return const ProviderSignInResult(ProviderSignInOutcome.cancelled);
      }
      final verified = await TwoFactorChallengeScreen.open(
        context,
        email: required.email,
      );
      if (!verified) {
        return const ProviderSignInResult(ProviderSignInOutcome.cancelled);
      }
    }
    return const ProviderSignInResult(ProviderSignInOutcome.signedIn);
  } on ApiError catch (e) {
    return ProviderSignInResult(ProviderSignInOutcome.failed, e.message);
  } catch (_) {
    return ProviderSignInResult(
      ProviderSignInOutcome.failed,
      '$label sign-in did not complete. Please try again.',
    );
  }
}

/// The shape every provider button takes, wherever it is drawn.
///
/// Shared so a second provider -- or a second screen -- cannot drift from the
/// first: the same height, the same corner as the card, the same hairline and
/// the same surface.
ButtonStyle providerButtonStyle(ThemeData theme) => OutlinedButton.styleFrom(
  minimumSize: const Size.fromHeight(54),
  backgroundColor: theme.colorScheme.surface,
  side: BorderSide(color: theme.dividerColor),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
  ),
);

/// The mark and the words, laid out the one way.
Widget _providerButtonLabel(ThemeData theme, Widget mark, String label) => Row(
  mainAxisAlignment: MainAxisAlignment.center,
  mainAxisSize: MainAxisSize.min,
  children: [
    mark,
    const SizedBox(width: 12),
    // Flexible, and allowed to scale down inside that. The label is a fixed
    // phrase in a button whose width is whatever is left after the padding of
    // whichever card it sits in, and inside one of them "Continue with Google"
    // overflowed the row by seventeen points. Giving up a fraction of a point
    // beats an overflow stripe, and it only happens where the width demands.
    Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    ),
  ],
);

/// The provider button, with Google's own mark on it.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onPressed,
      style: providerButtonStyle(theme),
      child: _providerButtonLabel(
        theme,
        SvgPicture.asset('assets/brand/google_g.svg', height: 22),
        'Continue with Google',
      ),
    );
  }
}

/// The same button, with Apple's mark.
///
/// The mark is Material's own glyph rather than a new asset: it is the Apple
/// logo, it inherits the card's ink so it reads in either theme, and adding a
/// brand file for one button would be a second place for it to go stale.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onPressed,
      style: providerButtonStyle(theme),
      child: _providerButtonLabel(
        theme,
        Icon(Icons.apple, size: 24, color: theme.colorScheme.onSurface),
        'Continue with Apple',
      ),
    );
  }
}

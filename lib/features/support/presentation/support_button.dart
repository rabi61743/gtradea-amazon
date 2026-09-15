import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/header_action_tile.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import 'support_tickets_screen.dart';

/// The messages tile in the home header, beside orders and notifications.
///
/// It has the cart's old place at the end of that group and is drawn by the
/// same [HeaderActionTile] the other two use, so its glyph, its word, its slot
/// and its tap target are theirs -- nothing about the row's metrics changes
/// with what sits in the third column.
///
/// The cart itself is unaffected. It is still on the bottom bar, still the same
/// [CartStore] count, and a shopper reaching for it has not lost a way in.
///
/// No badge. The bell and the tracker each badge a count they can actually
/// compute; the tickets endpoint gives no unread figure, and a dot invented
/// from nothing would be a claim that something is waiting when nobody knows.
class SupportButton extends StatelessWidget {
  const SupportButton({
    super.key,
    this.color = AppColors.onPrimary,
    this.size = 23,
    this.label = 'Messages',
    this.onOpened,
  });

  /// Pinned by the header, which draws this on the teal band where an
  /// inherited colour would vanish.
  final Color color;

  /// The glyph size. The header sets it from its own constant, which the
  /// header's right-hand inset is also derived from -- the two have to agree or
  /// the group drifts off its margin.
  final double size;

  /// The word under the glyph.
  final String label;

  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Rebuilt on sign-in so the tap goes to the conversations rather than to
      // the sign-in screen the moment there is an account behind it.
      listenable: AuthStore.instance,
      builder: (context, _) {
        return HeaderActionTile(
          icon: Icons.chat_bubble_outline,
          label: label,
          tooltip: 'Messages',
          color: color,
          iconSize: size,
          onTap: () {
            onOpened?.call();
            // The tickets endpoint answers 401 to a guest, so opening the list
            // would show them an error rather than a conversation. Same call
            // the orders tracker makes.
            final destination = AuthStore.instance.isSignedIn
                ? const SupportTicketsScreen()
                : const AuthScreen(initialMode: AuthMode.signIn);
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => destination));
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import 'support_tickets_screen.dart';

/// The chat icon in the home header.
///
/// Built to match [NotificationBell] and [OrderTrackerButton] beside it: an
/// IconButton with the same metrics, its own listener, and the same answer for
/// a guest. Three controls sharing a row that behaved differently would read as
/// three unrelated things.
///
/// No badge. The bell and the tracker each badge a count they can actually
/// compute; the tickets endpoint gives no unread figure, and a dot invented
/// from nothing would be a claim that something is waiting when nobody knows.
class SupportButton extends StatelessWidget {
  const SupportButton({super.key, this.color, this.size = 24, this.onOpened});

  /// Pinned by the header, which draws this on the teal band where an
  /// inherited colour would vanish.
  final Color? color;

  /// The glyph size. The header sets it from its own constant, which the
  /// header's right-hand inset is also derived from -- the two have to agree or
  /// the bell drifts off its margin.
  final double size;

  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        return IconButton(
          icon: Icon(Icons.chat_bubble_outline, size: size, color: color),
          tooltip: 'Messages',
          onPressed: () {
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

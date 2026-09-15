import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/address_store.dart';
import 'address_picker_sheet.dart';

/// "Deliver to Lalitpur, Nepal" in the home header.
///
/// The one place in the app that answers "where is this going" without opening
/// the cart. Reads the default address rather than the phone's GPS: what
/// matters is where the parcel is being sent, which is a decision the shopper
/// has made, not a place they happen to be standing.
///
/// Tapping opens the same picker the checkout uses, so there is one address
/// book and choosing here changes what checkout will use too.
class DeliveryLocationButton extends StatelessWidget {
  const DeliveryLocationButton({
    super.key,
    this.color = AppColors.onPrimary,
    this.compact = false,
  });

  final Color color;

  /// Names the city rather than the whole line.
  ///
  /// For the header row when it is also carrying a coin balance: there is not
  /// room for "Jawalakhel, Lalitpur, Bagmati" beside one, and a line
  /// ellipsised to "Jawalakhel, La..." says less than the city alone does.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: AddressStore.instance,
      builder: (context, _) {
        final address = AddressStore.instance.defaultAddress;
        // Never a guess. With no address saved this asks for one rather than
        // naming a city nobody chose.
        final label = address?.oneLine ?? 'Set delivery location';
        final known = address != null;

        return Semantics(
          button: true,
          label: known
              ? 'Delivering to ${address.oneLine}. Change delivery location.'
              : 'Set delivery location',
          excludeSemantics: true,
          // Carries its own Material rather than relying on finding one above.
          // The header is the only caller today, and it happens to sit inside a
          // Scaffold -- but a widget whose ripple depends on where somebody
          // puts it is a widget that throws the first time it moves.
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pick(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 17 to 15, with the chevron below coming down by the same
                    // step. Shrinking only the pin would leave the arrow at the
                    // other end of the control looking oversized, and the two
                    // are read as one thing.
                    Icon(Icons.location_on_outlined, size: 15, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Only when there is a place to name. "Deliver to" over
                          // "Set delivery location" would be two prompts stacked.
                          if (known)
                            Text(
                              'Deliver to',
                              maxLines: 1,
                              // Squeezed as this line gets on a phone, the
                              // label has to be able to give way like the
                              // place name under it does.
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: color.withValues(alpha: 0.75),
                                height: 1.1,
                              ),
                            ),
                          Text(
                            // The fullest form that fits. On a phone the
                            // header row also carries a coin balance and three
                            // labelled actions, and "Jawalakhel, Lalitpur,
                            // Bagmati" ellipsised to "Jawalakhel, La..." says
                            // less than the city on its own does. Measured
                            // rather than guessed at, so a wide screen still
                            // gets the whole line.
                            compact && known ? address.city : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              // A point under labelLarge's 14. Sized here
                              // rather than by dropping to labelMedium, which
                              // is 12 and a visible step down rather than the
                              // slight one asked for.
                              //
                              // One size for both states on purpose: this is
                              // the same control whether it reads "Set delivery
                              // location" or "Lalitpur, Nepal", and two sizes
                              // would make it look like it changes shape when
                              // an address is saved.
                              fontSize: 14,
                              color: color,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // The arrow goes when the line is down to a city: at that
                    // width those twelve points are worth more to the name of
                    // the place, and the whole control is still the button it
                    // always was.
                    if (!compact) ...[
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down, size: 12, color: color),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pick(BuildContext context) async {
    final store = AddressStore.instance;
    await store.load();
    if (!context.mounted) return;

    final chosen = await AddressPickerSheet.show(
      context,
      selectedId: store.defaultAddress?.id,
    );
    if (chosen == null) return;
    // Picking here sets the default, which is what makes the header's answer
    // and the checkout's agree.
    store.setDefault(chosen.id);
  }
}

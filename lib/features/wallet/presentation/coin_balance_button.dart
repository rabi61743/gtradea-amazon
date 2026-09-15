import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../home/widgets/product_rail.dart'
    show formatGrouped, formatRupees;
import '../data/coin_balance_store.dart';
import 'wallet_screen.dart';

/// The coin balance in the home header, beside the delivery address.
///
/// The figure is the account's own, read from `GET /wallet` by
/// [CoinBalanceStore] -- the same endpoint and the same balance
/// [WalletScreen] shows, which is where tapping this goes. There is no second
/// copy of the number and nothing cached behind the shopper's back.
///
/// **Nothing at all until there is something true to say.** A guest has no
/// balance, an unfinished request has no figure yet, and a failed one has no
/// figure at all -- in each of those this draws nothing and, because the store
/// says so before the row is built, takes none of the row's width either.
///
/// It reloads when the account changes, when the app comes back to the
/// foreground, and when the shopper returns from the wallet -- the three
/// moments the balance can have moved while this was on screen.
class CoinBalanceButton extends StatefulWidget {
  const CoinBalanceButton({
    super.key,
    this.color = AppColors.onPrimary,
    this.withLeadingDivider = false,
    this.compact = false,
  });

  final Color color;

  /// Draws the hairline that separates this from the delivery line beside it.
  ///
  /// It belongs to the chip rather than to the header because the chip is the
  /// half that can be absent: a divider drawn by the row would be left hanging
  /// beside nothing for a guest.
  final bool withLeadingDivider;

  /// Drops the caption and the chevron, for a row that has an address to fit
  /// beside this. The figure and the coin stay, which is the whole of what the
  /// chip is for.
  final bool compact;

  @override
  State<CoinBalanceButton> createState() => _CoinBalanceButtonState();
}

class _CoinBalanceButtonState extends State<CoinBalanceButton>
    with WidgetsBindingObserver {
  CoinBalanceStore get _store => CoinBalanceStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No load here. This is only built once there is a balance, so the fetch
    // belongs to the shell that asks for one -- and a store that notified
    // from inside this initState would mark the row around it dirty during
    // its own first build.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _store.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        // Never null: the store falls back rather than going quiet, so the
        // chip always has a figure. See CoinBalanceStore.balance.
        final balance = _store.balance;

        final theme = Theme.of(context);

        final chip = Semantics(
          button: true,
          // The same words the chip draws. It read "Rs. 1,000" to a screen
          // reader while the chip showed "1,000" -- announcing coins as
          // rupees, and for a figure that is not money.
          label: widget.compact
              ? 'Coins balance ${formatGrouped(balance)}. Open your coins.'
              : 'Coins balance ${formatRupees(balance)}. Open your coins.',
          excludeSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _open,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The coin, in the amber the wallet screen already uses
                    // for it, so the two read as the same thing.
                    const Icon(
                      Icons.monetization_on,
                      size: 16,
                      color: Color(0xFFF5B301),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            // The bare figure in the header row, where the
                            // coin beside it already says what it counts and
                            // an address has to fit alongside: "Rs. 1,000"
                            // ellipsised to "Rs. 1,..." and took the address
                            // down to a single letter. The wallet screen this
                            // opens still prints the full formatting.
                            widget.compact
                                ? formatGrouped(balance)
                                : formatRupees(balance),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 16,
                              color: widget.color,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          // The caption goes when the row is tight. The figure
                          // and the coin beside it already say what this is,
                          // and the word costs the delivery address the room
                          // it needs to name a place.
                          if (!widget.compact)
                            Text(
                              'Coins',
                              maxLines: 1,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                                color: widget.color.withValues(alpha: 0.75),
                                height: 1.1,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!widget.compact) ...[
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 14, color: widget.color),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );

        // Capped, and the address beside it keeps the rest: a long balance
        // takes the ellipsis rather than the place someone lives.
        final sized = ConstrainedBox(
          // Narrow in the header row, where an address has to fit beside it.
          constraints: BoxConstraints(maxWidth: widget.compact ? 88 : 120),
          child: chip,
        );

        if (!widget.withLeadingDivider) return sized;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 1,
              height: 22,
              // Tighter in the header row. The rule and its margins are the
              // one part of this chip that cannot shrink -- `sized` is
              // Flexible, this is not -- so on a 320pt phone those twelve
              // points of margin were the whole of a one-pixel overflow, and
              // no amount of shortening the figure could reach them.
              margin: EdgeInsets.symmetric(horizontal: widget.compact ? 3 : 6),
              color: widget.color.withValues(alpha: 0.28),
            ),
            Flexible(child: sized),
          ],
        );
      },
    );
  }

  Future<void> _open() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WalletScreen()));
    // Coins can have been spent or refunded in there.
    if (mounted) await _store.load();
  }
}

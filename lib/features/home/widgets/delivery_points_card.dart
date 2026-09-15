import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../address/data/address_store.dart';
import '../../address/presentation/address_picker_sheet.dart';
import '../../tour/data/tour_step.dart';
import '../../wallet/data/coin_balance_store.dart';
import '../../wallet/presentation/wallet_screen.dart';
import 'product_rail.dart' show formatGrouped;

/// "Deliver to Jawalakhel, Lalitpur | 2,450 Points" -- the header card from
/// the reference: one dark rounded card, the delivery address on the left and
/// the points balance on the right, split by a thin rule.
///
/// Nothing here is new data. The address is the default delivery address
/// ([AddressStore]) and tapping it opens the same picker the old header chip
/// did; the figure is the account's real balance from `GET /wallet`
/// ([CoinBalanceStore]) and tapping it opens the wallet. "Points" and the "P"
/// coin are this card's wording only -- the wallet page still says coins.
///
/// It shares its row with the Orders / Messages / Notifications group, so on
/// a phone it has a little over half the header. Below [denseBelow] it draws
/// its dense metrics -- tighter padding, slightly smaller glyphs, and the
/// icon group's height -- and keeps the reference's layout; on a tablet or
/// desktop it draws the reference's full size.
class DeliveryPointsCard extends StatelessWidget {
  const DeliveryPointsCard({super.key});

  static const _coinGold = Color(0xFFF5B301);

  static const radius = 14.0;

  /// Card width under which the dense metrics are used.
  static const denseBelow = 360.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = constraints.maxWidth < denseBelow
            ? _Metrics.dense
            : _Metrics.regular;
        return ListenableBuilder(
          listenable: Listenable.merge([
            AddressStore.instance,
            CoinBalanceStore.instance,
          ]),
          builder: (context, _) {
            return Container(
              constraints: BoxConstraints(minHeight: m.minHeight),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                // 14, the header blocks' own radius. 16 is the band's corner,
                // and a card inside the band does not borrow it.
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Row(
                  children: [
                    Expanded(
                      child: _DeliveryHalf(m: m, onTap: () => _pick(context)),
                    ),
                    Container(
                      width: 1,
                      height: m.dividerHeight,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    // Its natural width, capped at 45% of the card and scaled
                    // down beyond that -- so a large text setting or a narrow
                    // phone shrinks the points rather than overflowing the row.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.45,
                      ),
                      child: _PointsHalf(
                        // The real balance is what the coins tour step rings.
                        key: TourAnchors.instance.keyOf(TourAnchor.coins),
                        m: m,
                        onTap: () => _openWallet(context),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The same picker the header's address chip always opened.
  static Future<void> _pick(BuildContext context) async {
    final store = AddressStore.instance;
    await store.load();
    if (!context.mounted) return;
    final chosen = await AddressPickerSheet.show(
      context,
      selectedId: store.defaultAddress?.id,
    );
    if (chosen == null) return;
    store.setDefault(chosen.id);
  }

  static Future<void> _openWallet(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WalletScreen()));
    // Points can have been spent or refunded in there.
    await CoinBalanceStore.instance.load();
  }

  /// "Jawalakhel, Lalitpur": the neighbourhood from the area line, then the
  /// city.
  ///
  /// The area line comes in two orders. Typed by hand it leads with the place
  /// ("Jawalakhel, house 12"); filled by the location detector it leads with
  /// the province and postcode ("Bagmati Province 44600, Ekantakuna"). So the
  /// neighbourhood is the first part that is not the province, a postcode or
  /// the city -- taking the first part blindly put "Bagmati Provin..." in the
  /// header on a real device.
  ///
  /// [withCity] false gives the neighbourhood alone -- the dense phone layout,
  /// where "Ekantakuna, Lalitpur" cut to "Ekant..." beside the icon section.
  /// With no neighbourhood the city stands in, so it is never blank.
  @visibleForTesting
  static String? placeOf(Address? address, {bool withCity = true}) {
    if (address == null) return null;
    final city = address.city.trim();
    final province = address.province.trim().toLowerCase();
    bool isPlace(String part) {
      final lower = part.toLowerCase();
      if (part.isEmpty) return false;
      if (RegExp(r'^[\d\s-]+$').hasMatch(part)) return false; // a postcode
      if (lower.contains('province')) return false;
      if (province.isNotEmpty && lower == province) return false;
      if (city.isNotEmpty && lower == city.toLowerCase()) return false;
      return true;
    }

    final neighbourhood = address.area
        .split(',')
        .map((part) => part.trim())
        .firstWhere(isPlace, orElse: () => '');
    if (!withCity && neighbourhood.isNotEmpty) return neighbourhood;
    final parts = [neighbourhood, city].where((p) => p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// The card's sizes: the reference's own, and a dense set for when it shares
/// a phone's header row with the icon group.
class _Metrics {
  const _Metrics({
    required this.minHeight,
    required this.padding,
    required this.pin,
    required this.pinGap,
    required this.chevron,
    required this.coin,
    required this.label,
    required this.value,
    required this.figure,
    required this.dividerHeight,
    required this.chevrons,
    required this.placeWithCity,
  });

  final double minHeight;
  final EdgeInsets padding;
  final double pin;
  final double pinGap;
  final double chevron;
  final double coin;
  final double label;
  final double value;
  final double figure;
  final double dividerHeight;

  /// The ⌄ and › glyphs. Both halves stay tappable without them; on a phone
  /// their 36 points go to the address instead.
  final bool chevrons;

  /// "Ekantakuna, Lalitpur" rather than "Ekantakuna".
  final bool placeWithCity;

  static const regular = _Metrics(
    minHeight: 56,
    padding: EdgeInsets.fromLTRB(14, 9, 10, 9),
    pin: 22,
    pinGap: 10,
    chevron: 22,
    coin: 30,
    label: 12.5,
    value: 15.5,
    figure: 17,
    dividerHeight: 34,
    chevrons: true,
    placeWithCity: true,
  );

  /// 42 tall, the icon group's own floor, so the two sit level.
  static const dense = _Metrics(
    minHeight: 42,
    padding: EdgeInsets.fromLTRB(8, 4, 4, 4),
    pin: 18,
    pinGap: 5,
    chevron: 18,
    coin: 24,
    label: 11,
    value: 13.5,
    figure: 15,
    dividerHeight: 28,
    // Beside the icon section a phone leaves the address about 90 points:
    // enough for "Deliver to" and a neighbourhood, not for the city and two
    // arrows as well.
    chevrons: false,
    placeWithCity: false,
  );
}

class _DeliveryHalf extends StatelessWidget {
  const _DeliveryHalf({required this.m, required this.onTap});

  final _Metrics m;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = AddressStore.instance.defaultAddress;
    final place = DeliveryPointsCard.placeOf(
      address,
      withCity: m.placeWithCity,
    );
    // The screen reader always hears the whole place, dense or not.
    final spoken = DeliveryPointsCard.placeOf(address);

    return Semantics(
      button: true,
      label: spoken == null
          ? 'Set delivery location'
          : 'Delivering to $spoken. Change delivery location.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(DeliveryPointsCard.radius),
        ),
        child: Padding(
          padding: m.padding,
          child: Row(
            children: [
              // Under 24: the header keeps its glyphs below Material's default.
              Icon(Icons.location_on, size: m.pin, color: AppColors.onPrimary),
              SizedBox(width: m.pinGap),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deliver to',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: m.label,
                        height: 1.15,
                        color: AppColors.onPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      place ?? 'Set delivery location',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: m.value,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (m.chevrons) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: m.chevron,
                  color: AppColors.onPrimary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsHalf extends StatelessWidget {
  const _PointsHalf({super.key, required this.m, required this.onTap});

  final _Metrics m;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final figure = formatGrouped(CoinBalanceStore.instance.balance);

    return Semantics(
      button: true,
      label: 'Points balance $figure. Open your points.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(DeliveryPointsCard.radius),
        ),
        child: Padding(
          padding: m.padding,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PCoin(size: m.coin),
                SizedBox(width: m.pinGap),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      figure,
                      maxLines: 1,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: m.figure,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onPrimary,
                      ),
                    ),
                    Text(
                      'Points',
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: m.label,
                        height: 1.15,
                        color: AppColors.onPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                if (m.chevrons) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right,
                    size: m.chevron,
                    color: AppColors.onPrimary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The reference's gold coin with a "P" on it.
class _PCoin extends StatelessWidget {
  const _PCoin({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DeliveryPointsCard._coinGold,
        border: Border.all(color: const Color(0xFFD99A00), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        'P',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

import '../../catalog/data/catalog_repository.dart';
import 'deal_pricing.dart';
import 'flash_sale.dart';
import 'flash_sale_placeholder.dart' as placeholder;

/// Where a flash sale comes from.
///
/// There is no `/flash-sales` endpoint, so this assembles one from the two
/// things the server does have: the promo fields on a hero banner, which are
/// the backend's own idea of a time-limited offer, and the discover feed, which
/// is real products at real prices. Everything neither of those can answer
/// comes from [placeholder], and the sale is marked as such.
///
/// See `docs/flash-sales-api.md` for the endpoint this would rather be reading.
class FlashSaleRepository {
  FlashSaleRepository._();

  static final FlashSaleRepository instance = FlashSaleRepository._();

  /// How many products the section shows.
  ///
  /// Four, which is two rows on a phone. The home page is a queue of sections
  /// and this one sits near the top; a sale that takes three screens to scroll
  /// past stops being a highlight and starts being the page.
  static const itemCount = 4;

  /// How many rows to ask for to end up with [itemCount] usable ones.
  ///
  /// Roughly half the discover feed has no price -- the catalogue carries rows
  /// whose pricing has not been worked out yet, and those cannot be a deal
  /// because there is nothing to discount. Asking for exactly four returned
  /// two, and the section rendered a half-empty row.
  static const _fetchSize = 16;

  /// The sale on now, or null when there is not one.
  Future<FlashSale?> current() async {
    final banners = await CatalogRepository.instance.heroBanners();
    final now = DateTime.now();

    // A real one: a banner whose promo has an end date still in the future.
    // `heroBanners` already drops expired banners, so anything with a
    // validUntil here is live.
    final promo = _firstPromo(banners, now);

    if (promo == null && !placeholder.enabled) return null;

    final endsAt = promo?.validUntil ?? placeholder.windowEnd(now);
    if (!endsAt.isAfter(now)) return null;

    final products = await CatalogRepository.instance.discover(
      pageSize: _fetchSize,
    );
    final sellable = products
        .where((p) => p.hasPrice)
        .take(itemCount)
        .toList(growable: false);
    if (sellable.isEmpty) return null;

    return FlashSale(
      id: promo?.id ?? 'placeholder-${endsAt.toIso8601String()}',
      headline: 'Dashain Specials',
      subhead: 'Unbeatable deals. Limited stock. Hurry up!',
      endsAt: endsAt,
      discountPercent: promo?.headlinePercent,
      promoCode: promo?.promoCode,
      isPlaceholder: promo == null,
      items: [
        for (final product in sellable)
          dealPricing(product, headlinePercent: promo?.headlinePercent),
      ],
    );
  }

  static HeroBanner? _firstPromo(List<HeroBanner> banners, DateTime now) {
    for (final banner in banners) {
      final until = banner.validUntil;
      if (until != null && until.isAfter(now)) return banner;
    }
    return null;
  }
}

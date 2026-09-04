import 'package:flutter/material.dart';

/// The promotional block under the flash sale: four category banners, the
/// delivery banner, and the offers strip that closes it.
///
/// All six are supplied artwork. Nothing is drawn over them -- each picture
/// carries its own headline, strapline and "Shop now", and a caption laid on
/// top would either repeat what the picture says or fight it for the space.
/// That is also why this file has almost no styling left in it: the design is
/// in the images, and the code's job is to place them, size them and route
/// their taps.
class PromoSection extends StatelessWidget {
  const PromoSection({
    super.key,
    required this.onFreeDelivery,
    required this.onElectronics,
    required this.onFurniture,
    required this.onToys,
    required this.onKitchen,
    required this.onOffers,
    required this.onWomen,
    required this.onAppliances,
    required this.onSports,
    required this.onPackaging,
    required this.onCamping,
    required this.onMen,
    required this.onFootwear,
    required this.onTools,
    required this.onBaby,
    required this.onBeauty,
    required this.onTrending,
    required this.onBathroom,
    required this.onCleaning,
    required this.onLighting,
    required this.onSafety,
    required this.onSchool,
    required this.onPets,
    required this.onIndustrial,
    required this.onAgriculture,
    required this.onElectrical,
    required this.onMachinery,
    required this.onTextiles,
    required this.onBags,
    required this.onDecor,
    required this.onOutdoorLiving,
    required this.onCorporateGifts,
    this.threshold,
  });

  /// Opens the free-delivery collection.
  final VoidCallback onFreeDelivery;

  /// Opens the Digital, Computer department.
  final VoidCallback onElectronics;

  /// Opens the Home Textile Furniture department.
  final VoidCallback onFurniture;

  /// Opens the Toys department.
  final VoidCallback onToys;

  /// Opens the Daily Dining Kitchen Utensils department.
  final VoidCallback onKitchen;

  /// Opens the deals page, which is where the shop's discounted items are.
  final VoidCallback onOffers;

  /// Opens the Women department.
  final VoidCallback onWomen;

  /// Opens the Home appliance department.
  final VoidCallback onAppliances;

  /// Opens the Sports Outdoors department.
  final VoidCallback onSports;

  /// Opens the Packaging department.
  final VoidCallback onPackaging;

  /// Opens the Mountain, Camping Supplies category.
  final VoidCallback onCamping;

  /// Opens the Men department.
  final VoidCallback onMen;

  /// Opens the Footwear department.
  final VoidCallback onFootwear;

  /// Opens the Hardware, tools department.
  final VoidCallback onTools;

  /// Opens the Maternal and Infant Supplies department.
  final VoidCallback onBaby;

  /// Opens the Beauty Skincare/Makeup department.
  final VoidCallback onBeauty;

  /// Opens the catalogue ordered by what is selling.
  final VoidCallback onTrending;

  /// Opens the Bathroom fixtures category.
  final VoidCallback onBathroom;

  /// Opens the Organize cleaning supplies category.
  final VoidCallback onCleaning;

  /// Opens the Lighting department.
  final VoidCallback onLighting;

  /// Opens the Safety, protection department.
  final VoidCallback onSafety;

  /// Opens the Learn stationery category.
  final VoidCallback onSchool;

  /// Opens the Pets & Supplies category.
  final VoidCallback onPets;

  /// Opens the Machinery and industry equipment department.
  final VoidCallback onIndustrial;

  /// Opens the Agriculture department.
  final VoidCallback onAgriculture;

  /// Opens the Electrician Electrical department.
  final VoidCallback onElectrical;

  /// Opens the Machine tools department.
  final VoidCallback onMachinery;

  /// Opens the Textiles, Leathers department.
  final VoidCallback onTextiles;

  /// Opens the Bags & Leather department.
  final VoidCallback onBags;

  /// Opens the Creative Ornaments category.
  final VoidCallback onDecor;

  /// Opens the Garden materials category.
  final VoidCallback onOutdoorLiving;

  /// Opens the Corporate Gifts collection.
  final VoidCallback onCorporateGifts;

  /// The order value above which delivery is free, when the shop has set one.
  ///
  /// Null is the live state: `site_settings.free_delivery_threshold` is unset,
  /// so no such promise can be made. Not drawn -- the artwork states the offer
  /// -- but it is what a screen reader is told, where the picture says nothing.
  final num? threshold;

  static const _radius = 16.0;
  static const _gap = 14.0;

  /// One shape for all four category tiles.
  ///
  /// The supplied files differ a little -- 1.16 to 1.28 -- and a grid whose
  /// tiles are each their own shape reads as a mistake. They are drawn to one
  /// ratio and cropped to fill it, which costs at most a few percent off the
  /// long edge of the widest and leaves every headline and button intact.
  static const _tileRatio = 1.22;

  /// The delivery banner's own proportions, 1529 x 756.
  static const _bannerRatio = 1529 / 756;

  /// The offers strip's own proportions, 1409 x 340. Much wider than the rest,
  /// which is what it was drawn as -- held to, so it is never squashed into
  /// the shape of the banner above it.
  static const _offersRatio = 1409 / 340;

  /// The packaging banner, 1369 x 916.
  static const _packagingRatio = 1369 / 916;

  /// The tent and outdoor banner, 1369 x 899.
  static const _campingRatio = 1369 / 899;

  /// The Women banner, 645 x 1570. A tall portrait picture, which is what
  /// decides the shape of the trio below the delivery banner.
  static const _womenRatio = 645 / 1570;

  /// The two stacked banners, 1372 x 881 and 1372 x 865. Within one percent of
  /// each other, so they share a ratio and stay the same height as each other
  /// -- which is what the layout asks for.
  static const _stackedRatio = 1372 / 873;

  /// The Men banner, 652 x 1570 -- the same tall portrait shape the Women one
  /// is, which is why the two trios can be mirror images.
  static const _menRatio = 652 / 1570;

  /// Footwear and Tools, 1123 x 1334 and 1122 x 1335. Portrait, unlike the
  /// pair beside the Women banner, so this trio is taller than that one.
  static const _menStackedRatio = 1123 / 1334;

  /// Baby & Mom and Beauty & Care, both 1122 x 1335 to the pixel. Sharing a
  /// ratio is what makes the pair the same height on any width -- equal
  /// columns of the same shape cannot come out different sizes.
  static const _pairRatio = 1122 / 1335;

  /// The trending banner, 1122 x 1335 -- the same shape as the pair above it,
  /// drawn across the full width rather than half of it.
  static const _trendingRatio = 1122 / 1335;

  /// The corporate gifts banner, 1151 x 1366 -- its own file, uncropped, so
  /// the Shop now button it carries is not trimmed off an edge.
  static const _corporateRatio = 1151 / 1366;

  /// The flash sale card's lift, so the block under it sits on the page the
  /// same way rather than inventing a second kind of shadow: a close tighter
  /// layer for the contact edge, and a wider fainter one for the diffusion
  /// falling away from it, both down and a little right as if the light were
  /// above and to the left.
  static const _lift = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(2, 3)),
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 24,
      // Pulled in, so the far layer reads as a soft halo under the card
      // rather than a second edge around it.
      spreadRadius: -10,
      offset: Offset(4, 8),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        // Stretch, not the default centre, so the banner spans the same width
        // as the grid above it.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/electronics.jpg',
                  label: 'Electronics. Smarter, faster, better.',
                  ratio: _tileRatio,
                  onTap: onElectronics,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/furniture.jpg',
                  label: 'Furniture for every space.',
                  ratio: _tileRatio,
                  onTap: onFurniture,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/kids_toys.jpg',
                  label: 'Kids toys. Play, learn, grow.',
                  ratio: _tileRatio,
                  onTap: onToys,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/kitchen.jpg',
                  label: 'Kitchen essentials.',
                  ratio: _tileRatio,
                  onTap: onKitchen,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          // Under the four tiles rather than over them. The tiles are the
          // section: this is the promise that closes it.
          _Banner(
            asset: 'assets/images/delivery_banner.jpg',
            label: threshold == null
                ? 'Free delivery. On selected products'
                : 'Free delivery. On orders above Rs. ${threshold!.round()}',
            ratio: _bannerRatio,
            onTap: onFreeDelivery,
          ),
          const SizedBox(height: _gap),
          _BannerTrio(
            gap: _gap,
            tallOnLeft: false,
            tallRatio: _womenRatio,
            stackedRatio: _stackedRatio,
            tall: _Art(
              asset: 'assets/images/women.jpg',
              label: 'Women. Style that speaks you.',
              onTap: onWomen,
            ),
            stacked: [
              _Art(
                asset: 'assets/images/home_appliances.jpg',
                label: 'Home appliances.',
                onTap: onAppliances,
              ),
              _Art(
                asset: 'assets/images/sports_fitness.jpg',
                label: 'Sports and fitness.',
                onTap: onSports,
              ),
            ],
          ),
          const SizedBox(height: _gap),
          // The same arrangement mirrored: the tall one takes the left, the
          // stacked pair the right.
          _BannerTrio(
            gap: _gap,
            tallOnLeft: true,
            tallRatio: _menRatio,
            stackedRatio: _menStackedRatio,
            tall: _Art(
              asset: 'assets/images/mens_style.jpg',
              label: "Men's style. Confident, timeless, you.",
              onTap: onMen,
            ),
            stacked: [
              _Art(
                asset: 'assets/images/footwear.jpg',
                label: 'Footwear. Step up, stand out, go anywhere.',
                onTap: onFootwear,
              ),
              _Art(
                asset: 'assets/images/tools_hardware.jpg',
                label: 'Tools and hardware. Built for work, made to last.',
                onTap: onTools,
              ),
            ],
          ),
          const SizedBox(height: _gap),
          // Side by side, sharing the row evenly. Expanded rather than a fixed
          // width, so the pair follows whatever the page is given -- phone,
          // tablet or a desktop window.
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/baby_mom.jpg',
                  label: 'Baby and mom. For every little moment of love.',
                  ratio: _pairRatio,
                  onTap: onBaby,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/beauty_care.jpg',
                  label: 'Beauty and care. Confidence, radiance, everyday.',
                  ratio: _pairRatio,
                  onTap: onBeauty,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          _Banner(
            asset: 'assets/images/trending_now.jpg',
            label: 'Trending now.',
            ratio: _trendingRatio,
            onTap: onTrending,
          ),
          const SizedBox(height: _gap),
          // Two by two, the same arrangement the four tiles at the top of this
          // section use. All four files are within a fifth of a percent of one
          // ratio, so equal columns give equal cards without forcing a height.
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/bathroom.jpg',
                  label: 'Bathroom.',
                  ratio: _pairRatio,
                  onTap: onBathroom,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/clean_home.jpg',
                  label: 'Clean home. A clean home is a happy home.',
                  ratio: _pairRatio,
                  onTap: onCleaning,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/lights_lamps.jpg',
                  label: 'Lights and lamps.',
                  ratio: _pairRatio,
                  onTap: onLighting,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/safety_security.jpg',
                  label: 'Safety and security.',
                  ratio: _pairRatio,
                  onTap: onSafety,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/school_stationery.jpg',
                  label:
                      'School and stationery. Write, learn, create, '
                      'every day.',
                  ratio: _pairRatio,
                  onTap: onSchool,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/pet_world.jpg',
                  label: 'Pet world. Happy pets, better life.',
                  ratio: _pairRatio,
                  onTap: onPets,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          _Banner(
            asset: 'assets/images/packaging.jpg',
            label: 'Packaging materials. Protect, seal, ship, deliver.',
            ratio: _packagingRatio,
            onTap: onPackaging,
          ),
          const SizedBox(height: _gap),
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/textiles_fabrics.jpg',
                  label:
                      'Textiles and fabrics. Premium quality, timeless '
                      'comfort, endless possibilities.',
                  ratio: _pairRatio,
                  onTap: onTextiles,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/bags_wallets.jpg',
                  label:
                      'Bags and wallets. Style you carry, confidence you '
                      'keep.',
                  ratio: _pairRatio,
                  onTap: onBags,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          _Banner(
            asset: 'assets/images/promo_banner.jpg',
            label:
                'Limited time offer. 20% sale on selected items. '
                'Explore to find your surprise.',
            ratio: _offersRatio,
            onTap: onOffers,
          ),
          const SizedBox(height: _gap),
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/home_decor.jpg',
                  label: 'Home decor. Beautiful spaces, inspired living.',
                  ratio: _pairRatio,
                  onTap: onDecor,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/outdoor_living.jpg',
                  label: 'Outdoor living. Live outside, love outside.',
                  ratio: _pairRatio,
                  onTap: onOutdoorLiving,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          _Banner(
            asset: 'assets/images/tent_outdoor.jpg',
            label: 'Tent and outdoor accessories.',
            ratio: _campingRatio,
            onTap: onCamping,
          ),
          const SizedBox(height: _gap),
          // The trade half of the catalogue, closing the section the way it
          // opened: two by two, all four the same shape.
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/industrial_supplies.jpg',
                  label: 'Industrial supplies.',
                  ratio: _pairRatio,
                  onTap: onIndustrial,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/agri_farming.jpg',
                  label: 'Agriculture and farming.',
                  ratio: _pairRatio,
                  onTap: onAgriculture,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          Row(
            children: [
              Expanded(
                child: _Banner(
                  asset: 'assets/images/electrical_supplies.jpg',
                  label: 'Electrical supplies.',
                  ratio: _pairRatio,
                  onTap: onElectrical,
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _Banner(
                  asset: 'assets/images/machinery_equipment.jpg',
                  label:
                      'Machinery and equipment. Built strong, engineered '
                      'precise, ready for more.',
                  ratio: _pairRatio,
                  onTap: onMachinery,
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          // Its own destination rather than a category: a collection the shop
          // curates, like Free Delivery at the top of this section.
          _Banner(
            asset: 'assets/images/corporate_gifts.jpg',
            label: 'Corporate gifts. Shop now.',
            ratio: _corporateRatio,
            onTap: onCorporateGifts,
          ),
        ],
      ),
    );
  }
}

/// Two stacked banners on the left, one tall one on the right.
///
/// The three are laid out so that **no picture is cropped or stretched**: the
/// column widths are solved from the artwork's own proportions rather than
/// picked, which is the only way three fixed-ratio pictures can fill one row
/// and still line up top and bottom.
///
/// Solving it, with a the width available, g the gap, s the stacked
/// banners' ratio and w the Women banner's -- the row is full, and both
/// columns are the same height:
///
///     left + g + right = a
///     right / w = 2 * (left / s) + g
///
/// which gives left = (a - g * (1 + w)) / (1 + 2 * w / s).
///
/// **On the 2:1 rule.** The brief asks for the tall banner to be exactly twice
/// each small one *and* for the columns to line up. Both cannot hold at once
/// once there is a gap between the stacked pair -- the tall one has to cover
/// that gap as well. The columns line up, which is what the diagram shows and
/// what the eye checks; the tall banner is therefore twice a small one plus
/// the 14pt gap.
class _BannerTrio extends StatelessWidget {
  const _BannerTrio({
    required this.gap,
    required this.tall,
    required this.tallRatio,
    required this.stacked,
    required this.stackedRatio,
    required this.tallOnLeft,
  });

  final double gap;

  /// The one that spans both rows, and the pair beside it.
  final _Art tall;
  final List<_Art> stacked;

  final double tallRatio;
  final double stackedRatio;

  /// Which side the tall one takes. The Women trio puts it right; the Men
  /// trio mirrors that.
  final bool tallOnLeft;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = tallRatio;
        final s = stackedRatio;

        // The stacked column's width, from the two rules above.
        final narrow = (constraints.maxWidth - gap * (1 + w)) / (1 + 2 * w / s);
        final stackedHeight = narrow / s;

        final column = SizedBox(
          width: narrow,
          child: Column(
            children: [
              SizedBox(
                height: stackedHeight,
                child: _Banner(
                  asset: stacked.first.asset,
                  label: stacked.first.label,
                  ratio: s,
                  onTap: stacked.first.onTap,
                ),
              ),
              SizedBox(height: gap),
              SizedBox(
                height: stackedHeight,
                child: _Banner(
                  asset: stacked.last.asset,
                  label: stacked.last.label,
                  ratio: s,
                  onTap: stacked.last.onTap,
                ),
              ),
            ],
          ),
        );

        final big = Expanded(
          child: SizedBox(
            // The two stacked banners and the gap between them, so the
            // columns end level.
            height: stackedHeight * 2 + gap,
            child: _Banner(
              asset: tall.asset,
              label: tall.label,
              ratio: w,
              onTap: tall.onTap,
            ),
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: tallOnLeft
              ? [big, SizedBox(width: gap), column]
              : [column, SizedBox(width: gap), big],
        );
      },
    );
  }
}

/// One supplied picture and where it leads.
class _Art {
  const _Art({required this.asset, required this.label, required this.onTap});

  final String asset;
  final String label;
  final VoidCallback onTap;
}

/// One piece of supplied artwork, as a card that opens something.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.asset,
    required this.label,
    required this.ratio,
    required this.onTap,
  });

  final String asset;

  /// What the picture says, for a screen reader, which cannot see it.
  final String label;

  final double ratio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // Outside the Material, which clips: a shadow drawn inside would be cut
      // off at the very edge it is meant to fall past.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PromoSection._radius),
        boxShadow: PromoSection._lift,
      ),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(PromoSection._radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // The whole banner is the target, which is what a shopper expects
            // of a promotional tile.
            onTap: onTap,
            child: AspectRatio(
              aspectRatio: ratio,
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                // Sized to what it is drawn at rather than decoded at full
                // width for a slot a third of that: this sits on the home
                // page, which is already the heaviest screen in the app for
                // image memory.
                cacheWidth:
                    (MediaQuery.of(context).size.width *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
                errorBuilder: (context, _, _) => const ColoredBox(
                  // A file that will not decode must not leave a hole where a
                  // tappable card was: the tile still reads as a panel and
                  // still opens what it opens.
                  color: Color(0xFFF1F3F5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

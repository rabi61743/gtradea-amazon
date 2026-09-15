import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/home/widgets/promo_section.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    num? threshold,
    VoidCallback? onFree,
    VoidCallback? onElectronics,
    VoidCallback? onFurniture,
    VoidCallback? onToys,
    VoidCallback? onKitchen,
    VoidCallback? onOffers,
    VoidCallback? onWomen,
    VoidCallback? onAppliances,
    VoidCallback? onSports,
    VoidCallback? onPackaging,
    VoidCallback? onCamping,
    VoidCallback? onMen,
    VoidCallback? onFootwear,
    VoidCallback? onTools,
    VoidCallback? onBaby,
    VoidCallback? onBeauty,
    VoidCallback? onTrending,
    VoidCallback? onBathroom,
    VoidCallback? onCleaning,
    VoidCallback? onLighting,
    VoidCallback? onSafety,
    VoidCallback? onSchool,
    VoidCallback? onPets,
    VoidCallback? onIndustrial,
    VoidCallback? onAgriculture,
    VoidCallback? onElectrical,
    VoidCallback? onMachinery,
    VoidCallback? onTextiles,
    VoidCallback? onBags,
    VoidCallback? onDecor,
    VoidCallback? onOutdoorLiving,
    VoidCallback? onCorporateGifts,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PromoSection(
              threshold: threshold,
              onFreeDelivery: onFree ?? () {},
              onElectronics: onElectronics ?? () {},
              onFurniture: onFurniture ?? () {},
              onToys: onToys ?? () {},
              onKitchen: onKitchen ?? () {},
              onOffers: onOffers ?? () {},
              onWomen: onWomen ?? () {},
              onAppliances: onAppliances ?? () {},
              onSports: onSports ?? () {},
              onPackaging: onPackaging ?? () {},
              onCamping: onCamping ?? () {},
              onMen: onMen ?? () {},
              onFootwear: onFootwear ?? () {},
              onTools: onTools ?? () {},
              onBaby: onBaby ?? () {},
              onBeauty: onBeauty ?? () {},
              onTrending: onTrending ?? () {},
              onBathroom: onBathroom ?? () {},
              onCleaning: onCleaning ?? () {},
              onLighting: onLighting ?? () {},
              onSafety: onSafety ?? () {},
              onSchool: onSchool ?? () {},
              onPets: onPets ?? () {},
              onIndustrial: onIndustrial ?? () {},
              onAgriculture: onAgriculture ?? () {},
              onElectrical: onElectrical ?? () {},
              onMachinery: onMachinery ?? () {},
              onTextiles: onTextiles ?? () {},
              onBags: onBags ?? () {},
              onDecor: onDecor ?? () {},
              onOutdoorLiving: onOutdoorLiving ?? () {},
              onCorporateGifts: onCorporateGifts ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The asset each banner draws, in the order they are laid out.
  List<String> assets(WidgetTester tester) => tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => (image.image as ResizeImage).imageProvider)
      .whereType<AssetImage>()
      .map((asset) => asset.assetName)
      .toList(growable: false);

  group('the section is the supplied artwork', () {
    testWidgets('twenty-one banners, in the order they were given', (
      tester,
    ) async {
      await pump(tester);

      expect(assets(tester), [
        'assets/images/electronics.jpg',
        'assets/images/furniture.jpg',
        'assets/images/kids_toys.jpg',
        'assets/images/kitchen.jpg',
        'assets/images/delivery_banner.jpg',
        'assets/images/home_appliances.jpg',
        'assets/images/sports_fitness.jpg',
        'assets/images/women.jpg',
        'assets/images/mens_style.jpg',
        'assets/images/footwear.jpg',
        'assets/images/tools_hardware.jpg',
        'assets/images/baby_mom.jpg',
        'assets/images/beauty_care.jpg',
        'assets/images/trending_now.jpg',
        'assets/images/bathroom.jpg',
        'assets/images/clean_home.jpg',
        'assets/images/lights_lamps.jpg',
        'assets/images/safety_security.jpg',
        'assets/images/school_stationery.jpg',
        'assets/images/pet_world.jpg',
        'assets/images/packaging.jpg',
        'assets/images/textiles_fabrics.jpg',
        'assets/images/bags_wallets.jpg',
        'assets/images/promo_banner.jpg',
        'assets/images/home_decor.jpg',
        'assets/images/outdoor_living.jpg',
        'assets/images/tent_outdoor.jpg',
        'assets/images/industrial_supplies.jpg',
        'assets/images/agri_farming.jpg',
        'assets/images/electrical_supplies.jpg',
        'assets/images/machinery_equipment.jpg',
        'assets/images/corporate_gifts.jpg',
      ]);
    });

    testWidgets('and nothing is drawn over them', (tester) async {
      // Each picture carries its own headline, strapline and Shop now. A
      // caption on top would repeat the picture or fight it for the space.
      await pump(tester);

      expect(find.byType(Text), findsNothing);
    });
  });

  group('how they are laid out', () {
    testWidgets('two by two, with the delivery banner closing it', (
      tester,
    ) async {
      await pump(tester);

      final rects = tester
          .widgetList<Image>(find.byType(Image))
          .toList(growable: false)
          .asMap()
          .entries
          .map((e) => tester.getRect(find.byType(Image).at(e.key)))
          .toList(growable: false);

      final [electronics, furniture, toys, kitchen, delivery, ...rest] = rects;
      final offers = rest.last;

      expect(furniture.left, greaterThan(electronics.right), reason: 'beside');
      expect(toys.top, greaterThan(electronics.bottom), reason: 'second row');
      expect(kitchen.left, greaterThan(toys.right), reason: 'beside');
      expect(toys.left, electronics.left, reason: 'the columns line up');
      expect(delivery.top, greaterThan(toys.bottom), reason: 'under the grid');
      expect(
        offers.top,
        greaterThan(delivery.bottom),
        reason: 'the offers strip sits directly below free delivery',
      );
    });

    testWidgets('the four tiles are all one size', (tester) async {
      // The supplied files are each a slightly different shape. A grid whose
      // tiles are each their own shape reads as a mistake.
      await pump(tester);

      final sizes = [
        for (var i = 0; i < 4; i++) tester.getSize(find.byType(Image).at(i)),
      ];

      expect(sizes[1], sizes[0]);
      expect(sizes[2], sizes[0]);
      expect(sizes[3], sizes[0]);
    });

    testWidgets('and the wide banners span both columns', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));

      for (final index in [4, 13, 20, 23, 26]) {
        final wide = tester.getRect(find.byType(Image).at(index));
        expect(wide.left, electronics.left);
        expect(wide.right, kitchen.right);
      }
    });

    testWidgets('the offers strip keeps its own shape', (tester) async {
      // It was drawn much wider than the delivery banner. Forcing it into the
      // same box would squash the artwork.
      await pump(tester);

      final delivery = tester.getRect(find.byType(Image).at(4));
      final offers = tester.getRect(find.byType(Image).at(23));

      expect(offers.width, delivery.width, reason: 'same width');
      expect(
        offers.height,
        lessThan(delivery.height),
        reason: 'and shorter, because it is a wider picture',
      );
      expect(
        offers.width / offers.height,
        closeTo(1409 / 340, 0.01),
        reason: 'its own aspect ratio, undistorted',
      );
    });

    testWidgets('every one carries the flash sale card lift', (tester) async {
      await pump(tester);

      final lifts = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => (box.decoration as BoxDecoration).boxShadow)
          .whereType<List<BoxShadow>>()
          .where((shadows) => shadows.isNotEmpty)
          .toList();

      expect(lifts, hasLength(32));
      for (final shadow in lifts) {
        expect(shadow, hasLength(2));
        expect(shadow.first.color, const Color(0x14000000));
        expect(shadow.last.spreadRadius, -10);
      }
    });
  });

  group('the trio below the delivery banner', () {
    /// appliances, sports, women -- in the order they are laid out.
    ({Rect appliances, Rect sports, Rect women}) trio(WidgetTester tester) => (
      appliances: tester.getRect(find.byType(Image).at(5)),
      sports: tester.getRect(find.byType(Image).at(6)),
      women: tester.getRect(find.byType(Image).at(7)),
    );

    testWidgets('sits directly below the delivery banner', (tester) async {
      await pump(tester);

      final delivery = tester.getRect(find.byType(Image).at(4));
      final group = trio(tester);

      expect(group.appliances.top, greaterThan(delivery.bottom));
      expect(
        tester.getRect(find.byType(Image).at(20)).top,
        greaterThan(group.sports.bottom),
        reason: 'and the packaging banner follows it',
      );
    });

    testWidgets('two stacked on the left, the tall one on the right', (
      tester,
    ) async {
      await pump(tester);
      final group = trio(tester);

      expect(group.sports.top, greaterThan(group.appliances.bottom));
      expect(group.appliances.left, group.sports.left, reason: 'one column');
      expect(group.women.left, greaterThan(group.appliances.right));
    });

    testWidgets('the two stacked ones are the same height', (tester) async {
      await pump(tester);
      final group = trio(tester);

      expect(group.sports.height, closeTo(group.appliances.height, 0.5));
      expect(group.sports.width, closeTo(group.appliances.width, 0.5));
    });

    testWidgets('the columns start and end level', (tester) async {
      // What the diagram is actually asking for.
      await pump(tester);
      final group = trio(tester);

      expect(group.women.top, closeTo(group.appliances.top, 0.5));
      expect(group.women.bottom, closeTo(group.sports.bottom, 0.5));
    });

    testWidgets('the tall one is twice a small one, plus the gap', (
      tester,
    ) async {
      // Exactly twice and level columns cannot both hold once there is a gap
      // between the stacked pair: the tall banner has to span it too.
      await pump(tester);
      final group = trio(tester);

      // The section's own gap, not a copy of it. This assertion carried the
      // literal 14 and broke the moment the spacing was tightened -- which is
      // the wrong kind of failure: the identity still held, only the number
      // had moved.
      expect(
        group.women.height,
        closeTo(group.appliances.height * 2 + PromoSection.gap, 0.5),
      );
    });

    testWidgets('and not one of the three is distorted', (tester) async {
      // The column widths are solved from the artwork's own proportions, so
      // every picture is drawn at the shape it was made in.
      await pump(tester);
      final group = trio(tester);

      expect(
        group.appliances.width / group.appliances.height,
        closeTo(1372 / 873, 0.01),
      );
      expect(
        group.sports.width / group.sports.height,
        closeTo(1372 / 873, 0.01),
      );
      expect(group.women.width / group.women.height, closeTo(645 / 1570, 0.01));
    });
  });

  group('the Men trio below the Women one', () {
    /// men, footwear, tools -- in the order they are laid out.
    ({Rect men, Rect footwear, Rect tools}) trio(WidgetTester tester) => (
      men: tester.getRect(find.byType(Image).at(8)),
      footwear: tester.getRect(find.byType(Image).at(9)),
      tools: tester.getRect(find.byType(Image).at(10)),
    );

    testWidgets('sits directly below the Women trio', (tester) async {
      await pump(tester);

      final women = tester.getRect(find.byType(Image).at(7));
      final group = trio(tester);

      expect(group.men.top, greaterThan(women.bottom));
    });

    testWidgets('mirrors it: the tall one on the left', (tester) async {
      // The Women trio stacks on the left and puts its tall banner right.
      await pump(tester);
      final group = trio(tester);

      expect(group.footwear.left, greaterThan(group.men.right));
      expect(group.tools.left, group.footwear.left, reason: 'one column');
      expect(group.tools.top, greaterThan(group.footwear.bottom));
    });

    testWidgets('the stacked pair are the same size', (tester) async {
      await pump(tester);
      final group = trio(tester);

      expect(group.tools.height, closeTo(group.footwear.height, 0.5));
      expect(group.tools.width, closeTo(group.footwear.width, 0.5));
    });

    testWidgets('the columns start and end level', (tester) async {
      await pump(tester);
      final group = trio(tester);

      expect(group.men.top, closeTo(group.footwear.top, 0.5));
      expect(group.men.bottom, closeTo(group.tools.bottom, 0.5));
    });

    testWidgets('the tall one is twice a small one, plus the gap', (
      tester,
    ) async {
      await pump(tester);
      final group = trio(tester);

      expect(
        group.men.height,
        closeTo(group.footwear.height * 2 + PromoSection.gap, 0.5),
      );
    });

    testWidgets('and none of the three is distorted', (tester) async {
      await pump(tester);
      final group = trio(tester);

      expect(group.men.width / group.men.height, closeTo(652 / 1570, 0.01));
      expect(
        group.footwear.width / group.footwear.height,
        closeTo(1123 / 1334, 0.01),
      );
      expect(
        group.tools.width / group.tools.height,
        closeTo(1123 / 1334, 0.01),
      );
    });
  });

  group('the pair below the Men trio', () {
    testWidgets('sits directly below it, side by side', (tester) async {
      await pump(tester);

      final tools = tester.getRect(find.byType(Image).at(10));
      final baby = tester.getRect(find.byType(Image).at(11));
      final beauty = tester.getRect(find.byType(Image).at(12));

      expect(baby.top, greaterThan(tools.bottom));
      expect(beauty.left, greaterThan(baby.right), reason: 'beside it');
      expect(beauty.top, closeTo(baby.top, 0.5), reason: 'and level');
    });

    testWidgets('they share the row evenly', (tester) async {
      await pump(tester);

      final baby = tester.getRect(find.byType(Image).at(11));
      final beauty = tester.getRect(find.byType(Image).at(12));

      expect(beauty.width, closeTo(baby.width, 0.5));
      expect(beauty.height, closeTo(baby.height, 0.5));
    });

    testWidgets('spanning the same margins as everything else', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final baby = tester.getRect(find.byType(Image).at(11));
      final beauty = tester.getRect(find.byType(Image).at(12));

      expect(baby.left, electronics.left);
      expect(beauty.right, kitchen.right);
    });

    testWidgets('and neither is distorted', (tester) async {
      await pump(tester);

      for (final index in [11, 12]) {
        final rect = tester.getRect(find.byType(Image).at(index));
        expect(rect.width / rect.height, closeTo(1122 / 1335, 0.01));
      }
    });
  });

  group('the trending banner', () {
    testWidgets('sits directly below Beauty and Care, full width', (
      tester,
    ) async {
      await pump(tester);

      final beauty = tester.getRect(find.byType(Image).at(12));
      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final trending = tester.getRect(find.byType(Image).at(13));

      expect(trending.top, greaterThan(beauty.bottom));
      expect(trending.left, electronics.left);
      expect(trending.right, kitchen.right);
    });

    testWidgets('and is not distorted', (tester) async {
      await pump(tester);

      final trending = tester.getRect(find.byType(Image).at(13));
      expect(trending.width / trending.height, closeTo(1122 / 1335, 0.01));
    });
  });

  group('the four cards below Trending Now', () {
    /// bathroom, clean home, lights, safety -- in layout order.
    List<Rect> quad(WidgetTester tester) => [
      for (var i = 14; i <= 17; i++) tester.getRect(find.byType(Image).at(i)),
    ];

    testWidgets('sit below it, two by two', (tester) async {
      await pump(tester);

      final trending = tester.getRect(find.byType(Image).at(13));
      final [bath, clean, lights, safety] = quad(tester);

      expect(bath.top, greaterThan(trending.bottom));
      expect(clean.left, greaterThan(bath.right), reason: 'first row');
      expect(lights.top, greaterThan(bath.bottom), reason: 'second row');
      expect(safety.left, greaterThan(lights.right));
      expect(lights.left, bath.left, reason: 'the columns line up');
    });

    testWidgets('all four are the same size', (tester) async {
      await pump(tester);
      final cards = quad(tester);

      for (final card in cards.skip(1)) {
        expect(card.width, closeTo(cards.first.width, 0.5));
        expect(card.height, closeTo(cards.first.height, 0.5));
      }
    });

    testWidgets('spanning the section margins', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final cards = quad(tester);

      expect(cards[0].left, electronics.left);
      expect(cards[1].right, kitchen.right);
      expect(cards[2].left, electronics.left);
      expect(cards[3].right, kitchen.right);
    });

    testWidgets('and none is distorted', (tester) async {
      await pump(tester);

      for (final card in quad(tester)) {
        expect(card.width / card.height, closeTo(1122 / 1335, 0.01));
      }
    });
  });

  group('the pair below the four cards', () {
    testWidgets('sits between them and the packaging banner', (tester) async {
      await pump(tester);

      final lights = tester.getRect(find.byType(Image).at(16));
      final safety = tester.getRect(find.byType(Image).at(17));
      final school = tester.getRect(find.byType(Image).at(18));
      final pets = tester.getRect(find.byType(Image).at(19));
      final packaging = tester.getRect(find.byType(Image).at(20));

      expect(school.top, greaterThan(lights.bottom));
      expect(pets.left, greaterThan(school.right), reason: 'side by side');
      expect(packaging.top, greaterThan(school.bottom));
      expect(school.left, lights.left, reason: 'the columns line up');
      expect(pets.right, safety.right);
    });

    testWidgets('both cards are the same size', (tester) async {
      await pump(tester);

      final school = tester.getRect(find.byType(Image).at(18));
      final pets = tester.getRect(find.byType(Image).at(19));

      expect(pets.width, closeTo(school.width, 0.5));
      expect(pets.height, closeTo(school.height, 0.5));
      expect(pets.top, closeTo(school.top, 0.5), reason: 'level');
    });

    testWidgets('spanning the section margins, undistorted', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final school = tester.getRect(find.byType(Image).at(18));
      final pets = tester.getRect(find.byType(Image).at(19));

      expect(school.left, electronics.left);
      expect(pets.right, kitchen.right);
      expect(school.width / school.height, closeTo(1122 / 1335, 0.01));
      expect(pets.width / pets.height, closeTo(1122 / 1335, 0.01));
    });

    testWidgets('with the same gap between them as the rows above', (
      tester,
    ) async {
      await pump(tester);

      final lights = tester.getRect(find.byType(Image).at(16));
      final safety = tester.getRect(find.byType(Image).at(17));
      final school = tester.getRect(find.byType(Image).at(18));
      final pets = tester.getRect(find.byType(Image).at(19));

      expect(
        pets.left - school.right,
        closeTo(safety.left - lights.right, 0.5),
      );
    });
  });

  group('the packaging banner', () {
    testWidgets('sits between the trio and the offers strip', (tester) async {
      await pump(tester);

      final sports = tester.getRect(find.byType(Image).at(6));
      final packaging = tester.getRect(find.byType(Image).at(20));
      final offers = tester.getRect(find.byType(Image).at(23));

      expect(packaging.top, greaterThan(sports.bottom));
      expect(offers.top, greaterThan(packaging.bottom));
    });

    testWidgets('full width, and its own shape', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final packaging = tester.getRect(find.byType(Image).at(20));

      expect(packaging.left, electronics.left);
      expect(packaging.right, kitchen.right);
      expect(
        packaging.width / packaging.height,
        closeTo(1369 / 916, 0.01),
        reason: 'undistorted',
      );
    });
  });

  group('the pair below the packaging banner', () {
    testWidgets('sits between it and the offers strip', (tester) async {
      await pump(tester);

      final packaging = tester.getRect(find.byType(Image).at(20));
      final textiles = tester.getRect(find.byType(Image).at(21));
      final bags = tester.getRect(find.byType(Image).at(22));
      final offers = tester.getRect(find.byType(Image).at(23));

      expect(textiles.top, greaterThan(packaging.bottom));
      expect(bags.left, greaterThan(textiles.right), reason: 'side by side');
      expect(offers.top, greaterThan(textiles.bottom));
    });

    testWidgets('both cards are the same size, level', (tester) async {
      await pump(tester);

      final textiles = tester.getRect(find.byType(Image).at(21));
      final bags = tester.getRect(find.byType(Image).at(22));

      expect(bags.width, closeTo(textiles.width, 0.5));
      expect(bags.height, closeTo(textiles.height, 0.5));
      expect(bags.top, closeTo(textiles.top, 0.5));
    });

    testWidgets('spanning the section margins, undistorted', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final furniture = tester.getRect(find.byType(Image).at(1));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final textiles = tester.getRect(find.byType(Image).at(21));
      final bags = tester.getRect(find.byType(Image).at(22));

      expect(textiles.left, electronics.left);
      expect(bags.right, kitchen.right);
      expect(
        bags.left - textiles.right,
        closeTo(furniture.left - electronics.right, 0.5),
        reason: 'the same gap as the rest of the section',
      );
      expect(textiles.width / textiles.height, closeTo(1122 / 1335, 0.01));
      expect(bags.width / bags.height, closeTo(1122 / 1335, 0.01));
    });
  });

  group('the pair below the offers strip', () {
    testWidgets('sits between it and the tent banner', (tester) async {
      await pump(tester);

      final offers = tester.getRect(find.byType(Image).at(23));
      final decor = tester.getRect(find.byType(Image).at(24));
      final outdoor = tester.getRect(find.byType(Image).at(25));
      final tent = tester.getRect(find.byType(Image).at(26));

      expect(decor.top, greaterThan(offers.bottom));
      expect(outdoor.left, greaterThan(decor.right), reason: 'side by side');
      expect(tent.top, greaterThan(decor.bottom));
    });

    testWidgets('both cards are the same size, level', (tester) async {
      await pump(tester);

      final decor = tester.getRect(find.byType(Image).at(24));
      final outdoor = tester.getRect(find.byType(Image).at(25));

      expect(outdoor.width, closeTo(decor.width, 0.5));
      expect(outdoor.height, closeTo(decor.height, 0.5));
      expect(outdoor.top, closeTo(decor.top, 0.5));
    });

    testWidgets('spanning the section margins, undistorted', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final furniture = tester.getRect(find.byType(Image).at(1));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final decor = tester.getRect(find.byType(Image).at(24));
      final outdoor = tester.getRect(find.byType(Image).at(25));

      expect(decor.left, electronics.left);
      expect(outdoor.right, kitchen.right);
      expect(
        outdoor.left - decor.right,
        closeTo(furniture.left - electronics.right, 0.5),
        reason: 'the same gap as the rest of the section',
      );
      expect(decor.width / decor.height, closeTo(1122 / 1335, 0.01));
      expect(outdoor.width / outdoor.height, closeTo(1122 / 1335, 0.01));
    });
  });

  group('the tent and outdoor banner', () {
    testWidgets('sits below the offers strip', (tester) async {
      await pump(tester);

      final offers = tester.getRect(find.byType(Image).at(23));
      final tent = tester.getRect(find.byType(Image).at(26));

      expect(tent.top, greaterThan(offers.bottom));
    });

    testWidgets('full width, and its own shape', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final tent = tester.getRect(find.byType(Image).at(26));

      expect(tent.left, electronics.left);
      expect(tent.right, kitchen.right);
      expect(
        tent.width / tent.height,
        closeTo(1369 / 899, 0.01),
        reason: 'undistorted',
      );
    });
  });

  group('the four cards below the tent banner', () {
    /// industrial, agriculture, electrical, machinery -- in layout order.
    List<Rect> quad(WidgetTester tester) => [
      for (var i = 27; i <= 30; i++) tester.getRect(find.byType(Image).at(i)),
    ];

    testWidgets('close the section, two by two', (tester) async {
      await pump(tester);

      final tent = tester.getRect(find.byType(Image).at(26));
      final [industrial, agri, electrical, machinery] = quad(tester);

      expect(industrial.top, greaterThan(tent.bottom));
      expect(agri.left, greaterThan(industrial.right), reason: 'first row');
      expect(
        electrical.top,
        greaterThan(industrial.bottom),
        reason: 'second row',
      );
      expect(machinery.left, greaterThan(electrical.right));
      expect(electrical.left, industrial.left, reason: 'the columns line up');
      expect(
        tester.widgetList<Image>(find.byType(Image)).length,
        32,
        reason: 'only the corporate gifts banner follows them',
      );
    });

    testWidgets('all four are the same size', (tester) async {
      await pump(tester);
      final cards = quad(tester);

      for (final card in cards.skip(1)) {
        expect(card.width, closeTo(cards.first.width, 0.5));
        expect(card.height, closeTo(cards.first.height, 0.5));
      }
      expect(cards[1].top, closeTo(cards[0].top, 0.5), reason: 'level');
      expect(cards[3].top, closeTo(cards[2].top, 0.5), reason: 'level');
    });

    testWidgets('spanning the section margins, undistorted', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final cards = quad(tester);

      expect(cards[0].left, electronics.left);
      expect(cards[1].right, kitchen.right);
      expect(cards[2].left, electronics.left);
      expect(cards[3].right, kitchen.right);
      for (final card in cards) {
        expect(card.width / card.height, closeTo(1122 / 1335, 0.01));
      }
    });

    testWidgets('with the same gaps as the rest of the section', (
      tester,
    ) async {
      await pump(tester);

      final cards = quad(tester);
      final electronics = tester.getRect(find.byType(Image).at(0));
      final furniture = tester.getRect(find.byType(Image).at(1));
      final gap = furniture.left - electronics.right;

      expect(cards[1].left - cards[0].right, closeTo(gap, 0.5));
      expect(cards[3].left - cards[2].right, closeTo(gap, 0.5));
      expect(cards[2].top - cards[0].bottom, closeTo(gap, 0.5));
    });
  });

  group('the corporate gifts banner', () {
    testWidgets('closes the section, below the four trade cards', (
      tester,
    ) async {
      await pump(tester);

      final machinery = tester.getRect(find.byType(Image).at(30));
      final gifts = tester.getRect(find.byType(Image).at(31));

      expect(gifts.top, greaterThan(machinery.bottom));
      expect(
        tester.widgetList<Image>(find.byType(Image)).length,
        32,
        reason: 'nothing follows it',
      );
    });

    testWidgets('full width, and its own shape', (tester) async {
      await pump(tester);

      final electronics = tester.getRect(find.byType(Image).at(0));
      final kitchen = tester.getRect(find.byType(Image).at(3));
      final gifts = tester.getRect(find.byType(Image).at(31));

      expect(gifts.left, electronics.left);
      expect(gifts.right, kitchen.right);
      expect(
        gifts.width / gifts.height,
        closeTo(1151 / 1366, 0.01),
        reason: 'undistorted',
      );
    });
  });

  group('every banner opens what it advertises', () {
    Future<void> tapBanner(WidgetTester tester, int index) async {
      await tester.ensureVisible(find.byType(Image).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image).at(index));
      await tester.pump();
    }

    testWidgets('electronics', (tester) async {
      var opened = 0;
      await pump(tester, onElectronics: () => opened++);

      await tapBanner(tester, 0);

      expect(opened, 1);
    });

    testWidgets('furniture', (tester) async {
      var opened = 0;
      await pump(tester, onFurniture: () => opened++);

      await tapBanner(tester, 1);

      expect(opened, 1);
    });

    testWidgets('toys', (tester) async {
      var opened = 0;
      await pump(tester, onToys: () => opened++);

      await tapBanner(tester, 2);

      expect(opened, 1);
    });

    testWidgets('kitchen', (tester) async {
      var opened = 0;
      await pump(tester, onKitchen: () => opened++);

      await tapBanner(tester, 3);

      expect(opened, 1);
    });

    testWidgets('free delivery', (tester) async {
      var opened = 0;
      await pump(tester, onFree: () => opened++);

      await tapBanner(tester, 4);

      expect(
        opened,
        1,
        reason: 'the whole banner opens it, not one corner of it',
      );
    });

    testWidgets('home appliances', (tester) async {
      var opened = 0;
      await pump(tester, onAppliances: () => opened++);

      await tapBanner(tester, 5);

      expect(opened, 1);
    });

    testWidgets('sports and fitness', (tester) async {
      var opened = 0;
      await pump(tester, onSports: () => opened++);

      await tapBanner(tester, 6);

      expect(opened, 1);
    });

    testWidgets('women', (tester) async {
      var opened = 0;
      await pump(tester, onWomen: () => opened++);

      await tapBanner(tester, 7);

      expect(opened, 1);
    });

    testWidgets('men', (tester) async {
      var opened = 0;
      await pump(tester, onMen: () => opened++);

      await tapBanner(tester, 8);

      expect(opened, 1);
    });

    testWidgets('footwear', (tester) async {
      var opened = 0;
      await pump(tester, onFootwear: () => opened++);

      await tapBanner(tester, 9);

      expect(opened, 1);
    });

    testWidgets('tools and hardware', (tester) async {
      var opened = 0;
      await pump(tester, onTools: () => opened++);

      await tapBanner(tester, 10);

      expect(opened, 1);
    });

    testWidgets('baby and mom', (tester) async {
      var opened = 0;
      await pump(tester, onBaby: () => opened++);

      await tapBanner(tester, 11);

      expect(opened, 1);
    });

    testWidgets('beauty and care', (tester) async {
      var opened = 0;
      await pump(tester, onBeauty: () => opened++);

      await tapBanner(tester, 12);

      expect(opened, 1);
    });

    testWidgets('trending now', (tester) async {
      var opened = 0;
      await pump(tester, onTrending: () => opened++);

      await tapBanner(tester, 13);

      expect(opened, 1);
    });

    testWidgets('bathroom', (tester) async {
      var opened = 0;
      await pump(tester, onBathroom: () => opened++);
      await tapBanner(tester, 14);
      expect(opened, 1);
    });

    testWidgets('clean home', (tester) async {
      var opened = 0;
      await pump(tester, onCleaning: () => opened++);
      await tapBanner(tester, 15);
      expect(opened, 1);
    });

    testWidgets('lights and lamps', (tester) async {
      var opened = 0;
      await pump(tester, onLighting: () => opened++);
      await tapBanner(tester, 16);
      expect(opened, 1);
    });

    testWidgets('safety and security', (tester) async {
      var opened = 0;
      await pump(tester, onSafety: () => opened++);
      await tapBanner(tester, 17);
      expect(opened, 1);
    });

    testWidgets('school and stationery', (tester) async {
      var opened = 0;
      await pump(tester, onSchool: () => opened++);
      await tapBanner(tester, 18);
      expect(opened, 1);
    });

    testWidgets('pet world', (tester) async {
      var opened = 0;
      await pump(tester, onPets: () => opened++);
      await tapBanner(tester, 19);
      expect(opened, 1);
    });

    testWidgets('packaging', (tester) async {
      var opened = 0;
      await pump(tester, onPackaging: () => opened++);

      await tapBanner(tester, 20);

      expect(opened, 1);
    });

    testWidgets('textiles and fabrics', (tester) async {
      var opened = 0;
      await pump(tester, onTextiles: () => opened++);
      await tapBanner(tester, 21);
      expect(opened, 1);
    });

    testWidgets('bags and wallets', (tester) async {
      var opened = 0;
      await pump(tester, onBags: () => opened++);
      await tapBanner(tester, 22);
      expect(opened, 1);
    });

    testWidgets('the offers strip', (tester) async {
      var opened = 0;
      await pump(tester, onOffers: () => opened++);

      await tapBanner(tester, 23);

      expect(opened, 1);
    });

    testWidgets('home decor', (tester) async {
      var opened = 0;
      await pump(tester, onDecor: () => opened++);
      await tapBanner(tester, 24);
      expect(opened, 1);
    });

    testWidgets('outdoor living', (tester) async {
      var opened = 0;
      await pump(tester, onOutdoorLiving: () => opened++);
      await tapBanner(tester, 25);
      expect(opened, 1);
    });

    testWidgets('industrial supplies', (tester) async {
      var opened = 0;
      await pump(tester, onIndustrial: () => opened++);
      await tapBanner(tester, 27);
      expect(opened, 1);
    });

    testWidgets('agriculture and farming', (tester) async {
      var opened = 0;
      await pump(tester, onAgriculture: () => opened++);
      await tapBanner(tester, 28);
      expect(opened, 1);
    });

    testWidgets('electrical supplies', (tester) async {
      var opened = 0;
      await pump(tester, onElectrical: () => opened++);
      await tapBanner(tester, 29);
      expect(opened, 1);
    });

    testWidgets('machinery and equipment', (tester) async {
      var opened = 0;
      await pump(tester, onMachinery: () => opened++);
      await tapBanner(tester, 30);
      expect(opened, 1);
    });

    testWidgets('corporate gifts', (tester) async {
      var opened = 0;
      await pump(tester, onCorporateGifts: () => opened++);
      await tapBanner(tester, 31);
      expect(opened, 1);
    });

    testWidgets('and tent and outdoor', (tester) async {
      var opened = 0;
      await pump(tester, onCamping: () => opened++);

      await tapBanner(tester, 26);

      expect(opened, 1);
    });
  });

  group('what a screen reader is told', () {
    testWidgets('each banner says what its picture says', (tester) async {
      // The artwork is the whole message, and a screen reader cannot see it.
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        find.bySemanticsLabel('Electronics. Smarter, faster, better.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Furniture for every space.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Kids toys. Play, learn, grow.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Kitchen essentials.'), findsOneWidget);
      expect(find.bySemanticsLabel('Home appliances.'), findsOneWidget);
      expect(find.bySemanticsLabel('Sports and fitness.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Women. Style that speaks you.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Packaging materials. Protect, seal, ship, deliver.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Tent and outdoor accessories.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Limited time offer. 20% sale on selected items. '
          'Explore to find your surprise.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('no threshold set, so it promises none', (tester) async {
      // site_settings.free_delivery_threshold is null on this shop, and
      // checkout quotes delivery per order -- a headline figure it then
      // contradicts is worse than no figure.
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        find.bySemanticsLabel('Free delivery. On selected products'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('and names one the moment the shop sets it', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, threshold: 999);

      expect(
        find.bySemanticsLabel('Free delivery. On orders above Rs. 999'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}

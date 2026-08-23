import 'package:flutter/material.dart';

import 'widgets/category_section.dart';
import 'widgets/department_grid.dart';
import 'widgets/deal_group.dart';
import 'widgets/hero_banner.dart';
import 'widgets/promo_rail.dart';
import 'widgets/spotlight_rail.dart';
import 'widgets/product_rail.dart';

/// Placeholder content for the home feed.
///
/// Split out of the screen so the widget stays about layout. Every list here is
/// stand-in data with the same shape an API would return, so wiring a backend
/// later replaces this file and touches nothing else.
class HomeContent {
  HomeContent._();

  static const promos = [
    PromoItem(
      headline: 'Up to 40% off',
      caption: 'Everyday electronics, this week only',
      tint: Color(0xFFF97316),
    ),
    PromoItem(
      headline: 'Free delivery',
      caption: 'On hand-picked items across Nepal',
      tint: Color(0xFF0EA5E9),
    ),
    PromoItem(
      headline: 'New arrivals',
      caption: 'Fresh stock added daily',
      tint: Color(0xFF059669),
    ),
  ];

  static const electronics = [
    CategoryEntry(
      label: 'Headphones',
      imageUrl: 'https://loremflickr.com/400/400/headphones?lock=1',
      icon: Icons.headphones,
      tint: Color(0xFF6366F1),
    ),
    CategoryEntry(
      label: 'Tablets',
      imageUrl: 'https://loremflickr.com/400/400/tablet,device?lock=2',
      icon: Icons.tablet_mac,
      tint: Color(0xFF0EA5E9),
    ),
    CategoryEntry(
      label: 'Gaming',
      imageUrl: 'https://loremflickr.com/400/400/gaming,setup?lock=3',
      icon: Icons.sports_esports,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Speakers',
      imageUrl: 'https://loremflickr.com/400/400/hifi,loudspeaker?lock=4',
      icon: Icons.speaker,
      tint: Color(0xFFF97316),
    ),
  ];

  static const computing = [
    CategoryEntry(
      label: 'Desktops',
      imageUrl: 'https://loremflickr.com/400/400/desktop,computer?lock=5',
      icon: Icons.desktop_windows,
      tint: Color(0xFF0891B2),
    ),
    CategoryEntry(
      label: 'Laptops',
      imageUrl: 'https://loremflickr.com/400/400/laptop?lock=6',
      icon: Icons.laptop_mac,
      tint: Color(0xFF2563EB),
    ),
    CategoryEntry(
      label: 'Monitors',
      imageUrl: 'https://loremflickr.com/400/400/computer,display?lock=7',
      icon: Icons.monitor,
      tint: Color(0xFF059669),
    ),
    CategoryEntry(
      label: 'Accessories',
      imageUrl: 'https://loremflickr.com/400/400/computer,mouse?lock=8',
      icon: Icons.keyboard,
      tint: Color(0xFFE84326),
    ),
  ];

  static const homeGoods = [
    CategoryEntry(label: 'Bedsheets', icon: Icons.bed, tint: Color(0xFF0891B2)),
    CategoryEntry(
      label: 'Pillows',
      imageUrl: 'https://loremflickr.com/400/400/pillow?lock=9',
      icon: Icons.airline_seat_individual_suite,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Duvet covers',
      imageUrl: 'https://loremflickr.com/400/400/duvet,bedding?lock=10',
      icon: Icons.king_bed,
      tint: Color(0xFFF59E0B),
    ),
    CategoryEntry(
      label: 'Throws and blankets',
      imageUrl: 'https://loremflickr.com/400/400/blanket?lock=11',
      icon: Icons.dry_cleaning,
      tint: Color(0xFF059669),
    ),
  ];

  /// Generic console categories rather than brand names: this is placeholder
  /// data, and naming a manufacturer implies stock we have not modelled.
  static const gaming = [
    CategoryEntry(
      label: 'Controllers',
      imageUrl: 'https://loremflickr.com/400/400/gamepad?lock=12',
      icon: Icons.sports_esports,
      tint: Color(0xFF6366F1),
    ),
    CategoryEntry(
      label: 'Handhelds',
      imageUrl: 'https://loremflickr.com/400/400/nintendo,handheld?lock=13',
      icon: Icons.videogame_asset,
      tint: Color(0xFFE84326),
    ),
    CategoryEntry(
      label: 'VR headsets',
      imageUrl: 'https://loremflickr.com/400/400/virtualreality?lock=14',
      icon: Icons.vrpano,
      tint: Color(0xFF0891B2),
    ),
    CategoryEntry(
      label: 'Console accessories',
      imageUrl: 'https://loremflickr.com/400/400/gaming,accessory?lock=15',
      icon: Icons.cable,
      tint: Color(0xFFF59E0B),
    ),
  ];

  static const family = [
    CategoryEntry(
      label: 'Outdoor play',
      imageUrl: 'https://loremflickr.com/400/400/playground?lock=16',
      icon: Icons.park,
      tint: Color(0xFF059669),
    ),
    CategoryEntry(
      label: 'Building blocks',
      imageUrl: 'https://loremflickr.com/400/400/lego?lock=17',
      icon: Icons.extension,
      tint: Color(0xFFF97316),
    ),
    CategoryEntry(
      label: 'Board games',
      imageUrl: 'https://loremflickr.com/400/400/boardgame?lock=18',
      icon: Icons.casino,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Learning toys',
      imageUrl: 'https://loremflickr.com/400/400/wooden,toys?lock=19',
      icon: Icons.school,
      tint: Color(0xFF0EA5E9),
    ),
  ];

  static const shoes = [
    CategoryEntry(
      label: "Women's",
      icon: Icons.woman,
      tint: Color(0xFFEC4899),
    ),
    CategoryEntry(label: "Men's", icon: Icons.man, tint: Color(0xFF2563EB)),
    CategoryEntry(
      label: "Girls'",
      icon: Icons.child_care,
      tint: Color(0xFF059669),
    ),
    CategoryEntry(
      label: "Boys'",
      icon: Icons.child_friendly,
      tint: Color(0xFF0EA5E9),
    ),
  ];

  static const pets = [
    CategoryEntry(label: 'Dog supplies', icon: Icons.pets, tint: Color(0xFFF59E0B)),
    CategoryEntry(
      label: 'Cat supplies',
      imageUrl: 'https://loremflickr.com/400/400/cat?lock=20',
      icon: Icons.cruelty_free,
      tint: Color(0xFFA855F7),
    ),
    CategoryEntry(
      label: 'Grooming',
      imageUrl: 'https://loremflickr.com/400/400/dog,grooming?lock=21',
      icon: Icons.content_cut,
      tint: Color(0xFF0891B2),
    ),
    CategoryEntry(
      label: 'Beds and crates',
      imageUrl: 'https://loremflickr.com/400/400/dog,bed?lock=22',
      icon: Icons.night_shelter,
      tint: Color(0xFF059669),
    ),
  ];

  static const departments = [
    DepartmentEntry(label: 'Beauty', icon: Icons.brush, tint: Color(0xFFEC4899)),
    DepartmentEntry(
      label: 'Home and kitchen',
      imageUrl: 'https://loremflickr.com/400/400/kitchen?lock=23',
      icon: Icons.chair,
      tint: Color(0xFF0891B2),
    ),
    DepartmentEntry(
      label: 'Sports and outdoors',
      imageUrl: 'https://loremflickr.com/400/400/sports?lock=24',
      icon: Icons.sports_baseball,
      tint: Color(0xFF059669),
    ),
    DepartmentEntry(
      label: 'Electronics',
      imageUrl: 'https://loremflickr.com/400/400/electronics?lock=25',
      icon: Icons.memory,
      tint: Color(0xFF6366F1),
    ),
    DepartmentEntry(
      label: 'Outdoor clothing',
      imageUrl: 'https://loremflickr.com/400/400/outdoor,jacket?lock=26',
      icon: Icons.backpack,
      tint: Color(0xFFF59E0B),
    ),
    DepartmentEntry(
      label: 'Pet supplies',
      imageUrl: 'https://loremflickr.com/400/400/pets?lock=27',
      icon: Icons.pets,
      tint: Color(0xFFA855F7),
    ),
  ];

  /// Titles, prices and photography are real rows from
  /// `/api/v1/feed/trending-products` -- the same catalogue the sibling
  /// storefront sells -- so the rail shows product shots rather than stock
  /// imagery. Ratings and review counts are still invented: that endpoint
  /// returns no rating, and the star row is here to prove the layout.
  static const topPicks = [
    ProductItem(
      title: 'Ice Silk Sun Protection Clothing for Women',
      price: 1130,
      listPrice: 1568,
      rating: 4.5,
      reviewCount: 128,
      icon: Icons.checkroom,
      tint: Color(0xFF6366F1),
      imageUrl: 'https://cbu01.alicdn.com/img/ibank/O1CN01iXcpl126fA5yFMZ2a_!!2222450237688-0-cib.jpg',
    ),
    ProductItem(
      title: 'Khaki Culottes, elastic high waist',
      price: 1921,
      listPrice: 2760,
      rating: 4.0,
      reviewCount: 64,
      icon: Icons.checkroom,
      tint: Color(0xFFF97316),
      imageUrl: 'https://cbu01.alicdn.com/img/ibank/O1CN01Bni0Xe1tkZgUKE65i_!!2204179815940-0-cib.jpg',
    ),
    ProductItem(
      title: 'Ballet-style suspender dress',
      price: 1808,
      rating: 5.0,
      reviewCount: 12,
      icon: Icons.woman,
      tint: Color(0xFFEC4899),
      imageUrl: 'https://cbu01.alicdn.com/img/ibank/O1CN01iBIpGB25c7r5El11d_!!2220252547546-0-cib.jpg',
    ),
    ProductItem(
      title: 'Retro lace-up collar top',
      price: 1808,
      listPrice: 2545,
      rating: 3.5,
      reviewCount: 41,
      icon: Icons.checkroom,
      tint: Color(0xFF0EA5E9),
      imageUrl: 'https://cbu01.alicdn.com/img/ibank/O1CN01kprFtD2LEnXBsp37y_!!2220883829661-0-cib.jpg',
    ),
  ];

  /// Price bands, not prices: these are marketing framings and are stored as
  /// written rather than run through formatRupees.
  static const alsoPopular = [
    DealItem(
      label: 'Water bottles and flasks',
      imageUrl: 'https://loremflickr.com/400/400/water,bottle?lock=32',
      teaser: 'From Rs. 350',
      icon: Icons.local_drink,
      tint: Color(0xFF0891B2),
    ),
    DealItem(
      label: 'Vehicle lighting',
      imageUrl: 'https://loremflickr.com/400/400/car,headlight?lock=33',
      teaser: 'From Rs. 450',
      icon: Icons.light_mode,
      tint: Color(0xFFF59E0B),
    ),
    DealItem(
      label: 'Kurta sets',
      imageUrl: 'https://loremflickr.com/400/400/kurta?lock=34',
      teaser: 'From Rs. 1,200',
      icon: Icons.checkroom,
      tint: Color(0xFF0EA5E9),
    ),
    DealItem(
      label: 'Saris',
      imageUrl: 'https://loremflickr.com/400/400/saree?lock=35',
      teaser: 'Under Rs. 2,000',
      icon: Icons.woman,
      tint: Color(0xFFEC4899),
    ),
  ];

  /// Seasonal placeholder. Dashain is the Nepali festival this storefront
  /// would actually merchandise around; a real build would drive both the
  /// title and the tint from a campaign the admin schedules.
  static const festival = [
    DealItem(
      label: 'Sweets and hampers',
      imageUrl: 'https://loremflickr.com/400/400/giftbox?lock=36',
      teaser: 'From Rs. 299',
      icon: Icons.card_giftcard,
      tint: Color(0xFFE84326),
    ),
    DealItem(
      label: 'Skincare sets',
      imageUrl: 'https://loremflickr.com/400/400/skincare?lock=37',
      teaser: 'Up to 60% off',
      icon: Icons.spa,
      tint: Color(0xFFA855F7),
    ),
    DealItem(
      label: 'Jewellery',
      imageUrl: 'https://loremflickr.com/400/400/jewellery?lock=38',
      teaser: 'Under Rs. 1,500',
      icon: Icons.diamond,
      tint: Color(0xFFF59E0B),
    ),
    DealItem(
      label: 'Home decor',
      imageUrl: 'https://loremflickr.com/400/400/interior,vase?lock=39',
      teaser: 'From Rs. 199',
      icon: Icons.emoji_objects,
      tint: Color(0xFF059669),
    ),
  ];

  static const spotlight = [
    SpotlightItem(
      offer: 'From Rs. 1,099',
      caption: 'Watches',
      imageUrl: 'https://loremflickr.com/400/400/wristwatch?lock=40',
      icon: Icons.watch,
      tint: Color(0xFF6366F1),
    ),
    SpotlightItem(
      offer: 'Min. 65% off',
      caption: 'Running shoes',
      imageUrl: 'https://loremflickr.com/400/400/running,shoes?lock=41',
      icon: Icons.directions_run,
      tint: Color(0xFF059669),
    ),
    SpotlightItem(
      offer: 'Up to 80% off',
      caption: 'Earbuds',
      imageUrl: 'https://loremflickr.com/400/400/earbuds?lock=42',
      icon: Icons.earbuds,
      tint: Color(0xFF0EA5E9),
    ),
    SpotlightItem(
      offer: 'From Rs. 799',
      caption: 'Backpacks',
      imageUrl: 'https://loremflickr.com/400/400/backpack?lock=43',
      icon: Icons.backpack,
      tint: Color(0xFFF97316),
    ),
  ];

  /// Hero carousel. A real build would serve these from a campaign table;
  /// the shapes match what such an endpoint would return.
  static const banners = [
    BannerItem(
      headline: 'Dashain deals are live',
      caption: 'Save across every department',
      cta: 'Shop the sale',
      tint: Color(0xFFE84326),
      imageUrl: 'https://loremflickr.com/600/400/festival,lights?lock=44',
    ),
    BannerItem(
      headline: 'Free delivery on picks',
      caption: 'Hand-picked, delivery on us',
      cta: 'See the list',
      tint: Color(0xFF277586),
      imageUrl: 'https://loremflickr.com/600/400/delivery,parcel?lock=45',
    ),
    BannerItem(
      headline: 'New tech, lower prices',
      caption: 'Fresh stock every week',
      cta: 'Browse tech',
      tint: Color(0xFF6366F1),
      imageUrl: 'https://loremflickr.com/600/400/technology,gadgets?lock=46',
    ),
  ];
}

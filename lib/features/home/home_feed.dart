import 'package:flutter/material.dart';

import '../../shared/widgets/page_width.dart';

import '../../../shared/widgets/loadable_view.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/data/catalog_store.dart';
import '../catalog/data/product.dart';
import '../catalog/presentation/catalog_visuals.dart';
import '../deals/presentation/deals_screen.dart';
import '../flash_sale/presentation/flash_sale_card.dart';
import '../flash_sale/presentation/flash_sale_card_skeleton.dart';
import '../search/presentation/search_results_screen.dart';
import 'data/fallback_banners.dart';
import '../catalog/presentation/browse_screen.dart';
import '../catalog/presentation/category_screen.dart';
import 'widgets/department_feed.dart';
import '../free_delivery/data/free_delivery_repository.dart';
import '../corporate_gifts/presentation/corporate_gifts_screen.dart';
import '../free_delivery/presentation/free_delivery_screen.dart';
import 'widgets/promo_section.dart';
import 'widgets/department_grid.dart';
import 'widgets/hero_banner.dart' as banner;
import 'widgets/product_carousel.dart';
import 'widgets/product_grid.dart';
import 'widgets/subcategory_grid.dart';
import '../cart/presentation/quick_add_to_cart.dart';

/// The home feed, built from what the catalogue actually contains.
///
/// Every block below is a separate request that loads and fails on its own.
/// That is the point: one of them timing out must not take the banners and the
/// recommendation rail down with it.
///
/// The department blocks are the exception, and deliberately so -- they are
/// Browse sections built from the category tree that is already in memory, so
/// they cost no request at all. They used to carry a rail of products each,
/// which was nine requests and the same shape repeated nine times down a page
/// that already opens with one.
class HomeFeed extends StatefulWidget {
  const HomeFeed({super.key, this.department});

  /// The department tab in force, or null for "For You".
  ///
  /// The strip that sets this lives in the header above, outside the scroll
  /// view, so it stays on screen however far down the page a shopper is --
  /// which is the whole reason it is a tab strip rather than a block in the
  /// feed.
  final Category? department;

  @override
  State<HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<HomeFeed> {
  /// Asked for once, not on every rebuild: the home feed rebuilds on every
  /// store notification, and a future recreated in build would refetch each
  /// time and flicker the line under the headline.
  final Future<num?> _freeDeliveryThreshold = FreeDeliveryRepository.instance
      .threshold()
      .catchError((_) => null);

  /// How far down the catalogue the Browse sections reach.
  ///
  /// The head of the tree, which is where the departments a shopper is most
  /// likely to want sit. Everything past it is reachable through the index at
  /// the foot of the page and through [_featured].
  static const _headCount = 5;

  /// Departments that get a block wherever they sit in the catalogue's order.
  ///
  /// The tree is sorted for a clothing shopper: these four sit at positions
  /// 16, 19, 26 and 31, so reaching them by raising [_headCount] would mean
  /// putting twenty-seven departments on the page to get four wanted ones.
  ///
  /// Keyed on cid rather than on name. The names are here to say which is
  /// which, but a name is display text the backoffice can edit -- "Machine
  /// tools" losing its lowercase t would silently drop the section, and a
  /// section that quietly stops appearing is the hardest kind of bug to
  /// notice.
  static const _featured = <String, String>{
    '1042954': 'Bags & Leather',
    '1426': 'Machine tools',
    '10208': 'Instruments',
    '1': 'Agriculture',
  };

  /// The departments that get a Browse section, in page order.
  ///
  /// The head of the catalogue first, then the featured four in the order they
  /// are named above rather than in catalogue order -- they are a chosen set,
  /// and shuffling them back into the tree's ordering would lose the choice.
  ///
  /// A featured department already in the head is not added twice, and one the
  /// catalogue does not contain is skipped rather than left as a heading with
  /// nothing under it.
  List<Category> _blockDepartments(List<Category> categories) {
    final head = categories.take(_headCount).toList();
    final taken = {for (final d in head) d.cid};

    for (final cid in _featured.keys) {
      if (taken.contains(cid)) continue;
      final match = categories.where((c) => c.cid == cid);
      if (match.isEmpty) continue;
      head.add(match.first);
      taken.add(cid);
    }

    return head;
  }

  /// A short, chosen set of categories, shown large under the sale.
  ///
  /// Keyed on cid like [_featured], and for the same reason: a name is display
  /// text the backoffice can edit, and a curated block whose members quietly
  /// stop appearing is the hardest kind of bug to notice.
  ///
  /// Every one was checked against production before it was put here, because
  /// a tile that leads to an empty page is worse than no tile. That check ruled
  /// out the obvious picks: **Footwear** and **jewelry** are both real
  /// categories with real artwork and **no products at all** -- zero from
  /// `/search/products` and zero from `/categories/{cid}/products`. These four
  /// return rows from both.
  static const _fashion = <String, String>{
    '10166': 'Women',
    '10165': 'Men',
    '1042954': 'Bags & Leather',
    '97': 'Beauty Skincare/Makeup',
  };

  /// The curated block, or nothing when the tree cannot fill it.
  ///
  /// Two tiles is the floor. A "picks" block showing one thing is not a
  /// selection, and a half-empty grid reads as a section that failed to load.
  Widget _fashionEdit(BuildContext context, List<Category> categories) {
    final byCid = {for (final c in categories) c.cid: c};
    final picks = [
      for (final cid in _fashion.keys)
        if (byCid[cid] != null) byCid[cid]!,
    ];
    if (picks.length < 2) return const SizedBox.shrink();

    // The same tile the Browse sections use: the picture from the catalogue
    // with the name written across the foot of it, on a scrim. Reusing it
    // rather than drawing a second kind of category tile is what keeps the two
    // blocks reading as one page -- and the caption cannot be clipped by a long
    // name, because inside a square frame there is nothing to overflow.'

    return SubcategoryGrid(
      title: 'Fashion favourites',
      // Describes the four tiles rather than praising them. "Best prices" or
      // "most loved" would be a claim nothing here can check.
      subtitle: 'Clothing, bags and beauty.',
      leadingIcon: Icons.checkroom_outlined,
      actionLabel: 'Shop more',
      // The page's own measure, as the hero and the flash sale above it use.
      // These sections were inset a flat sixteen points, which on a phone is
      // three times the margin the rest of the page keeps and left them
      // visibly narrower than everything they sit under.
      margin: PageWidth.marginOf(context),
      // Thirteen of these stack down this page, so the rhythm between them is
      // paid twelve times over. See [SectionHeader.denseGapAbove].
      dense: true,
      children: picks,
      onSelected: (category) => _openSearch(context, cid: category.cid),
      onSeeAll: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const BrowseScreen())),
    );
  }

  /// The department the electronics block draws from.
  static const _electronicsCid = '57';

  // The departments the promo banners open. Measured on the live tree:
  // /alibaba-categories?parent_cid=null.
  static const _digitalCid = '7'; // Digital, Computer
  static const _furnitureCid = '96'; // Home Textile Furniture
  static const _toysCid = '1813'; // Toys
  static const _womenCid = '10166'; // Women
  static const _menCid = '10165'; // Men
  static const _footwearCid = '1038378'; // Footwear
  static const _toolsCid = '59'; // Hardware, tools
  static const _babyCid = '1501'; // Maternal and Infant Supplies
  static const _beautyCid = '97'; // Beauty Skincare/Makeup
  static const _bathroomCid = '122384004'; // Bathroom fixtures
  static const _cleaningCid = '201547901'; // Organize cleaning supplies
  static const _lightingCid = '58'; // Lighting
  static const _safetyCid = '70'; // Safety, protection
  static const _schoolCid = '2111'; // Learn stationery
  static const _petsCid = '121814002'; // Pets & Supplies
  static const _industrialCid = '65'; // Machinery and industry equipment
  static const _agricultureCid = '1'; // Agriculture
  static const _electricalCid = '5'; // Electrician Electrical
  static const _machineryCid = '1426'; // Machine tools
  static const _textilesCid = '4'; // Textiles, Leathers
  static const _bagsCid = '1042954'; // Bags & Leather
  static const _decorCid = '127888009'; // Creative Ornaments
  static const _outdoorLivingCid = '125'; // Garden materials
  static const _packagingCid = '68'; // Packaging
  // A subcategory of Sports Outdoors, not the department: the Sports & Fitness
  // banner already opens that, and this one advertises tents.
  static const _campingCid = '281904'; // Mountain, Camping Supplies
  static const _kitchenCid = '201547801'; // Daily Dining Kitchen Utensils

  /// The four of its children the block shows, in this order.
  ///
  /// Cids, because the tree sorts its children alphabetically and these four
  /// are the 1st, 2nd, 4th and 11th of about thirty -- so "the first four" is
  /// Antenna, Audio Devices, Cabling Products and Capacitor, which is not the
  /// set asked for. The names beside them say which is which; **nothing here is
  /// drawn from them**. The label, the picture and the destination all come off
  /// the category the tree returns, so a rename or a new photograph in the
  /// backoffice shows up without this file being touched.
  static const _electronics = <String, String>{
    '10235': 'Antenna',
    '202058705': 'Audio Devices',
    '127676048': 'Capacitor',
    '200804003': 'Diode',
  };

  /// The electronics block, or nothing when the tree cannot fill it.
  Widget _electronicsEdit(BuildContext context, List<Category> categories) {
    Category? department;
    for (final candidate in categories) {
      if (candidate.cid == _electronicsCid) department = candidate;
    }
    if (department == null) return const SizedBox.shrink();

    final byCid = {for (final child in department.children) child.cid: child};
    final picks = [
      for (final cid in _electronics.keys)
        if (byCid[cid] != null) byCid[cid]!,
    ];
    // Two is the floor, as with the fashion block: a half-empty grid reads as a
    // section that failed to load rather than as a selection.
    if (picks.length < 2) return const SizedBox.shrink();

    return SubcategoryGrid(
      // The department's own name, not a copy of it typed here. It reads
      // "Electronic components" today; if the backoffice recases or renames it,
      // the heading follows.
      title: department.name,
      // Says what the tiles are. No claim about price, stock or quality --
      // there is nothing behind this section that could check one.
      subtitle: 'Components and modules by category.',
      leadingIcon: Icons.memory_outlined,
      actionLabel: 'Shop more',
      margin: PageWidth.marginOf(context),
      dense: true,
      children: picks,
      // Into the category, not straight at a product list. These four each hold
      // a level of their own -- Antenna six subcategories, Capacitor twelve --
      // and jumping past it threw that level away.
      onSelected: (category) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CategoryScreen(category: category)),
      ),
      onSeeAll: () => _openSearch(context, cid: department!.cid),
    );
  }

  /// The department the sports block draws from.
  static const _sportsCid = '18';

  /// Four of its children, in this order.
  ///
  /// Chosen rather than taken off the top, for the same reason as [_electronics]
  /// -- the tree returns thirty-odd children and the first four are not these.
  /// The names are documentation; the label, the picture and the destination
  /// are all read off the category the tree returns.
  ///
  /// Every one was checked against production first: all four carry real
  /// artwork, each holds between twelve and twenty-six subcategories of its
  /// own, and each has products under it. Fishing Supplies, Fitness Equipment
  /// and Swimming were the obvious picks and are all empty of products today,
  /// which is why they are not here.
  static const _sports = <String, String>{
    '281904': 'Mountain, Camping Supplies',
    '1048070': 'Outdoor Clothing',
    '2040': 'Sport Protective Gear',
    '1044819': 'Badminton and tennis equipment',
  };

  /// The sports block, or nothing when the tree cannot fill it.
  Widget _sportsEdit(BuildContext context, List<Category> categories) {
    Category? department;
    for (final candidate in categories) {
      if (candidate.cid == _sportsCid) department = candidate;
    }
    if (department == null) return const SizedBox.shrink();

    final byCid = {for (final child in department.children) child.cid: child};
    final picks = [
      for (final cid in _sports.keys)
        if (byCid[cid] != null) byCid[cid]!,
    ];
    if (picks.length < 2) return const SizedBox.shrink();

    // The name *under* the picture, not written across it.
    //
    // Same idea as the two blocks above, deliberately not the same drawing:
    // three identical grids down one page is a page that stops being read. It
    // is also the better fit here -- these names run to "Badminton and tennis
    // equipment", and a caption laid over a photograph has one line to say
    // that in, while a label under it has two.
    return DepartmentGrid(
      // The department's own name from the catalogue, not a copy typed here.
      title: department.name,
      subtitle: 'Camping, training and match-day kit.',
      leadingIcon: Icons.hiking_outlined,
      actionLabel: 'Shop more',
      margin: PageWidth.marginOf(context),
      dense: true,
      // Two across rather than the index's three: four tiles meant to be
      // looked at, with room for the names the catalogue actually uses.
      columns: 2,
      onSeeAll: () => _openSearch(context, cid: department!.cid),
      entries: [
        for (final category in picks)
          DepartmentEntry(
            label: category.name,
            icon: iconForCategory(category.name),
            tint: tintForCategory(category.cid),
            imageUrl: category.imageUrl,
            // Into the category, as the electronics tiles do: each of these
            // holds a dozen or more subcategories, and going straight to a
            // product list would throw that level away.
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CategoryScreen(category: category),
              ),
            ),
          ),
      ],
    );
  }

  /// The department the appliances block draws from.
  static const _appliancesCid = '6';

  /// Four of its children, in this order.
  ///
  /// Chosen rather than taken off the top, as [_electronics] and [_sports] are,
  /// and for the same reason: the names here are documentation, and the label,
  /// the picture and the destination are all read off the category the tree
  /// returns.
  ///
  /// All eleven children were checked against production first. These four each
  /// carry artwork, return products from both the category and the search
  /// endpoint, and hold a level of their own -- between thirty-one and
  /// seventy-three subcategories each -- which is the level the tiles open.
  ///
  /// Two were ruled out and it is worth saying which, so they are not picked up
  /// later as obvious omissions: **Audio-visual appliances** returns nothing at
  /// all from `/categories/{cid}/products`, and **Smart Home System** is a leaf
  /// with no subcategories, so a tile for it would open a category page with no
  /// level under it.
  static const _appliances = <String, String>{
    '653': 'Kitchen Appliance',
    '652': 'Living appliances',
    '1047393': 'Big appliances',
    '1047981': 'Two seasons appliances',
  };

  /// The appliances block, or nothing when the tree cannot fill it.
  ///
  /// Drawn exactly as [_electronicsEdit] is, down to the widget: the two blocks
  /// are the same kind of thing -- a department, four of its children as
  /// pictures, and a way into the rest of it.
  Widget _appliancesEdit(BuildContext context, List<Category> categories) {
    Category? department;
    for (final candidate in categories) {
      if (candidate.cid == _appliancesCid) department = candidate;
    }
    if (department == null) return const SizedBox.shrink();

    final byCid = {for (final child in department.children) child.cid: child};
    final picks = [
      for (final cid in _appliances.keys)
        if (byCid[cid] != null) byCid[cid]!,
    ];
    // Two is the floor, as with the blocks above: a half-empty grid reads as a
    // section that failed to load rather than as a selection.
    if (picks.length < 2) return const SizedBox.shrink();

    return SubcategoryGrid(
      // The department's own name, not a copy of it typed here. It reads
      // "Home appliance" today; if the backoffice recases or renames it to
      // "Home Appliances", the heading follows -- and so do the tab strip, the
      // browse screen and the "Shop by category" tile, which is the point of
      // never typing it.
      title: department.name,
      // Says what the tiles are, and nothing a shopper could be disappointed
      // by: no claim about price, stock or quality.
      subtitle: 'Kitchen, laundry and living.',
      leadingIcon: Icons.kitchen_outlined,
      actionLabel: 'Shop more',
      margin: PageWidth.marginOf(context),
      dense: true,
      children: picks,
      // Into the category rather than straight at a product list, as the
      // electronics tiles do. Each of these holds dozens of subcategories, and
      // jumping past that level would throw it away.
      onSelected: (category) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CategoryScreen(category: category)),
      ),
      onSeeAll: () => _openSearch(context, cid: department!.cid),
    );
  }

  @override
  void initState() {
    super.initState();
    CatalogStore.instance.banners.load();
    CatalogStore.instance.discover.load();
    CatalogStore.instance.randomPicks.load();
    CatalogStore.instance.categories.load();
    CatalogStore.instance.flashSale.load();
  }

  /// Puts a catalogue product in the cart from a department tab.
  ///
  /// No deal wrapper: this is the listed price, because nothing on these cards
  /// claims otherwise.
  /// Ask what is being bought before buying it: the options sheet, which adds
  /// through the same cart once the seller's own choices have been answered.
  Future<void> _addProduct(BuildContext context, Product product) =>
      quickAddToCart(context, product);

  void _openSearch(
    BuildContext context, {
    String query = '',
    String? cid,
    ProductSort sort = ProductSort.relevance,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SearchResultsScreen(query: query, categoryCid: cid, sort: sort),
      ),
    );
  }

  /// The built-in banners, as carousel items.
  ///
  /// Shown when the server has no campaigns running or could not be reached.
  /// Each one opens a real search, so a shopper who taps one lands somewhere
  /// that exists even while the banner endpoint is down -- and none of them
  /// advertises an offer, because nothing can confirm one at that moment.
  List<banner.BannerItem> _fallbackItems(BuildContext context) => [
    for (final item in kFallbackBanners)
      banner.BannerItem(
        eyebrow: item.eyebrow,
        headline: item.headline,
        caption: item.caption,
        cta: item.cta,
        tint: item.colors.first,
        gradient: item.colors,
        icon: item.icon,
        onTap: () => _openSearch(context, query: item.query),
      ),
  ];

  /// Turns a campaign link into a screen.
  ///
  /// The links are web routes written by whoever set the banner up, so most of
  /// them point at pages this app does not have. Search is the one shape worth
  /// following; everything else leaves the banner as artwork rather than
  /// sending a shopper somewhere blank.
  VoidCallback? _bannerAction(BuildContext context, HeroBanner item) {
    final link = item.buttonLink;
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.path.startsWith('/search')) return null;
    final query = uri.queryParameters['q'] ?? '';
    return () => _openSearch(context, query: query);
  }

  @override
  Widget build(BuildContext context) {
    final store = CatalogStore.instance;

    // A department tab lists that department instead of the whole storefront.
    // Same pull-to-refresh, so the gesture does not stop working on one tab.
    final department = widget.department;
    if (department != null) {
      return RefreshIndicator(
        onRefresh: () => CatalogStore.instance.rail(department.cid).refresh(),
        child: DepartmentFeed(
          department: department,
          onSeeAll: () => _openSearch(context, cid: department.cid),
          // Only from the button at the foot of the page. Tapping a
          // subcategory chip narrows this page in place rather than pushing a
          // screen, so this is the way out and not the way through.
          onSeeAllChild: (child) => _openSearch(context, cid: child.cid),
          onAddToCart: (product) => _addProduct(context, product),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: store.refreshHome,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Above the banner, under the department strip. Eight rather than
          // fourteen: the strip already keeps its own room beneath it.
          const SizedBox(height: 8),
          // Not a LoadableView: this is the one block that must never show an
          // error. A red retry panel where the storefront's artwork belongs is
          // worse than a storefront -- and the rails below read the same server,
          // so an outage is already reported once further down the page.
          //
          // Three states, and only three: the skeleton until the first answer,
          // the campaigns the server sent, and the built-in set when it sent
          // none or could not be reached.
          ListenableBuilder(
            listenable: store.banners,
            builder: (context, _) {
              final loadable = store.banners;
              final banners = loadable.value;

              if (banners == null && loadable.isLoading) {
                return const banner.HeroBannerSkeleton();
              }

              if (banners == null || banners.isEmpty) {
                return banner.HeroBanner(items: _fallbackItems(context));
              }

              return banner.HeroBanner(
                items: [
                  for (final item in banners)
                    banner.BannerItem(
                      headline: item.showTextOverlay ? item.title : '',
                      caption: item.showTextOverlay
                          ? (item.subtitle ?? '')
                          : '',
                      cta: item.buttonText ?? 'Shop now',
                      tint: tintForCategory(item.id),
                      imageUrl: item.imageUrl,
                      onTap: _bannerAction(context, item),
                    ),
                ],
              );
            },
          ),
          // Directly under the campaign artwork and above everything else on
          // the page: a sale with a deadline is the one block whose value goes
          // to zero if it is scrolled past.
          // Not a LoadableView, deliberately. That widget's rule is that a
          // failure is never silence, and it is right for the catalogue -- but
          // a flash sale is promotional extra, not content the page is about.
          // Most of the time there is no sale at all, so "no sale" and "the
          // sale could not be fetched" have to look the same: like a page
          // without a sale on it. A red retry block here would also report the
          // same outage twice, since the rail below reads the same endpoint.
          ListenableBuilder(
            listenable: store.flashSale,
            builder: (context, _) {
              final loadable = store.flashSale;
              final sale = loadable.value;
              // Nothing yet. While the request is still out the slot keeps the
              // card's height, so a sale that lands a second later takes the
              // space it was already given instead of pushing the banners below
              // it down the page. Once the server has answered and there is no
              // sale, the slot goes entirely -- which is the ordinary case, and
              // it must not leave a hole.
              if (sale == null) {
                return loadable.isLoading
                    ? const FlashSaleCardSkeleton()
                    : const SizedBox.shrink();
              }
              if (sale.items.isEmpty) {
                return const SizedBox.shrink();
              }
              void openDeals() => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DealsScreen()));

              // The deadline only. The "Dashain Specials" panel that used to
              // sit under this -- the sale's headline over a rail of its deals
              // -- is gone from the home page; the card still leads to the
              // Deals screen, which lists the same offers in full.
              return FlashSaleCard(sale: sale, onTap: openDeals);
            },
          ),
          // Directly under the flash sale, as the design places it: the
          // promotional block in its own colours. Outside any LoadableView,
          // so a catalogue that fails to load does not take the delivery
          // promise down with it -- the promise is true either way.
          FutureBuilder<num?>(
            future: _freeDeliveryThreshold,
            builder: (context, snapshot) => PromoSection(
              threshold: snapshot.data,
              onFreeDelivery: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FreeDeliveryScreen()),
              ),
              // Each banner opens the department it advertises. The cids are
              // the shop's own, read off /alibaba-categories: a banner that
              // said Electronics and opened a search for the word would have
              // been a guess about what the catalogue calls things.
              onElectronics: () => _openSearch(context, cid: _digitalCid),
              onFurniture: () => _openSearch(context, cid: _furnitureCid),
              onToys: () => _openSearch(context, cid: _toysCid),
              onKitchen: () => _openSearch(context, cid: _kitchenCid),
              onWomen: () => _openSearch(context, cid: _womenCid),
              // The two departments the edit blocks further down already use.
              onAppliances: () => _openSearch(context, cid: _appliancesCid),
              onSports: () => _openSearch(context, cid: _sportsCid),
              onPackaging: () => _openSearch(context, cid: _packagingCid),
              onCamping: () => _openSearch(context, cid: _campingCid),
              onMen: () => _openSearch(context, cid: _menCid),
              onFootwear: () => _openSearch(context, cid: _footwearCid),
              onTools: () => _openSearch(context, cid: _toolsCid),
              onBaby: () => _openSearch(context, cid: _babyCid),
              onBeauty: () => _openSearch(context, cid: _beautyCid),
              // "Trending now" is this catalogue's best selling: the whole
              // shop ordered by what is actually moving. There is no separate
              // trending screen to open, and pointing it at the deals page
              // would be advertising discounts as popularity.
              onTrending: () => _openSearch(context, sort: ProductSort.sales),
              onBathroom: () => _openSearch(context, cid: _bathroomCid),
              onCleaning: () => _openSearch(context, cid: _cleaningCid),
              onLighting: () => _openSearch(context, cid: _lightingCid),
              onSafety: () => _openSearch(context, cid: _safetyCid),
              onSchool: () => _openSearch(context, cid: _schoolCid),
              onPets: () => _openSearch(context, cid: _petsCid),
              onIndustrial: () => _openSearch(context, cid: _industrialCid),
              onAgriculture: () => _openSearch(context, cid: _agricultureCid),
              onElectrical: () => _openSearch(context, cid: _electricalCid),
              onMachinery: () => _openSearch(context, cid: _machineryCid),
              onTextiles: () => _openSearch(context, cid: _textilesCid),
              onBags: () => _openSearch(context, cid: _bagsCid),
              onDecor: () => _openSearch(context, cid: _decorCid),
              onOutdoorLiving: () =>
                  _openSearch(context, cid: _outdoorLivingCid),
              onCorporateGifts: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CorporateGiftsScreen()),
              ),
              // "Explore to find your surprise" is the deals page: the shop's
              // own discounted items, which is the only thing behind this app
              // that a sale banner can honestly lead to.
              onOffers: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DealsScreen())),
            ),
          ),
          LoadableView<List<Category>>(
            loadable: store.categories,
            emptyCheck: (categories) => categories.isEmpty,
            // An emptyCheck with no empty widget rendered nothing at all, so a
            // catalogue that came back empty looked like a page still loading.
            empty: const _NoCategories(),
            builder: (context, categories) => Column(
              children: [
                _fashionEdit(context, categories),
                _electronicsEdit(context, categories),
                _sportsEdit(context, categories),
                _appliancesEdit(context, categories),
                for (final department in _blockDepartments(categories))
                  _DepartmentBlock(
                    department: department,
                    onSeeAll: () => _openSearch(context, cid: department.cid),
                    onOpenChild: (child) =>
                        _openSearch(context, cid: child.cid),
                  ),
                // The "Shop by category" index used to close this column. It is
                // gone from the home page by request. Nothing was lost with it:
                // the department tab strip is pinned to the header, the Browse
                // screen still lists every department, and Fashion favourites'
                // "Shop more" is the route to it from here.
              ],
            ),
          ),
          // Drawn down the page rather
          // than along a rail: twenty products are meant to be browsed, and a
          // rail of twenty is nineteen swipes to reach the end of.
          //
          // The card is the one the rails and the search results already use,
          // in the same grid the results page lays out -- same columns, same
          // gaps, same measured height.
          //
          // Its own request, like every other block here, so a slow or failed
          // draw leaves the rest of the page alone. No skeleton and no empty
          // state on purpose: this section is a bonus rather than something a
          // shopper came for, and a placeholder for it would be louder than the
          // thing itself.
          LoadableView<List<Product>>(
            loadable: store.randomPicks,
            emptyCheck: (products) => products.isEmpty,
            // When the product feed is down the recommendations directly below
            // already say so, in the server's words and with a retry. A second
            // copy of the same message stacked above it tells a shopper
            // nothing.
            silentOnError: true,
            builder: (context, products) => ProductGrid(
              // Says what the section is for rather than how it was built.
              // "Random Products" described the algorithm; nobody shops for
              // randomness, and a heading admitting the order is arbitrary
              // reads as an apology for the rows under it.
              title: 'Discover something new',
              subtitle: 'A fresh mix from every corner of the catalogue.',
              leadingIcon: Icons.explore_outlined,
              products: products,
              onSeeAll: () => _openSearch(context),
              onAddToCart: (product) => _addProduct(context, product),
            ),
          ),
          // Its own request, so it still loads and fails on its own -- moving it
          // down the page changed where it appears and nothing else.
          LoadableView<List<Product>>(
            loadable: store.discover,
            emptyCheck: (products) => products.isEmpty,
            loading: const ProductCarouselSkeleton(
              title: 'Recommended for you',
            ),
            // Down the page rather than along a rail, laid out exactly as
            // "Discover something new" above it: the same cards, the same
            // columns, the same gaps. Same products and the same request --
            // only the layout changed.
            builder: (context, products) => ProductGrid(
              title: 'Recommended for you',
              leadingIcon: Icons.auto_awesome,
              products: products,
              onSeeAll: () => _openSearch(context),
              onAddToCart: (product) => _addProduct(context, product),
            ),
          ),
        ],
      ),
    );
  }
}

/// Said when the catalogue comes back with no departments in it.
///
/// Rare, and worth a line rather than a blank stretch of page: an empty
/// catalogue and a page that has not finished loading look identical
/// otherwise, and only one of them is worth waiting for.
class _NoCategories extends StatelessWidget {
  const _NoCategories();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: PageWidth.insets(context, top: 14, bottom: 14),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No departments to show just now. Pull down to try again.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One department, as a named Browse section.
///
/// It used to carry a rail of that department's best sellers above the
/// subcategories. The rails are gone by request: the page already opens with
/// "Recommended for you", and a second, third and ninth rail of products under
/// department headings was the same shape repeated down the page. What is left
/// is what the block is for -- a way into the department.
///
/// Stateless now, and that is the point rather than a tidy-up. The rail was the
/// only reason this ever held state: it loaded on first build, one request per
/// department. Nine departments' worth of those requests have gone with it, and
/// the subcategories were never a request at all -- they arrive with the
/// department tree and are already in memory.
class _DepartmentBlock extends StatelessWidget {
  const _DepartmentBlock({
    required this.department,
    required this.onSeeAll,
    required this.onOpenChild,
  });

  final Category department;
  final VoidCallback onSeeAll;
  final void Function(Category child) onOpenChild;

  @override
  Widget build(BuildContext context) {
    final children = department.children;
    if (children.isEmpty) return const SizedBox.shrink();

    return SubcategoryGrid(
      title: 'Browse ${department.name}',
      // The same measure as the curated blocks above, so every Browse section
      // down the page lines up with them and with the hero.
      margin: PageWidth.marginOf(context),
      dense: true,
      // Three across rather than two, and six tiles rather than four. A
      // department has about forty children, so this shows half again as many
      // of them in roughly two thirds the height -- which is what the width
      // freed by the 97% measure is for. The curated blocks above stay at two:
      // they hold exactly four, and three across would leave one on a row of
      // its own.
      columns: 3,
      shown: 6,
      children: children,
      onSelected: onOpenChild,
      onSeeAll: onSeeAll,
    );
  }
}

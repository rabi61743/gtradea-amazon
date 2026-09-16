import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/colors.dart';
import '../../core/realtime/realtime_service.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../account/data/recently_viewed_store.dart';
import '../for_you/presentation/new_for_you_screen.dart';
import '../account/presentation/account_screen.dart';
import '../address/data/address_store.dart';
import '../auth/data/auth_store.dart';
import '../wallet/data/coin_balance_store.dart';
import '../wallet/presentation/coins_to_wallet_animation.dart';
import '../cart/data/cart_store.dart';
import '../cart/presentation/cart_screen.dart';
import '../catalog/data/catalog_repository.dart' show Category;
import '../catalog/data/catalog_store.dart';
import '../checkout/data/saved_payment_store.dart';
import '../catalog/presentation/browse_screen.dart';
import '../notifications/data/device_notifications.dart';
import '../notifications/presentation/notifications_screen.dart';
import '../notifications/data/notification_store.dart';
import '../orders/data/order_store.dart';
import '../promo/data/coupon_store.dart';
import '../promo/data/popup_banner_store.dart';
import '../promo/presentation/startup_popup_banner.dart';
import '../search/data/recent_search_store.dart';
import '../search/presentation/search_entry_screen.dart';
import '../search/widgets/visual_search_sheet.dart';
import '../search/presentation/search_results_screen.dart';
import '../wishlist/data/wishlist_store.dart';
import '../wishlist/presentation/wishlist_screen.dart';
import '../tour/data/tour_step.dart';
import '../tour/data/tour_store.dart';
import '../tour/presentation/tour_overlay.dart';
import 'home_feed.dart';
import '../../shared/widgets/brand_loader.dart';
import '../../shared/widgets/loading_gate.dart';
import 'widgets/department_tabs.dart';
import 'widgets/search_header.dart';

/// The app shell: a pinned search bar over the feed, with the bottom bar.
///
/// This widget owns the things that outlive any one screen -- which stores are
/// bound to the signed-in account, the live socket, and the notification
/// catch-up at startup. The feed itself is [HomeFeed].
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The department tab in force, or null for "For You".
  ///
  /// Held here rather than in the feed because the strip that sets it lives in
  /// the header, outside the scroll view, so it stays put however far down the
  /// page the shopper is.
  Category? _department;

  /// Whether the feed has been scrolled off the top.
  ///
  /// What folds the department icons away. Held here rather than in the feed
  /// for the same reason [_department] is: the strip it drives sits in the
  /// header, outside the scroll view.
  ///
  /// A notifier rather than plain state, and that is the whole of the
  /// smoothness fix. Only the strip reads this; a setState rebuilt the entire
  /// shell for it -- the band, its photograph, and every section of [HomeFeed]
  /// -- in the same frame the fold began animating.
  final ValueNotifier<bool> _scrolled = ValueNotifier(false);

  /// Two thresholds rather than one.
  ///
  /// A single line would toggle on every pixel of overscroll wobble around it,
  /// which is a header that flickers. It folds after a deliberate scroll and
  /// only opens again near the very top.
  static const _foldAt = 24.0;
  static const _openAt = 6.0;

  /// Whether the header's chrome row -- the mark, the delivery line and the
  /// three icons -- is folded away.
  ///
  /// Driven by direction rather than depth: it goes on a scroll down and
  /// comes back on a scroll up, wherever in the feed that happens. Somebody
  /// reaching for the bell halfway down a page flicks up and it is there.
  final ValueNotifier<bool> _headerHidden = ValueNotifier(false);

  /// Where the feed was when the row last changed its mind.
  double _turnedAt = 0;

  /// How far the feed has to travel one way before the row follows it, so a
  /// finger resting on the glass cannot flap the header.
  static const _turn = 32.0;

  /// And how far it has to travel back before the header returns.
  ///
  /// Less than half of [_turn], because the two are not the same question.
  /// Hiding should wait for a committed scroll -- a header that folds on the
  /// first stray pixel is the flapping this dead-zone exists to stop. Coming
  /// back is answering somebody reaching for the search bar, and making them
  /// drag a further thirty-two points to be heard is the delay this removes.
  static const _turnUp = 14.0;

  void _onFeedScrolled(ScrollNotification notification) {
    // This page's own list, and nothing nested in it. A scrollable inside the
    // feed reports its own pixels in its own coordinate space, and a header
    // chasing two offsets at once cannot settle. The axis check below already
    // excluded the sideways rails; this excludes a vertical one.
    if (notification.depth != 0) return;
    if (notification.metrics.axis != Axis.vertical) return;

    final offset = notification.metrics.pixels;
    final scrolled = _scrolled.value ? offset > _openAt : offset > _foldAt;

    var hidden = _headerHidden.value;
    if (offset <= _openAt) {
      // At the top there is nothing to make room for.
      hidden = false;
      _turnedAt = offset;
    } else if (offset - _turnedAt > _turn) {
      hidden = true;
      _turnedAt = offset;
    } else if (_turnedAt - offset > _turnUp) {
      hidden = false;
      _turnedAt = offset;
    }

    // Straight onto the notifiers, which tell only the two widgets that read
    // them. Each already ignores a write that changes nothing, so the guard
    // this used to need is theirs now.
    //
    // What this replaced: a setState on the shell, which rebuilt the header
    // band, the photograph behind it, the department strip *and* the whole of
    // HomeFeed -- every rail, every grid, every LoadableView -- on the frame
    // the fold started. The fold was always animated; it was being animated on
    // a frame that had just rebuilt the page.
    _scrolled.value = scrolled;
    _headerHidden.value = hidden;
  }

  @override
  void initState() {
    super.initState();
    WishlistStore.instance.load();
    LanguageStore.instance.load();
    AuthStore.instance.load();
    // Bound before the load so a sign-in that lands mid-startup still moves
    // the cart to the right identity.
    CartStore.instance.bindToAuth();
    // Each account's saved list, history and alert choices are its own; these
    // follow the active account like the cart does.
    WishlistStore.instance.bindToAuth();
    RecentlyViewedStore.instance.bindToAuth();
    NotificationSettings.instance.bindToAuth();
    CouponStore.instance.bindToAuth();
    CouponStore.instance.load();
    OrderStore.instance.bindToAuth();
    NotificationStore.instance.bindToAuth();
    AddressStore.instance.bindToAuth();
    // The coin chip in the header draws from this, and the row around it is
    // built from whether there is a balance at all -- so the ask belongs to
    // the page rather than to a widget that only exists once it succeeds.
    CoinBalanceStore.instance.bindToAuth();
    CoinBalanceStore.instance.load();
    SavedPaymentStore.instance.bindToAuth();
    // Bound before the load, like the stores above: the listener has to be in
    // place before a restored session arrives, or the change it exists to hear
    // has already happened. What a guest saw carries into the account they
    // sign into, and one shopper's finished tour never silences another's.
    TourStore.instance.bindToAuth();
    unawaited(TourStore.instance.load());
    // Started here rather than left to HomeFeed's initState. The department
    // strip listens to this same store from the header, and a load kicked off
    // while the feed below it is being built notifies a sibling that has
    // already built this frame -- which is a setState-during-build assertion,
    // not a warning. Starting it before the first build sidesteps that, and
    // HomeFeed's own idempotent load() then does nothing.
    CatalogStore.instance.categories.load();
    AddressStore.instance.load();
    OrderStore.instance.load();
    CartStore.instance.load();

    // The feed catches up at startup: an order can move while the app is
    // closed, and those steps still have to be announced when it reopens.
    unawaited(_catchUpNotifications());

    // Sign-in and sign-out are the account events worth telling someone about,
    // and this is the one place that watches identity for the whole app.
    AuthStore.instance.addListener(_onAuthChanged);

    // The live channel. It carries "something changed" rather than the change
    // itself, so every payload still has exactly one source.
    RealtimeService.instance.bind(
      AuthStore.instance,
      userId: () => AuthStore.instance.account?.id,
    );
    _realtime = RealtimeService.instance.events.listen(_onRealtimeEvent);

    // A tap on a device notification lands here, whether the app was already
    // running or was launched by the tap itself. Routed to the notifications
    // screen, which is what already knows how to open a quote, a support
    // thread or an order -- rather than a second copy of that routing.
    DeviceNotifications.instance.onTap = _onNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = DeviceNotifications.instance.takePendingTap();
      if (pending != null) _onNotificationTap(pending);
    });

    // The admin's startup popup, once the storefront is ready. See
    // [_maybeShowPopup] for everything that has to be true first.
    unawaited(PopupBannerStore.instance.load());
    _popupTriggers.addListener(_schedulePopupCheck);
    _schedulePopupCheck();
  }

  StreamSubscription<RealtimeEvent>? _realtime;

  /// What can make the popup ready: the saved sign-in being restored, the
  /// catalogue finishing its cold load, the tour answering, and the setting
  /// arriving.
  final Listenable _popupTriggers = Listenable.merge([
    AuthStore.instance,
    CatalogStore.instance.categories,
    TourStore.instance,
    PopupBannerStore.instance,
  ]);

  void _schedulePopupCheck() {
    if (PopupBannerStore.instance.launchHandled) return;
    // After the frame: these stores can notify in the middle of a build.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _maybeShowPopup())
      // A still storefront has no frame coming to run the check in.
      ..scheduleFrame();
  }

  /// Shows the popup straight after the loading screen on a fresh launch, if
  /// there is one to show.
  ///
  /// Driven by the startup state itself rather than a timer: it waits for the
  /// saved sign-in to be restored, the cold-start loader to be gone, the tour
  /// to have read that account's record and the setting to arrive, whichever
  /// lands last. Once per app launch -- see [PopupBannerStore.launchHandled] --
  /// so resuming from the background or navigating never shows it again. A
  /// launch that opens the tour keeps the tour to itself: the popup waits for
  /// the next launch rather than stacking two overlays on a first run.
  Future<void> _maybeShowPopup() async {
    if (!mounted) return;
    final store = PopupBannerStore.instance;
    if (store.launchHandled) return;

    // The sign-in first. The tour reads the guest's record until the saved
    // session is restored, and then re-reads the account's. Deciding in that
    // gap took a signed-in shopper who had finished the tour for somebody who
    // had not -- "tour pending, skip the popup" -- on every launch, which is
    // why it did not appear. Restoring the session makes the tour unload for
    // the re-read synchronously, so the check below then waits for the right
    // record.
    if (!AuthStore.instance.isLoaded) return;
    final tour = TourStore.instance;
    if (!tour.isLoaded) return;
    final catalogue = CatalogStore.instance.categories;
    if (catalogue.value == null && catalogue.isLoading) return;
    if (!store.isLoaded) return;

    if (!store.claimLaunch()) return;
    _popupTriggers.removeListener(_schedulePopupCheck);
    // A first run belongs to the tour: nothing else opens over it.
    if (tour.shouldStart) return;

    // First the admin's popup, if there is one; then, once it is closed, the
    // coins-into-the-wallet scene. One after the other, never stacked.
    final followed = await _showLaunchPopup(store);
    if (!mounted) return;

    // The shopper tapped the banner and is on their way to the sale: taking
    // them there matters more than a celebration in front of it.
    if (followed != null) {
      _followPopupLink(followed);
      return;
    }

    // Once per fresh launch, on this same gate -- so it waits for the same
    // things the popup does and is never replayed on a resume or a
    // navigation. It reveals the figure the header already shows, so the two
    // can never disagree.
    if (CoinsToWalletAnimation.showOnLaunch &&
        ModalRoute.of(context)?.isCurrent != false) {
      await CoinsToWalletAnimation.show(
        context,
        value: CoinBalanceStore.instance.balance.round(),
      );
    }
  }

  /// Shows the launch popup if there is one to show, and waits for it to
  /// close. Returns the banner's link when the shopper followed it, and null
  /// otherwise -- closed, or no popup at all.
  Future<String?> _showLaunchPopup(PopupBannerStore store) async {
    final banner = store.banner;
    if (banner == null || !store.shouldShow()) return null;

    // Decoded before the card opens, so it never appears as an empty box. A
    // picture that will not load means no popup at all.
    final image = StartupPopupBanner.imageFor(context, banner);
    final loaded = await StartupPopupBanner.decode(context, image);
    if (!loaded || !mounted) return null;
    // Not over a page the shopper has already opened.
    if (ModalRoute.of(context)?.isCurrent == false) return null;

    final result = await StartupPopupBanner.show(
      context,
      banner: banner,
      image: image,
    );
    return result == PopupResult.followed ? banner.buttonLink : null;
  }

  /// The same links the hero banners follow: a search is the one web route
  /// this app has a screen for. Anything else just closes the popup.
  void _followPopupLink(String? link) {
    if (link == null) return;
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.path.startsWith('/search')) return;
    _openPage(
      context,
      SearchResultsScreen(query: uri.queryParameters['q'] ?? ''),
    );
  }

  @override
  void dispose() {
    _popupTriggers.removeListener(_schedulePopupCheck);
    AuthStore.instance.removeListener(_onAuthChanged);
    _realtime?.cancel();
    DeviceNotifications.instance.onTap = null;
    _scrolled.dispose();
    _headerHidden.dispose();
    super.dispose();
  }

  /// Routes a live event to whatever it invalidates.
  ///
  /// The sibling app refreshes only the orders *list* on an order event, so a
  /// shopper staring at a tracking screen watches it sit still while the list
  /// behind it updates. When the frame names an order, that order's tracking is
  /// refetched as well.
  ///
  /// An event matching neither prefix refreshes both, because an unrecognised
  /// name is more likely to be a new kind of change than nothing at all.
  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.isOrder || !event.isNotification) {
      unawaited(OrderStore.instance.refreshFromServer());
      final orderId = event.orderId;
      if (orderId != null) {
        unawaited(OrderStore.instance.loadTracking(orderId));
      }
    }
    if (event.isNotification || !event.isOrder) {
      unawaited(NotificationStore.instance.load());
    }
  }

  void _onNotificationTap(NotificationTap tap) {
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  void _onAuthChanged() {
    final account = AuthStore.instance.account;
    if (account == null) return;
    NotificationStore.instance.recordAccountEvent(
      // Keyed on the session so signing in again later is a new entry, but a
      // rebuild is not.
      id: 'signin:${account.email}:${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
      title: 'Signed in',
      body: 'You are signed in as ${account.email}.',
    );
  }

  Future<void> _catchUpNotifications() async {
    await NotificationSettings.instance.load();
    await NotificationStore.instance.load();
    await OrderStore.instance.load();
    if (!mounted) return;

    NotificationStore.instance.syncFromOrders(OrderStore.instance.orders);

    // Campaigns the storefront is actually running: the same banners the feed
    // shows, which an admin set and which expire on their own.
    await CatalogStore.instance.banners.load();
    if (!mounted) return;
    for (final banner in CatalogStore.instance.banners.value ?? const []) {
      if (banner.promoCode == null) continue;
      NotificationStore.instance.recordPromotion(
        id: banner.id,
        title: banner.title,
        body: banner.subtitle ?? 'Use code ${banner.promoCode} at checkout.',
      );
    }
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchEntryScreen()));
  }

  /// A dictated query goes straight to results, and is remembered exactly as a
  /// typed one is -- the shopper has already said what they want, so dropping
  /// them on the entry screen to say it again would be a step for nothing.
  void _searchSpoken(BuildContext context, String query) {
    RecentSearchStore.instance.record(query);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SearchResultsScreen(query: query)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogStore.instance.categories,
      builder: (context, _) {
        final catalogue = CatalogStore.instance.categories;
        // The one wait that earns the whole screen: a first run with nothing
        // cached, where a header over a page of bones is not a storefront yet.
        //
        // `value == null` is what keeps this to a genuinely cold start. The
        // tree is cached to disk, so a returning shopper has departments to
        // paint before the first frame and never sees this. A failure does not
        // qualify either -- the loader would sit there forever, when the page
        // underneath can say what went wrong and offer a retry.
        final cold = catalogue.value == null && catalogue.isLoading;

        return LoadingGate(
          loading: cold,
          loadingChild: const BrandLoaderScreen(),
          child: _shell(context),
        );
      },
    );
  }

  /// The height the band's photograph is drawn at, whatever the band is doing.
  ///
  /// Held constant so the picture is *clipped* by the folding band rather than
  /// re-cropped by it. `BoxFit.cover` scales from the width, which never
  /// changes, so a shorter box does not shrink the image -- it keeps less of
  /// it, and the part it keeps slides. That slide was the abruptness: the
  /// mountains travelled inside the frame while the frame travelled down the
  /// page, and no easing on the fold could have settled it.
  ///
  /// Taller than the band ever gets, on any text scale or screen width, so the
  /// crop is the same at every point of the fold -- but only just.
  ///
  /// Overshooting is *not* free, which is what 420 got wrong. `BoxFit.cover`
  /// scales to fill the box, so a box far taller than the band zooms the
  /// photograph into it: at 420 against an open band of about 230 the picture
  /// was blown up nearly twice over, and what reached the screen was a small
  /// flat patch of haze rather than the range. The image was there and
  /// correct -- it simply had nothing recognisable left in frame.
  ///
  /// 260 clears the open band at every text scale and on a tablet, and stops
  /// there, so the framing is the one the design chose.
  static const double _artHeight = 260;

  /// The page's own ground between the header and the departments.
  ///
  /// A real gap again. It was nothing while the foot was curved, because the
  /// curve was the separation and a gap under it would have left dead ground.
  /// A straight foot separates nothing on its own, so without this the band
  /// would butt directly into the department strip.
  static const double _bandGap = 8;

  /// The artwork's duotone, in the band's own blues.
  ///
  /// Luminance first -- the same red/green/blue weighting the eye uses, which
  /// is what turns a photograph into a single tone -- and then that tone is
  /// mapped across a ramp rather than left grey: black becomes #14485A, white
  /// becomes #BFE3EC, and everything between lands on the line joining them.
  ///
  /// A duotone rather than a greyscale because the picture is drawn at half
  /// strength now: grey mountains at that weight read as a smudged photograph
  /// on the teal, where blue mountains read as part of the band.
  ///
  /// The fifth column is the low end, in 0-255; the three weights carry the
  /// distance from low to high.
  static const _duotone = ColorFilter.matrix(<double>[
    0.1426, 0.4796, 0.0484, 0, 20, //
    0.1292, 0.4347, 0.0439, 0, 72, //
    0.1217, 0.4095, 0.0413, 0, 90, //
    0, 0, 0, 1, 0, //
  ]);

  Widget _shell(BuildContext context) {
    // The tour is a sibling of the whole Scaffold, not a layer inside its
    // body. That is the difference between blurring the storefront and
    // blurring the *app*: a BackdropFilter only reaches what is painted
    // beneath it in the same layer, and `bottomNavigationBar` is a separate
    // Scaffold slot painted outside the body -- so mounted inside the body,
    // the tour left the bottom bar sharp and bright while everything above it
    // softened. Above the Scaffold, both bars fall under the same blur.
    return Stack(
      children: [
        Scaffold(
          body: _body(context),
          bottomNavigationBar: _bottomBar(context),
        ),
        // Filled explicitly. The overlay's own root is a Stack whose children
        // are all positioned, and such a Stack sizes itself to nothing -- it
        // would collapse here exactly as the scrim's CustomPaint did under
        // loose constraints.
        Positioned.fill(
          child: ListenableBuilder(
            listenable: TourStore.instance,
            builder: (context, _) {
              final store = TourStore.instance;
              // One gate. `shouldStart` already answers false while the disk
              // is unread, once this account has seen the current version, and
              // when the tour is switched off for a suite -- so a second check
              // here would only be this screen reaching into a test-only flag.
              if (!store.shouldStart) return const SizedBox.shrink();
              final steps = stepsFrom(store.unseenFrom);
              if (steps.isEmpty) return const SizedBox.shrink();
              return TourOverlay(
                steps: steps,
                onFinished: (outcome) =>
                    unawaited(TourStore.instance.finish(outcome)),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The bottom bar, lifted out of [_shell] so the Scaffold and the tour can
  /// be siblings without this moving or changing.
  Widget _bottomBar(BuildContext context) {
    // Listening to both stores: the saved badge and the account wording each
    // have to change the moment their store does, without waiting for a
    // navigation to rebuild the bar.
    return ListenableBuilder(
      listenable: Listenable.merge([
        WishlistStore.instance,
        AuthStore.instance,
        CartStore.instance,
        LanguageStore.instance,
      ]),
      // Home is the shell and every other destination opens on top of it, so
      // the selected index is always Home. The bar is a row of shortcuts
      // rather than a tab controller; tracking a selection would leave a
      // destination highlighted for a page that had since been popped.
      // Two steps point at this bar -- Cart, and Orders by way of Account --
      // and a GlobalKey can only be on one widget, so the wrapper carries
      // the second. Both resolve to the same rectangle, which is the honest
      // answer: both destinations really are in this row.
      builder: (context, _) => KeyedSubtree(
        key: TourAnchors.instance.keyOf(TourAnchor.account),
        child: AppBottomNav(
          // The bar as a whole, not one destination: ringing a single slot
          // would mean restructuring NavigationBar, and the cart and account
          // steps read perfectly well against the row that holds them.
          key: TourAnchors.instance.keyOf(TourAnchor.cart),
          currentIndex: 0,
          strings: LanguageStore.instance.strings,
          savedCount: WishlistStore.instance.count,
          cartCount: CartStore.instance.count,
          isSignedIn: AuthStore.instance.isSignedIn,
          // Shifted down one when New for You left the bar for the department
          // strip. This switch is the half of that change that fails silently:
          // leave the old numbers and every destination opens its neighbour's
          // page -- Saved the feed, Account the wishlist, Cart the account.
          onSelected: (i) => switch (i) {
            1 => _openPage(context, const WishlistScreen()),
            2 => _openPage(context, const AccountScreen()),
            3 => _openPage(context, const CartScreen()),
            4 => _openPage(context, const BrowseScreen()),
            _ => null,
          },
        ),
      ),
    );
  }

  /// The storefront itself, under whatever the tour paints over it.
  Widget _body(BuildContext context) {
    return Column(
      children: [
        // The header, on its own band, straight across its foot.
        //
        // The department strip used to live inside this box, on the same
        // ramp. It is its own block below now, by request -- so the ramp
        // ends where the header does, and the strip carries the colour the
        // ramp ended on. That is what keeps the two reading as one surface
        // across the gap between them: no seam, because there is no second
        // gradient to snap back to the dark end.
        //
        // Clipped to the band, and it has to be explicit.
        //
        // The artwork below is held at a fixed height by an OverflowBox so its
        // crop cannot slide as the header folds. A Stack does not clip a child
        // enlarged that way -- the box breaks out through the constraints
        // rather than by being positioned outside -- so the picture painted its
        // full height straight down the page, putting the header's teal and its
        // mountains behind the department strip and the carousel beneath it.
        //
        // The strip and the carousel were never styled with the header's
        // colour; they were being painted over by it. This is what stops that,
        // and it is the whole of the fix: nothing below the band changes.
        ClipRect(
          child: Stack(
            children: [
              // The ground: the ramp with the Himalayan artwork over it. One
              // decoration paints colour, then gradient, then image, so the
              // picture is a texture on the band rather than a second layer
              // to keep in step with it.
              //
              // Kathmandu under the range -- pagodas, the stupa and its
              // prayer flags, with the Himalaya behind. Greyed and at a
              // tenth of its strength, so what is left is the shape of the
              // place rather than a photograph of it.
              // The picture is held at a fixed height and clipped, rather than
              // being resized with the band.
              //
              // This is what made the image read as abrupt on a scroll, and no
              // easing could have fixed it. `BoxFit.cover` takes its scale from
              // the width, which never changes -- so when the band halved on a
              // fold the photograph was not rescaled, it was *re-cropped*, and
              // with `alignment: 0.55` anchoring that crop below centre the
              // retained window slid across the mountains for the whole
              // transition. The image moved inside its own frame, further and
              // faster than the frame moved, every frame of the fold.
              //
              // Pinned to a height taller than the band ever is and aligned to
              // the top, the crop is now constant: the band simply closes over a
              // still picture. Nothing about the artwork itself changes -- same
              // asset, same alignment, same opacity, same duotone -- and the
              // enclosing Stack clips the overflow.
              //
              // A fixed number rather than a measurement because the band's open
              // height moves with the text scale and the brand mark's 26/30/34
              // step. It has to clear all of them -- and then stop, because
              // overshooting is not free: see [_artHeight], where 420 zoomed
              // the photograph nearly twice over and left only haze in frame.
              Positioned.fill(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: _artHeight,
                  maxHeight: _artHeight,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: AppColors.brandBand,
                      image: DecorationImage(
                        image: AssetImage(
                          'assets/images/header_background.jpg',
                        ),
                        fit: BoxFit.cover,
                        // Down and to the right: the range runs across the
                        // lower half of the artwork and the stupa stands at
                        // its right, so this is the crop that puts the
                        // mountains behind the header rather than the sky.
                        alignment: Alignment(0.3, 0.55),
                        // Half strength, by request. This is a picture in the
                        // header now rather than a watermark under it: the
                        // peaks, the stupa and the rooftops are all meant to
                        // be recognised at a glance.
                        //
                        // What keeps white type legible over it is that none
                        // of it sits on the photograph unaided -- the lockup
                        // is on the smooth top of the ramp, the delivery line
                        // and the actions have their own material, the search
                        // bar is a white pill, and the scrim below steadies
                        // the foot of the band where the greeting sits.
                        // The top of the range the design allows, by request:
                        // the picture is meant to be seen. Held at 0.60 rather
                        // than taken further because white type sits on this
                        // band, and the brand tests pin the 45-60 window as a
                        // legibility decision rather than a preference.
                        opacity: 0.6,
                        colorFilter: _duotone,
                      ),
                    ),
                  ),
                ),
              ),
              // No blur over it any more, and no wash of blue either. Both
              // were there to stop a watermark competing with the type; the
              // picture is meant to be seen now, and a blurred mountain is an
              // unrecognisable one.
              //
              // What replaces them: a scrim that is nothing across the top,
              // where the peaks are, and a little of the band's dark end at
              // the foot, where the greeting and the search pill sit over the
              // busiest part of the photograph. It costs the mountains
              // nothing and gives the type its contrast back.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        // Eased from 0.28. This wash is what steadies the type
                        // at the foot of the band, so it stays -- but at 28% it
                        // was also the heaviest thing standing between the
                        // photograph and the eye across the lower half.
                        AppColors.brandBandTop.withValues(alpha: 0.18),
                      ],
                      stops: const [0.45, 1],
                    ),
                  ),
                ),
              ),
              // Outside the scroll view on purpose: search stays reachable
              // no matter how far down the feed the customer is.
              // Only this rebuilds on a fold. Everything around it -- the
              // band, the ramp, the photograph -- is built once and left
              // alone, which is what keeps the fold's own frames cheap.
              //
              // The empty strip that used to sit under this went with the
              // curve. It existed only to give the arch something to cut
              // through that was not the search pill, so with a straight foot
              // it is 36 points of dead band and the header is shorter without
              // it.
              ValueListenableBuilder<bool>(
                valueListenable: _headerHidden,
                builder: (context, hidden, _) => SearchHeader(
                  // The real search pill is what the tour rings; there is
                  // no second copy of it drawn for the overlay.
                  key: TourAnchors.instance.keyOf(TourAnchor.search),
                  compact: hidden,
                  onTap: () => _openSearch(context),
                  // The camera icon opens the camera now. It used to open
                  // a blank search screen -- the same destination as
                  // tapping the bar itself, so the icon was decoration.
                  onImageSearch: () =>
                      unawaited(VisualSearchSheet.show(context)),
                  onVoiceResult: (query) => _searchSpoken(context, query),
                ),
              ),
            ],
          ),
        ),
        // Its own section, directly under the header and above the hero.
        //
        // Nothing of the header's about it: not its band, not its corners,
        // not its ink -- and nothing of its own either. The tabs sit on the
        // page's own background with no card behind them and no rule under
        // them, so what separates the three is space rather than boxes.
        const SizedBox(height: _bandGap),
        Padding(
          // On the block rather than on the strip inside it: this box keeps
          // its place whether the departments have landed or the skeleton is
          // standing in for them, so the tour rings the same thing either
          // way instead of losing its target mid-step.
          key: TourAnchors.instance.keyOf(TourAnchor.categories),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ListenableBuilder(
            listenable: CatalogStore.instance.categories,
            builder: (context, _) {
              final loadable = CatalogStore.instance.categories;
              final categories = loadable.value ?? const <Category>[];
              if (categories.isEmpty) {
                // A skeleton the exact height of the real strip, not
                // nothing: appearing out of nowhere would shove the whole
                // storefront down seventy points the moment the tree
                // landed. Gated, so a cached tree -- which answers in
                // single-digit milliseconds -- never flashes one.
                //
                // Genuinely empty or failed is a different thing: a strip
                // of bones that never resolves is worse than no strip, so
                // that collapses to nothing.
                return LoadingGate(
                  loading: loadable.isLoading,
                  loadingChild: const DepartmentTabsSkeleton(),
                  child: const SizedBox.shrink(),
                );
              }
              return ValueListenableBuilder<bool>(
                valueListenable: _scrolled,
                builder: (context, scrolled, _) => DepartmentTabs(
                  categories: categories,
                  selectedCid: _department?.cid,
                  compact: scrolled,
                  // Choosing a department is a deliberate act that changes
                  // what the feed lists, so that one still rebuilds the
                  // shell. Scrolling does not.
                  onSelected: (category) =>
                      setState(() => _department = category),
                  // The same screen the bottom bar's second slot opens. One
                  // destination reached from two places, rather than a second
                  // copy of the feed reached from the strip.
                  onNewForYou: () =>
                      _openPage(context, const NewForYouScreen()),
                ),
              );
            },
          ),
        ),
        // The feed says how far down it is, and the strip above folds its
        // icon tiles away while it is not at the top. Only this page's own
        // vertical scroll counts: the rails inside the feed scroll sideways,
        // and one of those would otherwise collapse the header.
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _onFeedScrolled(notification);
              return false;
            },
            child: HomeFeed(department: _department),
          ),
        ),
      ],
    );
  }
}

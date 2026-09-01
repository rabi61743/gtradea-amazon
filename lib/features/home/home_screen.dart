import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/colors.dart';
import '../../core/realtime/realtime_service.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../account/presentation/account_screen.dart';
import '../address/data/address_store.dart';
import '../auth/data/auth_store.dart';
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
import '../search/data/recent_search_store.dart';
import '../search/presentation/search_entry_screen.dart';
import '../search/widgets/visual_search_sheet.dart';
import '../search/presentation/search_results_screen.dart';
import '../wishlist/data/wishlist_store.dart';
import '../wishlist/presentation/wishlist_screen.dart';
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

  @override
  void initState() {
    super.initState();
    WishlistStore.instance.load();
    LanguageStore.instance.load();
    AuthStore.instance.load();
    // Bound before the load so a sign-in that lands mid-startup still moves
    // the cart to the right identity.
    CartStore.instance.bindToAuth();
    CouponStore.instance.bindToAuth();
    CouponStore.instance.load();
    OrderStore.instance.bindToAuth();
    NotificationStore.instance.bindToAuth();
    AddressStore.instance.bindToAuth();
    SavedPaymentStore.instance.bindToAuth();
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
  }

  StreamSubscription<RealtimeEvent>? _realtime;

  @override
  void dispose() {
    AuthStore.instance.removeListener(_onAuthChanged);
    _realtime?.cancel();
    DeviceNotifications.instance.onTap = null;
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

  Widget _shell(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // The band is painted here, once, for both the search header and the
          // department strip inside it.
          //
          // Not in each of them. A top-to-bottom gradient given to two siblings
          // separately runs the whole ramp twice and snaps back to the dark end
          // at the join -- which is the seam this header has already had
          // removed once. One decoration behind both means the ramp is
          // continuous from the status bar to the first product, and neither
          // child has to know how tall the other one is.
          DecoratedBox(
            decoration: const BoxDecoration(gradient: AppColors.brandBand),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Outside the scroll view on purpose: search stays reachable no
                // matter how far down the feed the customer is.
                SearchHeader(
                  onTap: () => _openSearch(context),
                  // The camera icon opens the camera now. It used to open a
                  // blank search screen -- the same destination as tapping the
                  // bar itself, so the icon was decoration.
                  onImageSearch: () =>
                      unawaited(VisualSearchSheet.show(context)),
                  onVoiceResult: (query) => _searchSpoken(context, query),
                ),
                // Directly under the search bar and on the same band, so the
                // two read as one control surface rather than as a strip of
                // chrome wedged between the search and the products.
                ListenableBuilder(
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
                    return DepartmentTabs(
                      categories: categories,
                      selectedCid: _department?.cid,
                      onSelected: (category) =>
                          setState(() => _department = category),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(child: HomeFeed(department: _department)),
        ],
      ),
      // Listening to both stores: the saved badge and the account wording each
      // have to change the moment their store does, without waiting for a
      // navigation to rebuild the bar.
      bottomNavigationBar: ListenableBuilder(
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
        builder: (context, _) => AppBottomNav(
          currentIndex: 0,
          strings: LanguageStore.instance.strings,
          savedCount: WishlistStore.instance.count,
          cartCount: CartStore.instance.count,
          isSignedIn: AuthStore.instance.isSignedIn,
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
}

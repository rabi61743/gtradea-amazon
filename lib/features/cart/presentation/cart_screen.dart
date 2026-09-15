import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/ui/action_status.dart';
import '../../address/data/address_store.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../catalog/data/product.dart' show productStub;
import '../../catalog/presentation/catalog_visuals.dart' show openProduct;
import '../../checkout/presentation/checkout_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../../shared/widgets/loadable_view.dart';
import '../../../shared/widgets/page_width.dart';
import '../../catalog/presentation/browse_screen.dart';
import '../../product/data/storefront_config.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../widgets/cart_variant_pickers.dart';
import '../../../core/network/api_error.dart';
import '../data/cart_store.dart';
import '../../promo/data/coupon_store.dart';
import '../../promo/presentation/promo_section.dart';
import '../../future_cart/presentation/future_cart_screen.dart';
import '../widgets/cart_summary.dart';
import 'cart_recommendations.dart';

/// The cart: every line, its quantity, and what the order comes to.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  /// The shop's own delivery window, which is a site setting rather than a
  /// figure per product. Null until it arrives, and the line says nothing
  /// about delivery until it does.
  DeliveryGuarantee? _guarantee;

  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
    CouponStore.instance.load();
    // The account's saved list, so "already saved" here means what it means
    // on every other device.
    unawaited(WishlistStore.instance.sync());
    unawaited(_quoteDelivery());
    unawaited(_loadShipping());
  }

  /// The delivery window the shop publishes, as the product page reads it.
  Future<void> _loadShipping() async {
    try {
      final shipping = await StorefrontConfigRepository.instance.shipping();
      if (!mounted || !shipping.guarantee.enabled) return;
      setState(() => _guarantee = shipping.guarantee);
    } on ApiError {
      // A promise about delivery that could not be fetched is one the cart
      // should not be making up.
    }
  }

  /// Moves one line out of the cart and onto the saved list.
  ///
  /// Both sides are the account's: the cart line is removed through the cart's
  /// own store, which reconciles with `/cart`, and the save goes through the
  /// wishlist store, which writes to `/wishlist`. Undo puts the line back and
  /// takes the save off again, so a mis-tap costs nothing.
  void _moveToWishlist(CartLine line) {
    final cart = CartStore.instance;
    final wishlist = WishlistStore.instance;
    final index = cart.indexOf(line.key);
    final wasSaved = wishlist.contains(line.productId);

    if (!wasSaved) wishlist.toggle(_savedFrom(line));
    cart.remove(line.key);

    ActionStatus.show(
      context,
      ActionStatus.addedToWishlist,
      detail: wasSaved ? 'was already saved' : null,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          cart.restore(line, index);
          if (!wasSaved) wishlist.remove(line.productId, announce: false);
        },
      ),
    );
  }

  /// Everything eligible, in one go.
  ///
  /// Eligible means a line this shop can save: one whose product has a price
  /// the account can hold. A line already on the saved list is not saved
  /// twice, and one with no price is left in the cart rather than filed under
  /// a figure nobody published. The count of each is what the shopper is told.
  /// True while the whole basket is being filed under the saved list.
  ///
  /// The card's own state rather than a store's: it covers a run of writes to
  /// two stores, and neither has a flag meaning "the thing the shopper just
  /// asked for is still going".
  bool _savingAll = false;

  /// How the last run went, said in the card and not only in a snack bar.
  ///
  /// A snack bar is gone in four seconds and takes the answer with it. This is
  /// the same sentence, left where the button that caused it is.
  ({bool ok, String message})? _saveAllResult;

  Future<void> _saveAllToWishlist() async {
    if (_savingAll) return;

    final cart = CartStore.instance;
    final wishlist = WishlistStore.instance;
    final lines = cart.lines;
    if (lines.isEmpty) return;

    setState(() {
      _savingAll = true;
      _saveAllResult = null;
    });

    var moved = 0;
    var already = 0;
    var skipped = 0;
    var failed = false;

    // Saved first, emptied after. The cart is what the shopper is looking at
    // while this runs -- empty it up front and the card, its button and the
    // spinner in it all vanish mid-write, and a failure would have taken the
    // lines with it.
    final taken = <CartLine>[];

    try {
      for (final line in lines) {
        if (line.unitPrice <= 0) {
          skipped++;
          continue;
        }
        if (wishlist.contains(line.productId)) {
          already++;
        } else {
          wishlist.toggle(_savedFrom(line));
          moved++;
        }
        taken.add(line);
      }

      // Settles the account copy. Each save writes to the device at once and
      // pushes to the account behind it; sync is what waits on that push, so
      // the button spins until the account has actually taken them and what is
      // said afterwards is about what happened rather than what was tried. A
      // guest has no account to reconcile with and returns immediately.
      if (moved > 0) {
        await wishlist.sync();
        failed = wishlist.syncError != null;
      }

      // Only once they are somewhere else. A line that could not be saved to
      // the account stays in the cart, where the shopper can see it and try
      // again, rather than being taken out on the strength of a write that did
      // not land.
      if (!failed) {
        for (final line in taken) {
          cart.remove(line.key);
        }
      }
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }

    if (!mounted) return;

    // Whatever the account makes of it, the shopper should see it here.
    final error = wishlist.syncError ?? cart.syncError;
    if (failed && error != null) {
      final message = error.isNetwork
          ? 'No connection to your account - nothing was moved. '
                'Your cart is as it was.'
          : 'Not saved to your account: ${error.message}';
      _snack(message);
      setState(() => _saveAllResult = (ok: false, message: message));
      return;
    }

    final parts = [
      if (moved > 0) '$moved saved',
      if (already > 0) '$already already on your list',
      if (skipped > 0) '$skipped left in the cart - no price to save it at',
    ];
    final summary = parts.isEmpty ? 'Nothing to save.' : parts.join(' - ');
    _snack(summary);
    setState(() => _saveAllResult = (ok: true, message: summary));

    // A write that failed outside this run -- the cart's own sync, say -- is
    // still worth saying, and is not what emptied the cart.
    if (error != null) {
      _snack(
        error.isNetwork
            ? 'Saved on this device only - no connection to your account.'
            : 'Not saved to your account: ${error.message}',
      );
    }
  }

  /// The saved-list row this line stands for.
  SavedProduct _savedFrom(CartLine line) => SavedProduct(
    id: line.productId,
    title: line.title,
    price: line.unitPrice,
    listPrice: line.listPrice,
    imageUrl: line.imageUrl,
    category: line.category,
    minOrder: line.minOrder,
  );

  void _continueShopping() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BrowseScreen()));
  }

  /// Asks the server what delivery costs for this basket.
  ///
  /// Freight is priced on the weight and volume of what is in the cart and
  /// where it is going, so it needs a destination: the shopper's default
  /// address. Without one there is nothing to quote against, and the summary
  /// says the charge is worked out at checkout rather than showing a figure.
  Future<void> _quoteDelivery() async {
    await AddressStore.instance.load();
    if (!mounted) return;
    await CartStore.instance.refreshDeliveryQuote(
      district: AddressStore.instance.defaultAddress?.city,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Removal is undoable rather than confirmed, matching the saved list: one
  /// line is cheap to put back and expensive to interrupt for.
  /// Opens the product this line was added from.
  ///
  /// The line remembers the catalogue id it was built with, so this is the
  /// exact listing rather than a search for one that looks like it. The stub
  /// paints the first frame from what the line already knows -- title, photo
  /// and the price actually charged -- and the page fetches the full record,
  /// with its variants and images, against that same id.
  void _openProduct(CartLine line) => openProduct(
    context,
    productStub(
      numIid: line.productId,
      title: line.title,
      imageUrl: line.imageUrl,
      displayPrice: line.unitPrice,
    ),
  );

  void _removeWithUndo(CartLine line) {
    final store = CartStore.instance;
    final index = store.indexOf(line.key);
    store.remove(line.key);

    ActionStatus.show(
      context,
      ActionStatus.removedFromCart,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => store.restore(line, index),
      ),
    );
  }

  /// Emptying the whole cart IS confirmed: undo alone is too easy to miss when
  /// the tap discards everything at once.
  Future<void> _confirmClear() async {
    final store = CartStore.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty your cart?'),
        content: Text(
          'This removes all ${store.lineCount} '
          '${store.lineCount == 1 ? 'line' : 'lines'}. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Empty cart'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) store.clear();
  }

  void _checkout() {
    final store = CartStore.instance;
    if (store.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        // The order is passed by value, not read back off the singleton: what
        // is being paid for is what was on screen at the moment of the tap.
        builder: (_) =>
            CheckoutScreen(lines: store.lines, totals: store.totals),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Both stores: the coupon changes the total as surely as adding a line
      // does, and listening to only one leaves the summary showing a price the
      // shopper has already been told they are not paying.
      listenable: Listenable.merge([CartStore.instance, CouponStore.instance]),
      builder: (context, _) {
        final store = CartStore.instance;
        final lines = store.lines;
        // The basket moves after a coupon goes on. Removing a line can drop it
        // under the minimum, and a discount that quietly stayed would be a
        // price the shop could not honour.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final dropped = CouponStore.instance.revalidate(lines);
          if (dropped != null) {
            _snack('${dropped.code} no longer applies to this cart.');
          }
        });

        final totals = store.totals;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              lines.isEmpty
                  ? 'Cart'
                  : 'Cart (${totals.itemCount} '
                        '${totals.itemCount == 1 ? 'item' : 'items'})',
            ),
            actions: [
              if (lines.isNotEmpty)
                TextButton(
                  onPressed: _confirmClear,
                  child: const Text('Empty'),
                ),
            ],
          ),
          body: lines.isEmpty
              // Scrollable rather than centred now that something follows it:
              // the empty note keeps its words and its button, and the shop's
              // general feed sits under it instead of under nothing.
              ? ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: const [_EmptyCart(), CartRecommendations()],
                )
              : RefreshIndicator(
                  // The account's cart may have moved on another device.
                  onRefresh: store.refreshFromServer,
                  child: ListView(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    children: [
                      if (store.syncError != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: LoadFailed(
                            compact: true,
                            // Said plainly rather than swallowed. A cart that
                            // exists only on this phone is one the shopper will
                            // not find on their laptop, and they should know
                            // that before relying on it.
                            message: _syncMessage(store),
                            onRetry: store.retrySync,
                          ),
                        ),
                      for (final line in lines)
                        _CartTile(
                          line: line,
                          guarantee: _guarantee,
                          onOpen: () => _openProduct(line),
                          onIncrement: () => store.increment(line.key),
                          onDecrement: () => store.decrement(line.key),
                          onRemove: () => _removeWithUndo(line),
                          onMoveToWishlist: () => _moveToWishlist(line),
                        ),
                      const SizedBox(height: 4),
                      _CartActions(
                        onSaveAll: _saveAllToWishlist,
                        savingAll: _savingAll,
                        result: _saveAllResult,
                      ),
                      const SizedBox(height: 8),
                      PromoSection(lines: lines),
                      Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        // Flat, by request, like the lines and the coupon
                        // block above it. The whole cart now reads as one
                        // page of bordered blocks rather than a stack of
                        // floating slips.
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: CartSummary(totals: totals),
                        ),
                      ),
                      // The way to what the shop thinks comes next. Above the
                      // shelf below, which is the same idea in one row: this
                      // page reads the orders behind the cart as well as the
                      // cart itself.
                      Padding(
                        padding: PageWidth.insets(context, top: 8),
                        child: _ActionCard(
                          icon: Icons.auto_awesome_outlined,
                          // Deeper than Continue shopping's Trust Blue, so two
                          // action cards on one page are told apart -- and not
                          // the accent, which in this app means "press this to
                          // buy" rather than "look at these suggestions".
                          background: AppColors.trustBlueDeep,
                          title: 'Future Cart',
                          subtitle:
                              'Smarter suggestions for a happier '
                              'tomorrow',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const FutureCartScreen(),
                            ),
                          ),
                        ),
                      ),
                      // Under the total, where it is the thing after the
                      // decision rather than something in the way of it. It
                      // reads the basket above and draws nothing at all when
                      // the shop has nothing to suggest.
                      const CartRecommendations(),
                      // The way back to the catalogue, after the shelf that
                      // is the catalogue's own suggestion.
                      _ContinueShopping(onTap: _continueShopping),
                    ],
                  ),
                ),
          bottomNavigationBar: lines.isEmpty
              ? null
              : _CheckoutBar(totals: totals, onCheckout: _checkout),
        );
      },
    );
  }
}

/// What the banner says about a sync that did not fully succeed.
///
/// Three unrelated situations used to share one sentence and one raw error
/// code -- a dead connection, a session the server would not accept, and the
/// account refusing one particular product -- and only the first of the three
/// was ever accurate. A cart of twenty lines with one refused product read as
/// "Not saved to your account: category_restricted", which was wrong about
/// nineteen lines and unreadable about the twentieth.
String _syncMessage(CartStore store) {
  final error = store.syncError!;

  if (error.isNetwork) {
    return 'Saved on this device only - no connection to your account.';
  }

  // Not a refused product: a refused caller. The interceptor already refreshes
  // a stale token and retries once, so a 401 arriving here means that failed.
  if (error.statusCode == 401 || error.statusCode == 403) {
    return 'Your session has expired. Sign in again to save this cart to '
        'your account.';
  }

  final rejected = store.rejected;
  if (rejected.isEmpty) {
    return 'This cart could not be saved to your account: '
        '${_readableReason(error.message)}.';
  }

  final key = rejected.keys.first;
  final reason = _readableReason(rejected[key]!.message);
  final title = _titleForKey(store, key);

  if (rejected.length == 1) {
    // Naming the item is the whole point: it is the one thing the shopper can
    // act on, and the old message named the cart instead.
    return title == null
        ? 'One item could not be saved to your account: $reason.'
        : '"$title" could not be saved to your account: $reason.';
  }
  return '${rejected.length} of ${store.lineCount} items could not be saved '
      'to your account. First reason: $reason.';
}

String? _titleForKey(CartStore store, String key) {
  for (final line in store.lines) {
    if (line.key == key) return line.title;
  }
  return null;
}

/// A server error code as something a shopper can read.
///
/// The codes arrive as `category_restricted` and were printed exactly like
/// that. This deliberately does **not** translate them: inventing a meaning
/// for a code whose semantics belong to the server would be worse than the
/// code itself. It only makes the code legible, and keeps every word the
/// server sent. Anything that is already a sentence passes through untouched.
String _readableReason(String message) {
  if (!RegExp(r'^[a-z0-9_]+$').hasMatch(message)) return message;
  final words = message.split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return message;
  final first = words.first;
  return [
    first[0].toUpperCase() + first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

/// What to do with the whole basket, under it.
///
/// Both are ordinary ways out of a cart: put the lot aside for later, or go
/// and find more. A card each, because each is a small proposition with a
/// consequence -- saving all of it empties the cart -- and a pair of bare
/// buttons in a row said neither what they would do nor what they would leave
/// behind.
///
/// Cards from the theme, like the summary under them: the same corner, the
/// same elevation, the same margin. Nothing here defines its own.
///
/// Neither is a filled button. Checkout is what this page is for and is the
/// only primary on it; these two are told apart from each other instead -- the
/// one that changes the cart is tonal, the one that merely leaves is outlined.
class _CartActions extends StatelessWidget {
  const _CartActions({
    required this.onSaveAll,
    required this.savingAll,
    required this.result,
  });

  final VoidCallback onSaveAll;

  /// True while the basket is being filed away.
  final bool savingAll;

  /// How the last attempt went, or null before there has been one.
  final ({bool ok, String message})? result;

  @override
  Widget build(BuildContext context) {
    final save = _ActionCard(
      icon: Icons.favorite_border_rounded,
      // Commerce Orange, #E94724, by request. White on it measures 3.9:1 --
      // enough for the bold title, a little under the 4.5 small body text
      // is asked to meet.
      background: AppColors.commerceOrange,
      title: 'Save all to wishlist',
      subtitle: savingAll
          ? 'Saving to your list...'
          : 'Move everything to your saved list',
      // Dead while it runs: the same tap twice would file the second half of a
      // cart the first tap is still emptying.
      busy: savingAll,
      onTap: onSaveAll,
      result: result,
    );

    // On its own now: "Continue shopping" sits under the recommendations,
    // after the shelf it leads on from.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: save,
    );
  }
}

/// Continue shopping, under the recommendations.
///
/// The same action card it always was -- trust blue, flat, compact, and
/// tappable across its whole width -- placed after the shelf of suggestions
/// rather than beside the save action, and on the page's own 97% measure so
/// it lines up with the grid above it.
class _ContinueShopping extends StatelessWidget {
  const _ContinueShopping({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // A small gap under the last row of cards.
      padding: PageWidth.insets(context, top: 8),
      child: _ActionCard(
        icon: Icons.storefront_outlined,
        // The app's Trust Blue; white on it is 5.2:1.
        background: AppColors.trustBlue,
        title: 'Continue shopping',
        subtitle: 'Back to browsing products',
        onTap: onTap,
      ),
    );
  }
}

/// One of the two, as a single tappable row: a mark, what it does, one line on
/// what that means, and a chevron.
///
/// The whole card is the button. It used to be a heading, a paragraph and a
/// full-width button repeating the heading's words, and only that button
/// answered a tap -- tall, and half of it dead. Now any part of it does, with
/// the ripple and a wash of its own colour on hover, focus and press.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.background,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
    this.result,
  });

  final IconData icon;

  /// The card's fill. Everything on it is drawn in white.
  final Color background;

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// True while the action runs: the card takes no taps and shows a spinner
  /// where the chevron was.
  final bool busy;

  /// Shown under the row when there is something to say about the last run.
  final ({bool ok, String message})? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = result;
    const ink = Colors.white;
    final softInk = Colors.white.withValues(alpha: 0.9);

    return Card(
      // The row above supplies the margin, so the two can be laid out side by
      // side without a double gap between them.
      margin: EdgeInsets.zero,
      color: background,
      // Flat: no shadow and no edge, on a card that is its own colour. The
      // corner is the theme's, kept.
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        enabled: !busy,
        child: InkWell(
          onTap: busy ? null : onTap,
          // A light darkening of the card's own colour, a step more for focus
          // and for a press: feedback without a flash of another colour.
          splashColor: Colors.black.withValues(alpha: 0.10),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.black.withValues(alpha: 0.14);
            }
            if (states.contains(WidgetState.focused)) {
              return Colors.black.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.black.withValues(alpha: 0.07);
            }
            return null;
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: softInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ink,
                        ),
                      )
                    else
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: softInk,
                      ),
                  ],
                ),
                if (outcome != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // White on the card's colour, success and failure alike:
                      // the icon says which, and red or blue on orange would
                      // not be read at all.
                      Icon(
                        outcome.ok
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 15,
                        color: ink,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          outcome.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ink,
                          ),
                        ),
                      ),
                    ],
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

/// One line: photo, title, chosen variant, price, stepper.
class _CartTile extends StatelessWidget {
  const _CartTile({
    required this.line,
    required this.onOpen,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onMoveToWishlist,
    this.guarantee,
  });

  final CartLine line;

  /// The shop's delivery window, or null while it is still being fetched.
  final DeliveryGuarantee? guarantee;

  /// Back to the product this line was added from.
  final VoidCallback onOpen;

  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  /// Out of the cart and onto the saved list.
  final VoidCallback onMoveToWishlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = line.listPrice;
    final struck = (list != null && list > line.unitPrice) ? list : null;

    // The unit price, with the list price struck beside it when there is one.
    // Built once, and placed on the delivery line when there is one.
    final price = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          formatRupees(line.unitPrice),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        if (struck != null) ...[
          const SizedBox(width: 6),
          Text(
            formatRupees(struck),
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
              decorationColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        // Which rung of the seller's quantity ladder this price is, so a
        // price that moves with the stepper says why it moved.
        if (line.appliedTierFrom != null) ...[
          const SizedBox(width: 6),
          Text(
            '${line.appliedTierFrom}+ pcs',
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );

    return Card(
      // 4 between cards rather than 6: closer again, and still clear of each
      // other -- the border and the corner are what separate them, not the gap.
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      // Flat, by request. The theme gives every Card an elevation of 1, which
      // on a page that is a stack of these reads as a pile of floating slips
      // rather than a list. The border and the corner are the theme's and stay
      // -- they are what separates one line from the next now.
      //
      // Here only: the summary card below these, the two action cards, and
      // every other Card in the app keep the theme's lift.
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The photo is a way back to the listing. Ink rather than a
                // bare gesture so the tap is felt, and so a pointer turns to a
                // hand over it -- otherwise nothing says it can be tapped.
                //
                // 64 rather than 76. It is the tallest thing in this row, so it
                // sets the row's height whenever the text beside it runs short
                // -- which is most lines -- and twelve points off it is twelve
                // off the card. Still the largest element on the line, and
                // still a comfortable tap back to the listing.
                SizedBox(
                  width: 64,
                  height: 64,
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    child: ArtworkPanel(
                      icon: Icons.checkroom,
                      tint: theme.colorScheme.primary,
                      imageUrl: line.imageUrl,
                      iconScale: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and chosen option together are one link back
                      // to the listing: a shopper who wants another look taps
                      // the name, which is where they would tap anywhere else.
                      // Wrapped as one region rather than two so the gap
                      // between them is not a dead strip.
                      InkWell(
                        onTap: onOpen,
                        borderRadius: BorderRadius.circular(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (line.variantLabel != null) ...[
                              const SizedBox(height: 2),
                              // The chosen option is spelled out: two lines of
                              // the same product are otherwise
                              // indistinguishable.
                              Text(
                                line.variantLabel!,
                                // Small and secondary to the name above it,
                                // and held to two lines: sellers write long
                                // option text, and it should not stretch the
                                // card.
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  height: 1.25,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (guarantee case final window?) ...[
                        const SizedBox(height: 4),
                        // The shop's own delivery window, with the price at
                        // the right of the same line. A site setting rather
                        // than a figure per product, which is what the server
                        // publishes -- see [DeliveryGuarantee].
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                'Delivery in ${window.weeksMin}-${window.weeksMax} weeks',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                // Smaller than the app's labelSmall: a note
                                // about the line, set a step under everything
                                // else on it, in the same quiet ink.
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9.5,
                                  height: 1.2,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            price,
                          ],
                        ),
                      ] else ...[
                        // No delivery window yet: the price keeps its own
                        // line, as it had before.
                        const SizedBox(height: 4),
                        price,
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  // Same reasoning as the stepper's pair: a full 48pt target
                  // for an 18px cross is a third of the row's height spent on
                  // air. Kept at 32 square, which is still a deliberate tap.
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onRemove,
                ),
              ],
            ),
            // What else this product comes in, from the catalogue: one
            // dropdown per axis the seller published. Draws nothing at all for
            // a product with no variants, which is most of them.
            CartVariantPickers(line: line),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The stepper and the wishlist action together on the left,
                // where the hand already is. Moving it up out of a full-width
                // row of its own puts it beside the control it belongs with
                // and gives the card back a line.
                //
                // Wrap rather than Row: on a narrow phone, or at a large text
                // size, the two do not fit side by side -- and this is a
                // basket, where a clipped control costs the shopper the item.
                // It drops under the stepper instead of overflowing.
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Stepper(
                        quantity: line.quantity,
                        canDecrease: line.quantity > line.minOrder,
                        canIncrease: line.quantity < CartStore.maxPerLine,
                        onIncrement: onIncrement,
                        onDecrement: onDecrement,
                      ),
                      TextButton.icon(
                        onPressed: onMoveToWishlist,
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                          // Small and quiet: a secondary action beside the
                          // stepper, in the label size rather than body text,
                          // with a 32pt target that is still easy to hit.
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 32),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        icon: const Icon(Icons.favorite_border, size: 14),
                        label: const Text('Move to wishlist'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // The line total, because unit price times quantity is
                // arithmetic the shopper should not have to do. Still the last
                // thing on the row, and still the only thing on the right.
                Text(
                  formatRupees(line.lineTotal),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Quantity stepper, shaped like the one on the detail page.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.canDecrease,
    required this.canIncrease,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The same hairline as the box around the control, so the two rules read
    // as part of it: − | 1 | +.
    final rule = SizedBox(
      width: 1,
      height: 18,
      child: ColoredBox(color: theme.colorScheme.outlineVariant),
    );

    // The two buttons' own box, rather than the 48pt target Material gives an
    // IconButton by default. That default -- 40 even at compact density -- is
    // what made this row the tallest part of the card below the photo, for two
    // 18px glyphs.
    //
    // 36 by 32 is a deliberate floor rather than the smallest that would fit:
    // this is a basket, where a missed tap on "fewer" costs the shopper money,
    // so the target is cut to what stays comfortable and no further.
    const box = BoxConstraints.tightFor(width: 36, height: 32);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            tooltip: 'Fewer',
            visualDensity: VisualDensity.compact,
            constraints: box,
            padding: EdgeInsets.zero,
            onPressed: canDecrease ? onDecrement : null,
          ),
          rule,
          SizedBox(
            width: 28,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          rule,
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'More',
            visualDensity: VisualDensity.compact,
            constraints: box,
            padding: EdgeInsets.zero,
            onPressed: canIncrease ? onIncrement : null,
          ),
        ],
      ),
    );
  }
}

/// Pinned checkout action carrying the total, so the number does not change
/// between the tap and the next screen.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.totals, required this.onCheckout});

  final CartTotals totals;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatRupees(totals.total),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: onCheckout,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text('Checkout'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Your cart is empty',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add something from a product page and it will wait for you here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Start shopping'),
            ),
          ],
        ),
      ),
    );
  }
}

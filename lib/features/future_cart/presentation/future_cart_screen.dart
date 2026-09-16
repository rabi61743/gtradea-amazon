import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/loadable_view.dart' show LoadFailed;
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart' show AuthMode, AuthScreen;
import '../../cart/data/cart_store.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../home/widgets/product_carousel.dart' show toggleSavedProduct;
import '../../wishlist/data/wishlist_store.dart';
import '../data/future_cart_feed.dart';
import 'future_cart_chrome.dart';
import 'suggestion_card.dart';

/// The Future Cart: what this shopper is likely to want next.
///
/// Two sections, both built from things that actually happened -- the orders
/// this account has placed, and what is in the cart right now. See
/// [FutureCartFeed]; nothing on this page is a list written down in the app.
///
/// Reached from the cart, and it says so: the bar at the foot goes back there
/// and counts what is waiting.
class FutureCartScreen extends StatefulWidget {
  const FutureCartScreen({super.key});

  @override
  State<FutureCartScreen> createState() => _FutureCartScreenState();
}

/// The filters across the top, in the reference's order.
///
/// The last two are real departments looked up in the catalogue's own tree
/// rather than ids written down here -- see
/// [FutureCartFeed.departmentSuggestions].
enum FutureCartFilter {
  all('All'),
  oftenBought('Often Bought'),
  complements('Complements'),
  forHome('For Home', ['home', 'kitchen', 'furniture', 'textile']),
  forKids('For Kids', ['kid', 'toy', 'baby', 'child']);

  const FutureCartFilter(this.label, [this.keywords = const []]);

  final String label;

  /// Department names this chip stands for. Empty for the three that filter
  /// what is already on the page rather than asking for something else.
  final List<String> keywords;
}

class _FutureCartScreenState extends State<FutureCartScreen> {
  FutureCartFilter _filter = FutureCartFilter.all;

  List<Suggestion> _repeats = const [];
  List<Suggestion> _complements = const [];

  /// The two department rails, which are now sections of the page rather than
  /// something only a chip could reach.
  List<Suggestion> _home = const [];
  List<Suggestion> _kids = const [];

  bool _loading = true;
  bool _failed = false;

  /// The failure was a refused session rather than a refused request.
  ///
  /// Told apart because the two need different words and different buttons:
  /// "Try again" on an expired token retries the same refusal forever, which
  /// is what this page did -- it reported "Suggestions could not be loaded"
  /// for a cart page that was, three lines up, correctly saying the session
  /// had ended.
  bool _sessionExpired = false;

  /// Which load is the current one, so an answer to an abandoned one is
  /// dropped rather than painted over the newer page.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _sessionExpired = false;
    });

    try {
      var repeats = await FutureCartFeed.oftenBoughtAgain();
      // Real purchases first, always. The stand-in only fills a section that
      // would otherwise be empty, and never replaces a real repeat.
      if (repeats.isEmpty && FutureCartFeed.usePlaceholderRepeats) {
        repeats = await FutureCartFeed.sampleRepeats();
      }
      // More than a section's six: this one is a rail to be swiped through.
      final complements = await FutureCartFeed.complements(
        limit: FutureCartFeed.carouselShown,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _repeats = repeats;
        _complements = complements;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
        // The interceptor already refreshes a stale token and retries once,
        // so a 401 or 403 arriving here means that failed: the refresh token
        // is dead and no amount of retrying will fetch a suggestion.
        _sessionExpired =
            error is ApiError &&
            (error.statusCode == 401 || error.statusCode == 403);
      });
      return;
    }

    // The department rails follow, once the page is already on screen.
    //
    // They are two more round trips apiece, and holding the whole page behind
    // them would trade a slower open for two sections most readers never
    // scroll to. They drop in when they land.
    unawaited(_loadDepartments(generation));
  }

  /// The department rails: what the shop sells for the home, and for children.
  ///
  /// A failure here costs one rail rather than the page. Each is asked for
  /// separately so that a department the catalogue cannot answer for leaves
  /// the other standing.
  Future<void> _loadDepartments(int generation) async {
    Future<List<Suggestion>> rail(FutureCartFilter filter) async {
      try {
        return await FutureCartFeed.departmentSuggestions(
          filter.keywords,
          limit: FutureCartFeed.carouselShown,
        );
      } catch (_) {
        return const [];
      }
    }

    final home = await rail(FutureCartFilter.forHome);
    final kids = await rail(FutureCartFilter.forKids);
    if (!mounted || generation != _generation) return;
    setState(() {
      _home = home;
      _kids = kids;
    });
  }

  /// A chip now filters what is already here rather than fetching.
  ///
  /// It used to send the department chips off to the catalogue on every tap,
  /// which meant a spinner each time and the same request again on the way
  /// back. Every rail is loaded with the page, so selecting one is a rebuild.
  void _select(FutureCartFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
  }

  void _add(Product product) {
    if (!product.hasPrice) return;
    CartStore.instance.add(
      CartLine(
        productId: product.numIid,
        title: product.title,
        unitPrice: product.displayPrice!,
        imageUrl: product.imageUrl,
        quantity: product.minOrder,
        minOrder: product.minOrder,
        category: product.categoryName,
        // Carried so the cart's own shelf sharpens with this add rather than
        // having to match the label by name afterwards.
        categoryCid: product.categoryCid,
        source: '1688',
      ),
    );
  }

  /// Sends the shopper to sign in, and loads the page again afterwards.
  ///
  /// The expiry is acknowledged either way. It is a one-shot flag meaning
  /// "the last sign-out was not your doing", and leaving it set would have
  /// the account screen go on announcing an expiry the shopper has already
  /// been shown and acted on.
  ///
  /// Nothing here pushes the cart back to the account: signing in changes the
  /// active account, [CartStore] is bound to that, and its reconcile is what
  /// gives every line its `serverId`.
  Future<void> _signInAgain() async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => const AuthScreen(initialMode: AuthMode.signIn),
      ),
    );
    if (!mounted) return;
    AuthStore.instance.acknowledgeExpiry();
    await _load();
  }

  /// Back where this was opened from, which is the cart.
  void _backToCart() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// Whether [section] belongs on the page as it is filtered right now: on
  /// the "All" view, or when its own chip is the one selected.
  bool _shows(FutureCartFilter section) =>
      _filter == FutureCartFilter.all || _filter == section;

  @override
  Widget build(BuildContext context) {
    final measure = FutureCartInsets.of(context);

    return Scaffold(
      backgroundColor: FutureCartPalette.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          // Laid out whole rather than lazily, which is what stopped the page
          // shaking under a scroll.
          //
          // As a `ListView` this was a lazy list, and a lazy list *estimates*
          // the height of the children it has not reached by averaging the
          // ones it has. The children here are a 40-point chip row beside
          // 700-point rails, so every section that arrived rewrote the guess:
          // measured on a 1220x2712 phone, `maxScrollExtent` ran 1931 -> 2720
          // -> 3089 -> 4298 -> 2753 -> 2403 during one scroll down the page.
          // A scroll in flight is corrected against that number every time it
          // moves, and those corrections are what read as vibration.
          //
          // There are eight children at most -- the bar, the banner, the
          // chips, four sections and a note -- so building them all costs one
          // layout and buys an exact extent from the first frame. The rails
          // inside them stay lazy along their own axis, so this does not mean
          // building every card.
          child: SingleChildScrollView(
            // Kept scrollable even when the content is short, or the pull to
            // refresh has nothing to grab on an empty page.
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FutureCartTopBar(),
                // Full width, with no side margin of its own: the banner is
                // meant to meet the edges of the page and hang off the bar
                // above it, so the only inset left is the gap over it.
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: FutureCartBanner(),
                ),
                Padding(
                  padding: measure.copyWith(top: 14),
                  child: _Filters(selected: _filter, onSelected: _select),
                ),
                ..._body(measure),
                const SizedBox(height: 14),
                // Edge to edge, like the banner at the top of the page.
                const FutureCartFooterNote(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BackToCartBar(onTap: _backToCart),
    );
  }

  List<Widget> _body(EdgeInsets measure) {
    if (_loading) {
      return [
        Padding(
          padding: measure.copyWith(top: 18),
          child: const SuggestionGridSkeleton(),
        ),
      ];
    }

    if (_failed) {
      // An expired session is not a failed request, and offering "Try again"
      // for it sends the shopper round a loop that cannot end. The way out is
      // signing in, so that is the button.
      final expired = _sessionExpired || AuthStore.instance.sessionExpired;
      return [
        Padding(
          padding: measure.copyWith(top: 18),
          child: LoadFailed(
            message: expired
                ? 'Your session has expired. Sign in again to see your '
                      'suggestions.'
                : 'Suggestions could not be loaded.',
            retryLabel: expired ? 'Sign in' : null,
            retryIcon: expired ? Icons.login : null,
            onRetry: () => unawaited(expired ? _signInAgain() : _load()),
          ),
        ),
      ];
    }

    final sections = <Widget>[
      if (_shows(FutureCartFilter.oftenBought) && _repeats.isNotEmpty)
        _Section(
          icon: Icons.schedule,
          ink: AppColors.trustBlue,
          title: 'Often Bought Again',
          subtitle: 'Items you usually purchase on a regular basis',
          suggestions: _repeats,
          measure: measure,
          // A rail like the others, so the page reads as one kind of thing.
          carousel: true,
          // The heading's action opens this section on its own, which is what
          // the chip above already does -- so it selects the chip rather than
          // pushing a second page showing the same cards.
          onSeeAll: _filter == FutureCartFilter.all
              ? () => _select(FutureCartFilter.oftenBought)
              : null,
          onAdd: _add,
        ),
      if (_shows(FutureCartFilter.complements) && _complements.isNotEmpty)
        _Section(
          icon: Icons.extension,
          ink: FutureCartPalette.complementInk,
          title: 'Complements for Your Cart',
          subtitle: 'Goes well with items in your cart',
          suggestions: _complements,
          measure: measure,
          // A rail rather than a grid, by request: there are more of these
          // than a grid should stack, and they are for browsing past rather
          // than reading down.
          carousel: true,
          onSeeAll: _filter == FutureCartFilter.all
              ? () => _select(FutureCartFilter.complements)
              : null,
          onAdd: _add,
        ),
      // The departments, as sections of the page rather than as chips only.
      // They are the shop's own answer rather than this cart's, so they come
      // after the two rails that are about what the shopper is actually
      // buying.
      if (_shows(FutureCartFilter.forHome) && _home.isNotEmpty)
        _Section(
          icon: Icons.chair_outlined,
          ink: AppColors.trustBlue,
          title: FutureCartFilter.forHome.label,
          subtitle: 'Popular in the home departments',
          suggestions: _home,
          measure: measure,
          carousel: true,
          onSeeAll: _filter == FutureCartFilter.all
              ? () => _select(FutureCartFilter.forHome)
              : null,
          onAdd: _add,
        ),
      if (_shows(FutureCartFilter.forKids) && _kids.isNotEmpty)
        _Section(
          icon: Icons.child_care,
          ink: AppColors.commerceOrange,
          title: FutureCartFilter.forKids.label,
          subtitle: 'Popular in the kids departments',
          suggestions: _kids,
          measure: measure,
          carousel: true,
          onSeeAll: _filter == FutureCartFilter.all
              ? () => _select(FutureCartFilter.forKids)
              : null,
          onAdd: _add,
        ),
    ];

    if (sections.isEmpty) {
      return [
        Padding(
          padding: measure.copyWith(top: 18),
          child: const _Quiet(
            text:
                'Nothing to suggest yet. Order something or add to your '
                'cart, and this fills up.',
          ),
        ),
      ];
    }
    return sections;
  }
}

/// One titled block of cards.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.ink,
    required this.title,
    required this.subtitle,
    required this.suggestions,
    required this.measure,
    required this.onAdd,
    this.carousel = false,
    this.onSeeAll,
  });

  final IconData icon;
  final Color ink;
  final String title;
  final String subtitle;
  final List<Suggestion> suggestions;
  final EdgeInsets measure;
  final void Function(Product product) onAdd;

  /// Draw the cards as a swipeable rail rather than a grid.
  final bool carousel;

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: measure.copyWith(top: 18, bottom: 10),
          child: SectionHeading(
            icon: icon,
            ink: ink,
            title: title,
            subtitle: subtitle,
            onSeeAll: onSeeAll,
          ),
        ),
        // The rail takes the page margin as its *own* padding rather than
        // sitting inside a Padding: that way the first card starts on the
        // margin and the last one can leave past it, so a half-visible card
        // at the edge reads as "there is more" instead of as a clipped
        // layout. A rail wrapped in a Padding would stop dead at the margin.
        if (carousel)
          ListenableBuilder(
            // The cart as well as the wishlist: adding from a card has to
            // redraw that card as its controls, and the store is what knows.
            listenable: Listenable.merge([
              WishlistStore.instance,
              CartStore.instance,
            ]),
            builder: (context, _) => _Carousel(
              suggestions: suggestions,
              onAdd: onAdd,
              padding: measure,
            ),
          )
        else
          Padding(
            padding: measure,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                WishlistStore.instance,
                CartStore.instance,
              ]),
              builder: (context, _) =>
                  _Grid(suggestions: suggestions, onAdd: onAdd),
            ),
          ),
      ],
    );
  }
}

/// One card, wired to the cart it is allowed to change.
///
/// Here rather than in each item builder because the rail and the grid draw
/// the same card and must not drift apart about what it can do.
///
/// The quantity is read straight off [CartStore] rather than counted from the
/// card's own taps, which is what keeps two cards for the same product -- one
/// in Often Bought Again, one in a department rail -- showing the same figure.
Widget _suggestionCard(
  BuildContext context,
  Suggestion suggestion,
  void Function(Product product) onAdd,
) {
  final cart = CartStore.instance;
  final product = suggestion.product;
  final line = cart.lineFor(product.numIid);

  return SuggestionCard(
    suggestion: suggestion,
    saved: WishlistStore.instance.contains(product.numIid),
    onToggleSaved: () => toggleSavedProduct(context, product),
    onAdd: () => onAdd(product),
    onTap: () => openProduct(context, product),
    quantity: line?.quantity ?? 0,
    // The cart's rules, not this page's. The floor is the line's minimum
    // order, because a wholesale listing priced for 350 pieces cannot be
    // stepped down to one; the ceiling is the store's own cap per line.
    canDecrease: line != null && line.quantity > line.minOrder,
    canIncrease: line != null && line.quantity < CartStore.maxPerLine,
    onDecrease: line == null
        ? null
        : () => cart.setQuantity(line.key, line.quantity - 1),
    onIncrease: line == null
        ? null
        : () => cart.setQuantity(line.key, line.quantity + 1),
    onRemove: line == null ? null : () => cart.remove(line.key),
  );
}

/// The cards on a rail, swiped sideways.
///
/// Built on the same idiom as the home page's [ProductCarousel] -- a
/// horizontal `ListView.separated` whose height is asked of the card rather
/// than written down -- but drawing [SuggestionCard], because this page's card
/// carries a reason pill and a full-width Add button that the home rail's card
/// has never had. The pattern is shared; the card is this page's own.
///
/// It scrolls itself, inside a page that scrolls the other way, so the two
/// never compete for a drag.
class _Carousel extends StatelessWidget {
  const _Carousel({
    required this.suggestions,
    required this.onAdd,
    required this.padding,
  });

  final List<Suggestion> suggestions;
  final void Function(Product product) onAdd;

  /// The page margin, spent inside the rail so the cards can run to the edge.
  final EdgeInsets padding;

  /// How many products it takes before a second row is worth drawing.
  ///
  /// Four. Below that a second row is one card with a hole beside it, which
  /// reads as something failing to load rather than as a deliberate shelf.
  static const _twoRowsFrom = 4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // What a card is measured against: the room left once the margin at
        // both ends is taken out, which is what the reader actually sees.
        final available = constraints.maxWidth - padding.horizontal;
        final width = SuggestionCard.carouselWidthFor(available);
        final cardHeight = SuggestionCard.heightFor(context, width);

        if (suggestions.length < _twoRowsFrom) {
          return SizedBox(
            height: cardHeight,
            child: _Rail(
              suggestions: suggestions,
              width: width,
              padding: padding,
              onAdd: onAdd,
            ),
          );
        }

        // Two rails, not one grid of two rows.
        //
        // A horizontal GridView is a single scrollable, so both rows moved
        // together under one finger -- swipe the top and the bottom went with
        // it. Two ListViews are two scroll positions, and each row answers the
        // finger that is actually on it.
        //
        // Split alternately rather than down the middle, because that is the
        // order the grid was already laying them out in: first card top-left,
        // second beneath it, third to the right. The page looks the same at
        // rest; only the scrolling changed.
        final top = <Suggestion>[];
        final bottom = <Suggestion>[];
        for (var i = 0; i < suggestions.length; i++) {
          (i.isEven ? top : bottom).add(suggestions[i]);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: cardHeight,
              child: _Rail(
                suggestions: top,
                width: width,
                padding: padding,
                onAdd: onAdd,
              ),
            ),
            const SizedBox(height: SuggestionCard.gridGap),
            SizedBox(
              height: cardHeight,
              child: _Rail(
                suggestions: bottom,
                width: width,
                padding: padding,
                onAdd: onAdd,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One row of the rail, with a scroll position of its own.
///
/// Its own widget because the carousel draws two of them and they must not
/// share a controller: a shared one is what made both rows move as a block.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.suggestions,
    required this.width,
    required this.padding,
    required this.onAdd,
  });

  final List<Suggestion> suggestions;

  /// How wide one card is, measured once by the carousel so both rows agree.
  final double width;

  final EdgeInsets padding;
  final void Function(Product product) onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      // The page margin, spent inside the rail so the cards can run past it.
      padding: EdgeInsets.only(left: padding.left, right: padding.right),
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => const SizedBox(width: SuggestionCard.gridGap),
      itemBuilder: (context, i) => SizedBox(
        width: width,
        child: _suggestionCard(context, suggestions[i], onAdd),
      ),
    );
  }
}

/// The cards, three across on a phone as the reference has them.
class _Grid extends StatelessWidget {
  const _Grid({required this.suggestions, required this.onAdd});

  final List<Suggestion> suggestions;
  final void Function(Product product) onAdd;

  /// Between cards, both ways. The card owns the number, so the grid, its
  /// skeleton and the card's own measurement cannot drift apart.
  static const gap = SuggestionCard.gridGap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = SuggestionCard.columnsFor(available);
        final width = (available - gap * (columns - 1)) / columns;

        return GridView.builder(
          // Inside the page's own scroll view, so it must not scroll itself.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            // The card's exact height, asked of the card, so the two cannot
            // disagree about where a card ends.
            mainAxisExtent: SuggestionCard.heightFor(context, width),
          ),
          itemBuilder: (context, i) =>
              _suggestionCard(context, suggestions[i], onAdd),
        );
      },
    );
  }
}

/// The filter chips.
class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelected});

  final FutureCartFilter selected;
  final ValueChanged<FutureCartFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    // Scrollable rather than wrapped: five chips do not fit across a phone at
    // the reference's size, and a second row would push the first section
    // below the fold.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final filter in FutureCartFilter.values) ...[
            FutureCartChip(
              label: filter.label,
              selected: filter == selected,
              onTap: () => onSelected(filter),
            ),
            if (filter != FutureCartFilter.values.last)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// A sentence where a section would be, when there is nothing to put there.
class _Quiet extends StatelessWidget {
  const _Quiet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}

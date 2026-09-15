import 'dart:async';

import 'package:flutter/material.dart';

import '../../cart/presentation/cart_screen.dart';
import '../../../core/ui/action_status.dart';
import '../../../../core/network/api_error.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../catalog/data/product.dart' show productStub;
import '../../catalog/presentation/browse_screen.dart';
import '../../catalog/presentation/catalog_visuals.dart' show openProduct;
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../orders/data/order_store.dart';
import '../data/hidden_history_store.dart';
import '../data/product_views_repository.dart';
import 'discover_more_section.dart';
import 'recent_views_section.dart';

/// One line of the history, whichever tab it came from.
///
/// Viewed and purchased are different records on the server, and squashing
/// them into one model is what lets the two tabs share a card rather than
/// growing two that drift apart.
class _HistoryEntry {
  const _HistoryEntry({
    required this.productId,
    required this.title,
    required this.at,
    this.imageUrl,
    this.priceLabel,
    this.price,
    this.subtitle,
    this.variant,
  });

  final String productId;
  final String title;
  final DateTime at;
  final String? imageUrl;
  final String? priceLabel;
  final num? price;

  /// The category, under the title, as the reference has it.
  final String? subtitle;

  /// The chosen option, where the record kept one.
  final String? variant;

  /// This row, as the hidden list and the selection both key on it.
  String get key => HiddenHistoryStore.keyFor(productId: productId, at: at);

  /// What to print for the price: the number where there is one, and the label
  /// the view was recorded with otherwise.
  String? get priceText {
    final value = price;
    if (value != null && value > 0) return formatRupees(value);
    final label = priceLabel;
    return (label == null || label.isEmpty) ? null : label;
  }
}

/// Everything this shopper has looked at and bought.
///
/// Both halves are records the app already keeps: the views it has posted to
/// `/product-views` on every product open, and the orders it already reads.
/// Nothing here starts a second history.
class ProductHistoryScreen extends StatefulWidget {
  const ProductHistoryScreen({super.key});

  @override
  State<ProductHistoryScreen> createState() => _ProductHistoryScreenState();
}

class _ProductHistoryScreenState extends State<ProductHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _search = TextEditingController();

  List<ProductView> _views = const [];
  bool _loading = true;
  ApiError? _error;

  bool _searching = false;
  String _query = '';

  /// How far back to show, or null for everything.
  Duration? _within;

  /// One batch: a screen and a bit of cards.
  ///
  /// Small on purpose. The list itself is cheap (about 200 ms for 40 rows on
  /// the live route); what made this page slow was every card then fetching
  /// its full product record -- 40 of them at once, 1.5 to 3.6 s and up to
  /// 200 KB each. A card only asks for that once it is loaded, so the batch
  /// size is what bounds the work behind the first paint.
  static const pageSize = 10;

  /// How many rows are held, which is also what the next request extends.
  int _limit = pageSize;

  /// Whether older rows exist. The server's own `has_more` where it sends one;
  /// otherwise a batch that came back short of what was asked, which is the
  /// only end-of-list signal a limit-only route gives.
  bool _hasOlder = true;

  bool _loadingOlder = false;
  ApiError? _olderError;

  /// The purchased tab's own wait. It no longer holds up the viewed tab.
  bool _ordersLoading = true;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AuthStore.instance.isSignedIn) {
      setState(() {
        _views = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    // The purchased tab reads the orders, and only it does. Started alongside
    // the history rather than after it: the viewed tab used to wait out the
    // whole orders refresh before drawing a single card.
    unawaited(_loadOrders());

    try {
      // A pull-to-refresh starts over at one batch, like opening the page.
      _limit = pageSize;
      // The history and the rows this shopper has hidden, together, so the
      // first paint already has the hidden ones filtered out.
      final hidden = HiddenHistoryStore.instance.load();
      final page = await ProductViewsRepository.instance.page(limit: _limit);
      await hidden;
      if (!mounted) return;
      setState(() {
        _views = page.views;
        _loading = false;
        _hasOlder = page.hasMore ?? page.received >= _limit;
        _olderError = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadOrders() async {
    setState(() => _ordersLoading = true);
    await OrderStore.instance.refreshFromServer();
    if (mounted) setState(() => _ordersLoading = false);
  }

  /// The next batch, appended under the cards already on screen.
  ///
  /// The route ignores offsets, so the request is for everything held plus one
  /// batch; only rows not already held are appended, and the cards above are
  /// never rebuilt from the answer. Only those new rows then fetch their
  /// product records -- the ones already shown asked once and are cached.
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder) return;
    final asked = _limit + pageSize;
    if (asked > ProductViewsRepository.maxLimit) {
      setState(() => _hasOlder = false);
      return;
    }
    setState(() {
      _loadingOlder = true;
      _olderError = null;
    });

    try {
      final page = await ProductViewsRepository.instance.page(limit: asked);
      if (!mounted) return;
      final held = {for (final view in _views) _keyOf(view)};
      final fresh = [
        for (final view in page.views)
          if (held.add(_keyOf(view))) view,
      ];
      setState(() {
        _loadingOlder = false;
        _limit = asked;
        if (fresh.isNotEmpty) _views = List.unmodifiable([..._views, ...fresh]);
        _hasOlder =
            fresh.isNotEmpty && (page.hasMore ?? page.received >= asked);
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOlder = false;
        _olderError = e;
      });
    }
  }

  static String _keyOf(ProductView view) =>
      HiddenHistoryStore.keyFor(productId: view.productId, at: view.viewedAt);

  /// The viewed tab: what the server remembers, newest first.
  List<_HistoryEntry> get _viewed => [
    for (final view in _views)
      _HistoryEntry(
        productId: view.productId,
        title: view.title,
        at: view.viewedAt,
        imageUrl: view.imageUrl,
        priceLabel: view.priceLabel,
        price: view.price,
        subtitle: view.category,
      ),
  ];

  /// The purchased tab: every line of every order, newest order first.
  List<_HistoryEntry> get _purchased {
    final entries = <_HistoryEntry>[];
    for (final order in OrderStore.instance.orders) {
      for (final line in order.lines) {
        entries.add(
          _HistoryEntry(
            productId: line.productId,
            title: line.title,
            at: order.placedAt,
            imageUrl: line.imageUrl,
            price: line.unitPrice,
            subtitle: line.category,
            variant: line.variantLabel,
          ),
        );
      }
    }
    entries.sort((a, b) => b.at.compareTo(a.at));
    return entries;
  }

  /// The views the tab is showing, as records rather than rows.
  ///
  /// The same search, period and hidden-row filtering the tab applies, so the
  /// section below the list can never offer a product the shopper has just
  /// hidden or filtered away.
  List<ProductView> get _visibleViews {
    final keys = {for (final entry in _visible(_viewed)) entry.key};
    return [
      for (final view in _views)
        if (keys.contains(
          HiddenHistoryStore.keyFor(
            productId: view.productId,
            at: view.viewedAt,
          ),
        ))
          view,
    ];
  }

  /// What the search box and the period filter leave.
  List<_HistoryEntry> _visible(List<_HistoryEntry> all) {
    final query = _query.trim().toLowerCase();
    final within = _within;
    final cutoff = within == null ? null : DateTime.now().subtract(within);

    return [
      for (final entry in all)
        if ((query.isEmpty || entry.title.toLowerCase().contains(query)) &&
            (cutoff == null || entry.at.isAfter(cutoff)) &&
            !HiddenHistoryStore.instance.isHidden(entry.key))
          entry,
    ];
  }

  void _open(_HistoryEntry entry) {
    // The catalogue id the record was written with, so the page opens on the
    // product that was actually looked at.
    openProduct(
      context,
      productStub(
        numIid: entry.productId,
        title: entry.title,
        imageUrl: entry.imageUrl,
        displayPrice: entry.price,
      ),
    );
  }

  void _addToCart(_HistoryEntry entry) {
    final price = entry.price;
    if (price == null || price <= 0) {
      // The history keeps a price label, not always a number, and a line with
      // no price would reach checkout as free. Opening the product is where
      // the real price and the options are.
      _open(entry);
      return;
    }
    final inCart = CartStore.instance.add(
      CartLine(
        productId: entry.productId,
        title: entry.title,
        unitPrice: price,
        imageUrl: entry.imageUrl,
        variantLabel: entry.variant,
        category: entry.subtitle,
        source: '1688',
      ),
    );
    ActionStatus.addedToCart(
      context,
      title: entry.title,
      variant: entry.variant,
      inCart: inCart,
      onViewCart: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const CartScreen())),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This removes everything from Recently Viewed. Your orders are not '
          'affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    final before = _views;
    setState(() => _views = const []);
    try {
      await ProductViewsRepository.instance.clear();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _views = before);
      _say(e.message);
    }
  }

  Future<void> _filters() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              (null, 'All time'),
              (Duration(days: 1), 'Last 24 hours'),
              (Duration(days: 7), 'Last 7 days'),
              (Duration(days: 30), 'Last 30 days'),
            ])
              ListTile(
                leading: Icon(
                  _within == option.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _within == option.$1
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(option.$2),
                onTap: () {
                  setState(() => _within = option.$1);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear history'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_clear());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    final signedIn = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const AuthScreen()));
    if (signedIn == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search history',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('Product History'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search.clear();
                _query = '';
              }
            }),
          ),
          IconButton(
            tooltip: 'Filter',
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: _filters,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Recently Viewed'),
            Tab(text: 'Recently Purchased'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: TabBarView(
          controller: _tabs,
          children: [
            _tab(_visible(_viewed), removable: true),
            _tab(_visible(_purchased), removable: false),
          ],
        ),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
    );
  }

  Widget _tab(List<_HistoryEntry> entries, {required bool removable}) {
    if (!AuthStore.instance.isSignedIn) {
      return _Message(
        icon: Icons.lock_outline,
        text: 'Sign in to see the products you have looked at and bought.',
        actionLabel: 'Sign in',
        onAction: _signIn,
      );
    }
    // The viewed tab fades from its bones into its cards rather than snapping.
    if (removable) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey(_loading ? 'bones' : 'rows'),
          child: _viewedTab(entries),
        ),
      );
    }
    if (_loading || (_ordersLoading && entries.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    return _tabBody(entries, removable: false);
  }

  Widget _viewedTab(List<_HistoryEntry> entries) {
    if (_loading) {
      // The viewed tab is rows, so it waits as rows: bones at the card's own
      // measurements, from the top of the list, as many as the space holds.
      return LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 4, bottom: 28),
          children: [
            RecentViewsSkeleton(
              rows: RecentViewsSkeleton.rowsFor(context, constraints.maxHeight),
            ),
          ],
        ),
      );
    }
    return _tabBody(entries, removable: true);
  }

  Widget _tabBody(List<_HistoryEntry> entries, {required bool removable}) {
    final error = _error;
    if (error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: error.isNetwork
            ? 'No connection, so your history could not be loaded.'
            : error.message,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (entries.isEmpty) {
      return _Message(
        icon: Icons.history,
        text: _query.isNotEmpty || _within != null
            ? 'Nothing here matches what you are looking for.'
            : removable
            ? 'Products you open will appear here.'
            : 'Products you order will appear here.',
      );
    }

    // The viewed tab is drawn by [RecentViewsSection] -- one row per product,
    // with what the catalogue says about it and what to do about it. The
    // date-grouped cards it used to draw are gone, and the swipe and the
    // multi-select that lived on them went with them.
    if (removable) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 28),
        children: [
          RecentViewsSection(
            views: _visibleViews,
            // Every row it is given: this is the history, not a taste of it.
            limit: null,
          ),
          _olderFooter(),
          // Below the history and the way past it: what is selling and where
          // to look next, for the shopper who has reached the end of their
          // own list and wants somewhere to go.
          DiscoverMoreSection(
            onSeeAll: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BrowseScreen())),
          ),
        ],
      );
    }

    // Grouped by day, in the order the entries already carry -- newest first,
    // so the headings run Today, Yesterday, then dates.
    final groups = <String, List<_HistoryEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(formatDateHeading(entry.at), () => []).add(entry);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // No side inset of its own: each card takes its own share of the width
      // and centres in it, so the margin scales with the screen.
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              group.key,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // Only the purchased tab reaches here now: the viewed tab is drawn
          // by [RecentViewsSection] above, and an order line is not a row
          // anybody removes from their own history.
          for (final entry in group.value)
            _HistoryCard(
              entry: entry,
              onTap: () => _open(entry),
              onAdd: () => _addToCart(entry),
            ),
        ],
      ],
    );
  }

  /// "See older history", and what it has to say for itself.
  ///
  /// Below the list, as asked. It only appears on the viewed tab: the
  /// purchased half is the order book, which loads whole.
  Widget _olderFooter() {
    final theme = Theme.of(context);

    final error = _olderError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
        child: Column(
          children: [
            Text(
              error.isNetwork
                  ? 'No connection, so older history could not be loaded.'
                  : error.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: _loadOlder, child: const Text('Try again')),
          ],
        ),
      );
    }

    if (!_hasOlder) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 4),
        child: Text(
          'That is the whole history.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
      child: Center(
        // While a batch is on its way the button stays where it is, says so
        // with a spinner in place of its icon, and takes no second tap -- the
        // cards above stay exactly as they are.
        child: OutlinedButton.icon(
          key: const ValueKey('history-load-more'),
          onPressed: _loadingOlder ? null : _loadOlder,
          icon: _loadingOlder
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.history, size: 18),
          label: const Text('Load More'),
        ),
      ),
    );
  }
}

/// One row, laid out as the reference has it: picture, title and category,
/// price, attributes, the time it happened, and a way into the cart.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.onTap, this.onAdd});

  final _HistoryEntry entry;
  final VoidCallback onTap;

  /// Null where the row is not one to buy from.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = entry.priceText;

    // 97% of the page, centred in it, so the margin is a share of the screen
    // rather than a fixed inset.
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.97,
        child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // One 92pt square for every row, whatever shape the
                  // seller's photograph is: contained rather than cropped,
                  // so nothing is cut off or stretched, and centred in a
                  // tile of the page's own wash so the picture sits in the
                  // same place on every card.
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ArtworkPanel(
                      icon: Icons.inventory_2_outlined,
                      tint: theme.colorScheme.primary,
                      imageUrl: entry.imageUrl,
                      iconScale: 0.4,
                      knownWidth: 92,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        if (entry.subtitle != null &&
                            entry.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            entry.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (price != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            price,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                        if (entry.variant != null &&
                            entry.variant!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            entry.variant!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatTime(entry.at),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (onAdd case final add?) ...[
                        const SizedBox(height: 10),
                        _AddButton(onTap: add),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The circular cart button with its caption, as the reference draws it.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.dividerColor),
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add to cart',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      // A list, so pull-to-refresh still works with nothing on screen.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}

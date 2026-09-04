import 'dart:async';

import 'package:flutter/material.dart';

import '../../cart/presentation/cart_screen.dart';
import '../../../core/ui/action_status.dart';
import '../../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../catalog/data/product.dart' show productStub;
import '../../catalog/presentation/catalog_visuals.dart' show openProduct;
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../orders/data/order_store.dart';
import '../data/hidden_history_store.dart';
import '../data/product_views_repository.dart';

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

  /// How many rows to ask the server for.
  ///
  /// The list is fetched whole at this size rather than stitched from pages:
  /// `/product-views` takes a limit and nothing else, so asking for more and
  /// replacing what is held is both the paging this endpoint supports and the
  /// one arrangement that cannot show a row twice.
  static const _pageSize = 40;

  int _limit = _pageSize;

  /// False once the server has answered with no more than it did last time --
  /// which is what "there is nothing older" looks like on a limit-only route.
  bool _hasOlder = true;

  bool _loadingOlder = false;
  ApiError? _olderError;

  /// True while the shopper is picking rows to hide.
  bool _selecting = false;

  /// The rows ticked, by [_HistoryEntry.key].
  final Set<String> _selected = {};

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
    try {
      final views = await ProductViewsRepository.instance.list(limit: _limit);
      // The rows this shopper has hidden from their own view. Read here so the
      // first paint already has them filtered out.
      await HiddenHistoryStore.instance.load();
      // The purchased tab reads the orders this app already holds.
      await OrderStore.instance.refreshFromServer();
      if (!mounted) return;
      setState(() {
        _views = views;
        _loading = false;
        // A short answer to a full-size request means the server has nothing
        // beyond it.
        _hasOlder = views.length >= _limit;
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

  /// Asks for a page deeper into the same history.
  ///
  /// Nothing is appended: the bigger request is the same list plus what came
  /// before it, so the answer replaces what is held. That is why this cannot
  /// duplicate a row however many times it is pressed.
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder) return;
    setState(() {
      _loadingOlder = true;
      _olderError = null;
    });

    final asked = _limit + _pageSize;
    try {
      final views = await ProductViewsRepository.instance.list(limit: asked);
      if (!mounted) return;
      setState(() {
        _loadingOlder = false;
        // Nothing new came back, so this is the end of the history.
        _hasOlder = views.length > _views.length && views.length >= asked;
        if (views.length > _views.length) {
          _views = views;
          _limit = asked;
        } else {
          _hasOlder = false;
        }
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOlder = false;
        _olderError = e;
      });
    }
  }

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

  /// Enters selection mode on the row that was held down.
  void _startSelecting(_HistoryEntry entry) {
    setState(() {
      _selecting = true;
      _selected.add(entry.key);
    });
  }

  void _toggle(_HistoryEntry entry) {
    setState(() {
      if (!_selected.remove(entry.key)) _selected.add(entry.key);
      // The last one unticked leaves selection mode, so the list is not stuck
      // in a mode with nothing in it.
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _endSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  /// Hides the ticked rows from this shopper's own history.
  ///
  /// **The server keeps them.** This list is the read side of
  /// `/product-views`, and what is deleted here is the shopper's view of it --
  /// see [HiddenHistoryStore]. Nothing is sent, no other account is touched,
  /// and the product itself is not affected.
  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(count == 1 ? 'Remove 1 item?' : 'Remove $count items?'),
        content: Text(
          count == 1
              ? 'It is removed from your history on this device. Your orders '
                    'are not affected.'
              : 'They are removed from your history on this device. Your '
                    'orders are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    final hidden = Set<String>.from(_selected);
    await HiddenHistoryStore.instance.hide(hidden);
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(count == 1 ? '1 item removed' : '$count items removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await HiddenHistoryStore.instance.show(hidden);
              if (mounted) setState(() {});
            },
          ),
        ),
      );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _remove(_HistoryEntry entry) async {
    final before = _views;
    setState(
      () => _views = [
        for (final view in _views)
          if (view.productId != entry.productId) view,
      ],
    );
    try {
      await ProductViewsRepository.instance.remove(entry.productId);
    } on ApiError catch (e) {
      // Put it back: a row that vanished here and stayed on the server would
      // return on the next open, which reads as the removal being ignored.
      if (!mounted) return;
      setState(() => _views = before);
      _say(e.message);
    }
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

    // Selection owns the bar while it is on: the count is the title and the
    // only actions are the two that apply to a selection.
    if (_selecting) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel selection',
            onPressed: _endSelecting,
          ),
          title: Text(
            _selected.length == 1
                ? '1 selected'
                : '${_selected.length} selected',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove from history',
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            ),
          ],
        ),
        // Back leaves selection rather than the page, which is what a shopper
        // who pressed Back expects of a mode they are in.
        body: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _endSelecting();
          },
          child: _tab(_visible(_viewed), removable: true),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
      );
    }

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
    if (_loading) return const Center(child: CircularProgressIndicator());

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

    // Grouped by day, in the order the entries already carry -- newest first,
    // so the headings run Today, Yesterday, then dates.
    final groups = <String, List<_HistoryEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(formatDateHeading(entry.at), () => []).add(entry);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
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
          for (final entry in group.value)
            if (!removable)
              _HistoryCard(
                entry: entry,
                onTap: () => _open(entry),
                onAdd: () => _addToCart(entry),
              )
            else if (_selecting)
              // No swipe while selecting: the gesture would fight the tick,
              // and the two mean different things -- one forgets the row on
              // the server, the other hides it here.
              _HistoryCard(
                entry: entry,
                selecting: true,
                selected: _selected.contains(entry.key),
                onTap: () => _toggle(entry),
                onLongPress: () => _toggle(entry),
              )
            else
              Dismissible(
                key: ValueKey('history-${entry.productId}-${entry.at}'),
                direction: DismissDirection.endToStart,
                background: const _RemoveBackground(),
                onDismissed: (_) => unawaited(_remove(entry)),
                child: _HistoryCard(
                  entry: entry,
                  onTap: () => _open(entry),
                  onAdd: () => _addToCart(entry),
                  onLongPress: () => _startSelecting(entry),
                ),
              ),
        ],
        if (removable) _olderFooter(),
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

    if (_loadingOlder) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
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
        child: OutlinedButton.icon(
          onPressed: _loadOlder,
          icon: const Icon(Icons.history, size: 18),
          label: const Text('See older history'),
        ),
      ),
    );
  }
}

/// One row, laid out as the reference has it: picture, title and category,
/// price, attributes, the time it happened, and a way into the cart.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.onTap,
    this.onAdd,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final _HistoryEntry entry;
  final VoidCallback onTap;

  /// Null while picking rows: Add to cart is not what a tick is for, and a
  /// button that still acted would fire on a press meant for the row.
  final VoidCallback? onAdd;

  /// Long press to start picking -- and, with a mouse, a right-click, which is
  /// the same intent on a desktop window.
  final VoidCallback? onLongPress;

  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = entry.priceText;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      // The picked state is the theme's own selection tint over the card
      // colour, so nothing about the card's shape, radius or spacing moves as
      // rows are ticked.
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : null,
      child: GestureDetector(
        onSecondaryTap: onLongPress,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selecting) ...[
                  // Drawn rather than tapped: the whole row is the target, so
                  // the box says what state it is in and the row answers.
                  Padding(
                    padding: const EdgeInsets.only(top: 34),
                    child: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                SizedBox(
                  width: 92,
                  height: 92,
                  child: ArtworkPanel(
                    icon: Icons.inventory_2_outlined,
                    tint: theme.colorScheme.primary,
                    imageUrl: entry.imageUrl,
                    iconScale: 0.4,
                    knownWidth: 92,
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

/// What a swipe reveals, so the gesture says what it will do before it does it.
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.only(right: 20),
    alignment: Alignment.centerRight,
    decoration: BoxDecoration(
      color: AppColors.destructiveLight.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.delete_outline, color: AppColors.destructiveLight),
  );
}

/// The empty, signed-out and failed states.
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

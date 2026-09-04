import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/data/product.dart';
import '../../home/widgets/product_grid.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../data/corporate_gifts_repository.dart';
import 'corporate_gifts_skeleton.dart';

/// The Corporate Gifts collection.
///
/// Where the home page's Corporate Gifts banner goes. It is a curated
/// collection the shop maintains, not a filter over the whole catalogue, so
/// this lists what is in it and nothing else -- and the search box searches
/// that collection and only that collection.
///
/// The search runs on the server: each settled keystroke is a request with `q`
/// on it, the one before is cancelled, and the results are the server's
/// answer. See [CorporateGiftsRepository].
class CorporateGiftsScreen extends StatefulWidget {
  const CorporateGiftsScreen({super.key});

  @override
  State<CorporateGiftsScreen> createState() => _CorporateGiftsScreenState();
}

class _CorporateGiftsScreenState extends State<CorporateGiftsScreen> {
  final _query = TextEditingController();
  final _scroll = ScrollController();

  List<Product> _products = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  ApiError? _error;

  /// What the results on screen answer to. Held apart from the field so a
  /// keystroke does not re-run the search until the typing settles, and so the
  /// empty state can quote what was actually searched for.
  String _searched = '';

  /// True until the first answer arrives, so an empty collection can be told
  /// apart from a search that matched nothing.
  bool _everLoaded = false;

  Timer? _debounce;

  /// The request the current keystroke started, so the next one can drop it.
  CancelToken? _inFlight;

  /// Counts searches, so a slow answer to an old query cannot overwrite a fast
  /// answer to a newer one.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
    // The saved list, so a product already on it arrives here with a filled
    // heart rather than an empty one.
    WishlistStore.instance.load();
    _scroll.addListener(_onScroll);
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inFlight?.cancel('screen closed');
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  /// A keystroke. The request waits for a pause in the typing.
  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    // Short enough that a pause between words feels instant, long enough that
    // a word typed at speed is one request rather than six.
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_search(value)),
    );
  }

  void _submit(String value) {
    _debounce?.cancel();
    unawaited(_search(value));
    FocusScope.of(context).unfocus();
  }

  void _clear() {
    _query.clear();
    _submit('');
  }

  /// Asks the server for [query] and shows what comes back.
  Future<void> _search(String query) async {
    final generation = ++_generation;

    // Whatever the last keystroke started is no longer wanted. Cancelled
    // rather than merely ignored: an abandoned request still holds the
    // connection the current one needs.
    _inFlight?.cancel('superseded');
    final token = CancelToken();
    _inFlight = token;

    setState(() {
      _loading = true;
      _error = null;
      _searched = query.trim();
    });

    try {
      final page = await CorporateGiftsRepository.instance.page(
        query: query,
        cancelToken: token,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _products = page.products;
        _total = page.total;
        _loading = false;
        _everLoaded = true;
      });
    } on ApiError catch (e) {
      // A cancelled request is not a failure -- it is this screen deciding it
      // no longer wants the answer.
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
        // The products on screen answered the last query, not this one.
        // Leaving them under a search that failed would read as its results.
        _products = const [];
        _total = 0;
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    unawaited(_more());
  }

  /// The next page of whatever is currently being shown.
  Future<void> _more() async {
    if (_loading || _loadingMore || _products.length >= _total) return;

    final generation = _generation;
    setState(() => _loadingMore = true);

    try {
      final page = await CorporateGiftsRepository.instance.page(
        query: _searched,
        offset: _products.length,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _products = [..._products, ...page.products];
        _total = page.total;
        _loadingMore = false;
      });
    } on ApiError {
      // The page already on screen is still good; a failed "load more" leaves
      // it alone rather than replacing it with an error panel. Scrolling to
      // the end again tries once more.
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Corporate gifts'),
        actions: [
          ListenableBuilder(
            listenable: CartStore.instance,
            builder: (context, _) => IconButton(
              icon: Badge.count(
                count: CartStore.instance.count,
                isLabelVisible: CartStore.instance.count > 0,
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              tooltip: 'Cart',
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CartScreen())),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    // Shaped like the page it stands in for, rather than a spinner in the
    // middle of an empty screen -- but only for the first load. A search
    // replaces the grid, not the whole page, so the box stays where it is and
    // keeps the focus the shopper is typing into.
    if (_loading && !_everLoaded) return const CorporateGiftsSkeleton();

    if (_error case final failure?) {
      return LoadFailed(
        message: failure.isNetwork
            ? 'No connection, so the corporate gifts could not be loaded.'
            : failure.message,
        onRetry: () => unawaited(_search(_searched)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Search corporate gifts',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear',
                      onPressed: _clear,
                    ),
            ),
          ),
        ),
        Expanded(child: _results()),
      ],
    );
  }

  Widget _results() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searched.isEmpty
                ? 'There are no corporate gifts just now.'
                : 'No corporate gifts match “$_searched”.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _search(_searched),
      // Rebuilt when the saved list changes: [ProductGrid] reads WishlistStore
      // as it builds, so without a listener a tap would save the product and
      // leave the card showing the old heart.
      child: ListenableBuilder(
        listenable: WishlistStore.instance,
        builder: (context, _) => ListView(
          controller: _scroll,
          children: [
            ProductGrid(
              title: 'Corporate gifts',
              subtitle:
                  'Gift sets and desk pieces, curated for business gifting.',
              products: _products,
            ),
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

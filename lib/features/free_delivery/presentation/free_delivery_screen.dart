import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/data/product.dart';
import '../../home/widgets/product_grid.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../data/free_delivery_repository.dart';
import 'free_delivery_skeleton.dart';
import '../data/free_delivery_search.dart';

/// The products the shop delivers free.
///
/// Where the home page's Free Delivery card goes. It is a real collection --
/// the server keeps hundreds of them -- rather than a filter over the whole
/// catalogue, so this lists what is in it and nothing else.
///
/// The search box searches that collection and only that collection. See
/// [FreeDeliveryIndex] for why it runs here rather than as a request.
class FreeDeliveryScreen extends StatefulWidget {
  const FreeDeliveryScreen({super.key});

  @override
  State<FreeDeliveryScreen> createState() => _FreeDeliveryScreenState();
}

class _FreeDeliveryScreenState extends State<FreeDeliveryScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  FreeDeliveryIndex? _index;
  List<Product> _products = const [];
  List<String> _suggestions = const [];
  bool _loading = true;
  ApiError? _error;

  /// What the results currently answer to. Held apart from the field so a
  /// keystroke does not re-run the search until the typing settles.
  String _searched = '';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
    _focus.addListener(() => setState(() {}));
    // The saved list, so a product already on it arrives here with a filled
    // heart. Without this the cards drew unsaved until something else in the
    // app happened to load the list.
    WishlistStore.instance.load();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listings = await FreeDeliveryRepository.instance.listings();
      if (!mounted) return;
      setState(() {
        // Built once per load. Folding every title here is what makes each
        // keystroke a scan of prepared strings rather than 557 lowercasings.
        _index = FreeDeliveryIndex(listings);
        _loading = false;
      });
      _apply(_searched);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// A keystroke. Suggestions keep up with it; the results wait for a pause.
  void _onChanged(String value) {
    setState(() {
      _suggestions = _index?.suggest(value) ?? const [];
    });

    _debounce?.cancel();
    // Short enough that a pause between words feels instantaneous, long
    // enough that a word typed at speed is matched once rather than six times.
    _debounce = Timer(const Duration(milliseconds: 180), () => _apply(value));
  }

  /// Runs the search now, whatever the debounce was waiting for.
  void _apply(String value) {
    final index = _index;
    if (index == null || !mounted) return;
    setState(() {
      _searched = value;
      _products = index.search(value);
    });
  }

  void _submit(String value) {
    _debounce?.cancel();
    _apply(value);
    _focus.unfocus();
  }

  void _use(String suggestion) {
    _query
      ..text = suggestion
      ..selection = TextSelection.collapsed(offset: suggestion.length);
    setState(() => _suggestions = const []);
    _submit(suggestion);
  }

  void _clear() {
    _query.clear();
    setState(() => _suggestions = const []);
    _submit('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Free delivery'),
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
    // Shaped like the page it is standing in for, rather than a spinner in
    // the middle of an empty screen. See [FreeDeliverySkeleton].
    if (_loading) return const FreeDeliverySkeleton();

    if (_error case final failure?) {
      return LoadFailed(
        message: failure.isNetwork
            ? 'No connection, so the free delivery products could not be '
                  'loaded.'
            : failure.message,
        onRetry: _load,
      );
    }

    // Nothing in the collection at all, which is not the same as nothing
    // matching a search: there is no point offering a box to search an empty
    // collection with.
    if (_index?.all.isEmpty ?? true) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nothing is on free delivery just now.'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _query,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Search free delivery products',
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
        if (_focus.hasFocus && _suggestions.isNotEmpty)
          _Suggestions(terms: _suggestions, onTap: _use),
        Expanded(child: _results()),
      ],
    );
  }

  Widget _results() {
    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No free delivery products match “$_searched”.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      // Rebuilt when the saved list changes, which is what the hearts on these
      // cards were missing. [ProductGrid] reads WishlistStore as it builds, so
      // it draws the right state -- but nothing here was listening, so a tap
      // saved the product and left the card showing the old heart until the
      // screen was left and come back to.
      //
      // The home page's cards never had this: the whole home shell rebuilds on
      // the same store. This screen is its own route and had no such listener.
      child: ListenableBuilder(
        listenable: WishlistStore.instance,
        builder: (context, _) => ListView(
          children: [
            ProductGrid(
              title: 'Delivered free',
              subtitle: 'Every one of these ships at no delivery charge.',
              products: _products,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// What the collection can offer for what has been typed so far.
///
/// Sits between the box and the results rather than floating over them, so it
/// never covers the products it is meant to lead to, and it takes only the
/// room its terms need.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.terms, required this.onTap});

  final List<String> terms;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 232),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: terms.length,
        itemBuilder: (context, i) => InkWell(
          onTap: () => onTap(terms[i]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.north_west,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    terms[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

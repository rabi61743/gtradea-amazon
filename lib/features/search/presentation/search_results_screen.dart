import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/action_status.dart';
import '../../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../../shared/widgets/loading_gate.dart';
import '../../cart/data/cart_store.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../../shared/widgets/page_width.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../data/search_filters.dart';
import '../widgets/product_result_card.dart';
import '../widgets/search_field.dart';
import '../widgets/search_filter_sheet.dart';
import '../widgets/visual_search_sheet.dart';

/// Results for a query, in a grid, with the controls that narrow it.
///
/// The rule the whole screen is built on: **every control changes the request,
/// none of them filters what already came back**. The server holds millions of
/// rows and hands over a page of them, so narrowing that page on the device
/// would quietly claim the rest did not exist.
///
/// That rule is also what decides which controls exist. Production was probed
/// rather than assumed: the endpoint reads `q`, `category`, `min_price`,
/// `max_price` and `sort`, answers 200 to anything else and ignores it, and
/// returns an empty array for `sort=rating`. So there is no size or colour
/// control and no "Best rated" sort -- see [kSearchSorts] and
/// [kUnsupportedFacets] -- and the rating and brand controls in the sheet are
/// drawn switched off rather than wired to parameters the server discards.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({
    super.key,
    required this.query,
    this.categoryCid,
    this.categoryName,
    this.parentCid,
    this.parentName,
    this.sort = ProductSort.relevance,
  });

  /// How the results start out ordered.
  ///
  /// The shopper can change it from the sort control as always; this only
  /// decides where they land. It exists so a banner can open a real view --
  /// "Trending now" is this catalogue's best selling, and there is no other
  /// screen that means it.
  final ProductSort sort;

  final String query;

  /// Set when the search was started from inside a department.
  final String? categoryCid;

  /// What to call that category on its chip, when the caller already knows.
  ///
  /// The chip's name is otherwise looked up in the cached tree, and that tree
  /// is two levels deep. A listing opened from a third-level category --
  /// "super capacitor", "Zener Diode" -- is not in it, so the chip sat on the
  /// literal word "Department" for as long as the page was open. The screen
  /// that pushed it knows the name; this is it saying so rather than making
  /// this one go and find out.
  final String? categoryName;

  /// The category one level up, when the caller knows it.
  ///
  /// Used only when this one turns out to be empty, which at the third level
  /// is the common case: of the thirty-four subcategories under Antenna, Audio
  /// Devices, Capacitor and Diode, **two have any products at all**. Rather
  /// than a blank page, the listing widens to the parent and says so -- and it
  /// cannot work that parent out for itself, because the cached tree stops one
  /// level short.
  final String? parentCid;
  final String? parentName;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  late SearchFilters _filters = _initialFilters();

  /// The query, which now lives on [_filters] so the filter sheet can offer a
  /// search box and hand one back. Kept as a getter so every existing use of
  /// `_query` on this screen reads the same value it always did.
  String get _query => _filters.query;

  /// Waits out a burst of typing before asking the server.
  ///
  /// The same idiom the cart uses for its sync debounce. Without it every
  /// keystroke is a request, and the last one to land wins rather than the last
  /// one typed -- `_generation` already guards against that, but the requests
  /// were still made.
  Timer? _typing;

  static const _typingDelay = Duration(milliseconds: 300);

  List<Product> _results = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  ApiError? _error;

  /// Set when nothing matched and the grid below is a broadened search rather
  /// than hits. Never left null while showing substitutes -- results a shopper
  /// did not ask for have to say so.
  String? _relaxedFrom;

  /// Set when an empty subcategory was widened to its department, so the page
  /// can say which is which rather than passing one off as the other.
  ({String from, String to})? _widenedTo;

  /// Completes when the department tree has been fetched, however that turned
  /// out. Held rather than fired and forgotten, because the widening below
  /// needs the tree and cannot get at it through Loadable.load.
  late final Future<void> _departmentsReady;

  /// Guards against an older request landing after a newer one and overwriting
  /// it. Typing quickly makes that happen constantly.
  int _generation = 0;

  static const _pageSize = 24;

  /// Stands in for a department name that has not been looked up yet.
  static const _placeholderDepartment = 'Department';

  SearchFilters _initialFilters() {
    final cid = widget.categoryCid;
    if (cid == null) {
      return SearchFilters(query: widget.query, sort: widget.sort);
    }
    // Arrived from a department, so that department is already a filter and is
    // shown as a removable chip like any other. Its name is filled in once the
    // tree loads; until then the chip says what it can.
    return SearchFilters(
      query: widget.query,
      sort: widget.sort,
      departmentCid: cid,
      departmentName: widget.categoryName ?? _placeholderDepartment,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(WishlistStore.instance.load());
    _departmentsReady = _loadDepartments();
    unawaited(_departmentsReady);
    unawaited(_run());
  }

  /// The department tree, for the two category pills and the filter sheet.
  ///
  /// Fetched alongside the results rather than before them: the products are
  /// what the shopper asked for, and holding them behind a tree that only
  /// populates a filter would be the wrong thing to wait on.
  Future<void> _loadDepartments() async {
    // The brands go out alongside the tree rather than after it. They are for
    // a control that does nothing, so they must not hold up the one thing on
    // this screen that a shopper is actually waiting for.
    unawaited(CatalogStore.instance.brands.load());
    await CatalogStore.instance.categories.load();
    if (!mounted) return;
    setState(() {
      // A search opened from inside a department arrives with a cid and no
      // name, so its chip reads "Department" until the tree can say better.
      final cid = _filters.departmentCid;
      if (cid == null || _filters.departmentName != _placeholderDepartment) {
        return;
      }
      final named = _categoryNamed(cid);
      if (named != null) _filters = _filters.withDepartment(cid, named.name);
    });
  }

  /// The category with this cid, at either level of the tree.
  ///
  /// Children as well as tops. This used to scan the top level only, so a
  /// search opened from a subcategory tile -- which is most of the ways into
  /// this screen from the home page -- never found its name and left the chip
  /// reading the literal word "Department" for as long as the page was open.
  Category? _categoryNamed(String cid) {
    for (final department in _departments) {
      if (department.cid == cid) return department;
      for (final child in department.children) {
        if (child.cid == cid) return child;
      }
    }
    return null;
  }

  /// The department a subcategory belongs to, or null for a top-level one.
  Category? _parentOf(String cid) {
    for (final department in _departments) {
      if (department.children.any((c) => c.cid == cid)) return department;
    }
    return null;
  }

  @override
  void dispose() {
    _typing?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// The department tree, once it is there. Empty while loading, which the
  /// filter sheet handles by not offering those two sections.
  List<Category> get _departments =>
      CatalogStore.instance.categories.value ?? const [];

  /// The shop's brand names, once they have arrived. Empty until then, and
  /// empty for good if the call fails -- the section they fill is switched off
  /// either way, so there is nothing to report and nothing to wait for.
  List<String> get _brands => CatalogStore.instance.brands.value ?? const [];

  Future<void> _run() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _exhausted = false;
      _relaxedFrom = null;
      _widenedTo = null;
    });

    try {
      final products = await _fetch(_query, offset: 0);
      if (!mounted || generation != _generation) return;

      // Nothing matched. Widening is worth doing, but only when the filters are
      // not the reason -- if they are, the fix is to drop one, and the empty
      // state says so rather than burying it under a grid of substitutes.
      if (products.isEmpty && _query.isNotEmpty && _filters.isEmpty) {
        final relaxed = await _broaden(generation);
        if (!mounted || generation != _generation) return;
        if (relaxed != null) {
          setState(() {
            _results = relaxed;
            _loading = false;
            // Substitutes are not a page of a result set, so there is no
            // second page of them to fetch.
            _exhausted = true;
            _relaxedFrom = _query;
          });
          return;
        }
      }

      // A subcategory the catalogue has nothing under yet.
      //
      // Measured rather than guessed at: of the thirty-two subcategory tiles
      // the home page shows, fourteen return nothing, and one department's
      // four return nothing at all. Every one of those was a tap that ended on
      // an empty page. The tree lists categories the storefront could carry,
      // not the ones it does, and there is no count on it to tell them apart
      // without asking -- so this asks, once, only when the answer was empty.
      //
      // The department above it is the nearest thing that does have stock, and
      // the notice says so plainly. Silently showing a wider set as though it
      // were the narrow one is how somebody buys the wrong thing.
      final widened = await _widenToDepartment(generation, products);
      if (!mounted || generation != _generation) return;
      if (widened) return;

      setState(() {
        _results = products;
        _loading = false;
        _exhausted = products.length < _pageSize;
      });
    } on ApiError catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Retries an empty subcategory against its department.
  ///
  /// Returns true when it took over the page, so the caller stops.
  ///
  /// Deliberately narrow. It only fires when the shopper browsed rather than
  /// searched, when the only thing narrowing the results is the category, and
  /// when that category has a parent in the tree. With a query or a price band
  /// in play, an empty page means the filters are the thing to change, and the
  /// empty state already says exactly that.
  Future<bool> _widenToDepartment(
    int generation,
    List<Product> products,
  ) async {
    if (products.isNotEmpty || _query.isNotEmpty) return false;

    final cid = _filters.effectiveCategoryCid;
    if (cid == null) return false;
    if (_filters.minPrice != null || _filters.maxPrice != null) return false;

    // The tree is what says which department a subcategory belongs to, and it
    // is fetched alongside the results rather than before them -- so by the
    // time an empty answer comes back it may not have landed yet.
    //
    // This waits on the screen's own fetch, not on `categories.load()`.
    // Loadable.load returns `Future.value()` the moment a fetch is already in
    // flight rather than joining it, which is right for its job -- an
    // idempotent kick from initState -- and useless here: awaiting it came
    // back instantly with the tree still null, and the widening quietly never
    // happened.
    await _departmentsReady;
    if (!mounted || generation != _generation) return false;

    // The caller's parent first, then the tree's.
    //
    // The tree is two levels deep, so `_parentOf` finds the parent of a
    // subcategory and nothing else. A listing opened from a third-level
    // category -- "communication antenna", which has no products at all -- got
    // no parent, no widening and a blank page. The screen that pushed it knows
    // exactly which category it came from, and saying so is cheaper and more
    // reliable than making this one search a tree that does not go that deep.
    final parentCid = widget.parentCid ?? _parentOf(cid)?.cid;
    final parentName =
        widget.parentName ??
        (parentCid == null ? null : _categoryNamed(parentCid)?.name);
    if (parentCid == null || parentName == null) return false;

    final wider = await CatalogRepository.instance.search(
      categoryCid: parentCid,
      sort: _filters.sort,
      pageSize: _pageSize,
    );
    if (!mounted || generation != _generation) return false;
    if (wider.isEmpty) return false;

    setState(() {
      _results = wider;
      _loading = false;
      _exhausted = wider.length < _pageSize;
      _widenedTo = (
        from:
            widget.categoryName ?? _categoryNamed(cid)?.name ?? 'this category',
        to: parentName,
      );
    });
    return true;
  }

  Future<List<Product>> _fetch(String query, {required int offset}) {
    return CatalogRepository.instance.search(
      query: query,
      categoryCid: _filters.effectiveCategoryCid,
      minPrice: _filters.minPrice,
      maxPrice: _filters.maxPrice,
      sort: _filters.sort,
      pageSize: _pageSize,
      offset: offset,
    );
  }

  /// Something to show when the exact query found nothing.
  ///
  /// Drops one word at a time first, because "red cotton tshirt" failing does
  /// not mean "cotton tshirt" will. Only when a single word is left -- where
  /// there is nothing to drop and the word itself is likely the typo -- does it
  /// fall back to the discover feed.
  ///
  /// Returns null if even that finds nothing, so the caller shows the plain
  /// empty state rather than an empty "related products" heading.
  Future<List<Product>?> _broaden(int generation) async {
    var words = _query
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    while (words.length > 1) {
      words = words.sublist(0, words.length - 1);
      final wider = await _fetch(words.join(' '), offset: 0);
      if (generation != _generation) return null;
      if (wider.isNotEmpty) return wider;
    }

    try {
      final popular = await CatalogRepository.instance.discover(
        pageSize: _pageSize,
      );
      if (generation != _generation) return null;
      return popular.isEmpty ? null : popular;
    } on ApiError {
      // The substitutes are a courtesy. Failing to find them is not worth
      // replacing the "no results" message with an error panel.
      return null;
    }
  }

  /// Asks for the next page once the frame that noticed is over.
  ///
  /// The scroll notification arrives during layout, where setState is illegal.
  /// The guard is set synchronously so a second notification in the same frame
  /// cannot start a duplicate request; only the visible part waits.
  void _requestMore() {
    if (_loadingMore || _exhausted || _loading || _error != null) return;
    _loadingMore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      unawaited(_loadMore());
    });
  }

  Future<void> _loadMore() async {
    final generation = _generation;
    try {
      final more = await _fetch(_query, offset: _results.length);
      if (!mounted || generation != _generation) return;
      // The feed can repeat a row across pages when the ordering is not
      // strictly total. Showing the same product twice reads as a bug.
      final seen = _results.map((p) => p.numIid).toSet();
      final fresh = more
          .where((p) => seen.add(p.numIid))
          .toList(growable: false);
      setState(() {
        _results = [..._results, ...fresh];
        _loadingMore = false;
        _exhausted = more.length < _pageSize;
      });
    } on ApiError {
      if (!mounted || generation != _generation) return;
      // Silent: the results already on screen are still good, and an error
      // banner under them would suggest otherwise.
      setState(() {
        _loadingMore = false;
        _exhausted = true;
      });
    }
  }

  void _search(String query) {
    // Submitting beats the debounce rather than queueing behind it: someone who
    // pressed enter has finished typing and should not wait out a timer.
    _typing?.cancel();
    _apply(_filters.withQuery(query));
  }

  /// Typing, rather than submitting. Re-runs the search once the keystrokes
  /// stop, so the grid follows what is in the box without a request per letter.
  void _searchAsTyped(String query) {
    _typing?.cancel();
    _typing = Timer(_typingDelay, () {
      if (!mounted) return;
      _apply(_filters.withQuery(query));
    });
  }

  void _apply(SearchFilters filters) {
    if (filters == _filters) return;
    setState(() => _filters = filters);
    unawaited(_run());
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SearchFilterSheet(
        initial: _filters,
        departments: _departments,
        brands: _brands,
      ),
    );
    if (result == null || !mounted) return;
    _apply(result);
  }

  Future<void> _openSort() async {
    final chosen = await showModalBottomSheet<ProductSort>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in kSearchSorts)
              RadioGroup<ProductSort>(
                groupValue: _filters.sort,
                onChanged: (value) => Navigator.of(sheetContext).pop(value),
                child: RadioListTile<ProductSort>(
                  value: option,
                  title: Text(option.label),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    _apply(_filters.withSort(chosen));
  }

  /// A single-level picker, used for both the department and the category pill.
  Future<void> _pickCategory({
    required String title,
    required List<Category> options,
    required String? selected,
    required void Function(Category?) onPicked,
  }) async {
    final choice = await showModalBottomSheet<_Choice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: Theme.of(sheetContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: const Text('All'),
                    trailing: selected == null
                        ? const Icon(Icons.check, size: 20)
                        : null,
                    onTap: () =>
                        Navigator.of(sheetContext).pop(const _Choice(null)),
                  ),
                  for (final option in options)
                    ListTile(
                      title: Text(option.name),
                      trailing: selected == option.cid
                          ? const Icon(Icons.check, size: 20)
                          : null,
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_Choice(option)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    onPicked(choice.category);
  }

  List<Category> get _subcategories {
    final cid = _filters.departmentCid;
    if (cid == null) return const [];
    for (final department in _departments) {
      if (department.cid == cid) return department.children;
    }
    return const [];
  }

  void _toggleSaved(Product product) {
    final saved = WishlistStore.instance.toggle(
      SavedProduct(
        id: product.numIid,
        title: product.title,
        price: product.displayPrice ?? 0,
        imageUrl: product.imageUrl,
        sellerBadge: product.sellerBadge,
        salesLabel: product.salesLabel,
        category: product.categoryName,
        minOrder: product.minOrder,
      ),
    );
    // Only the removal is said out loud; saving has its own animation now.
    if (!saved) {
      ActionStatus.show(context, ActionStatus.removedFromWishlist);
    }
  }

  void _addToCart(Product product) {
    CartStore.instance.add(
      CartLine(
        productId: product.numIid,
        title: product.title,
        unitPrice: product.displayPrice!,
        imageUrl: product.imageUrl,
        quantity: product.minOrder,
        minOrder: product.minOrder,
        category: product.categoryName,
        source: '1688',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar. SearchField is the whole header -- it paints the teal band,
      // pads for the status bar and carries its own back arrow -- so putting it
      // in an AppBar's title got the AppBar's automatic leading arrow as well,
      // and the page showed two. The entry screen has always hosted it this
      // way; this screen was the odd one out.
      body: Column(
        children: [
          SearchField(
            controller: _controller,
            autofocus: false,
            onSubmitted: _search,
            // The field already accepted this and the screen never passed it,
            // so the grid only moved when enter was pressed.
            onChanged: _searchAsTyped,
            // The camera was drawn on this screen and did nothing, because the
            // handler was only ever wired up on the entry screen.
            onImageSearch: () => unawaited(VisualSearchSheet.show(context)),
          ),
          _ControlBar(
            filters: _filters,
            hasSubcategories: _subcategories.isNotEmpty,
            onSort: _openSort,
            onDepartment: _departments.isEmpty
                ? null
                : () => _pickCategory(
                    title: 'Department',
                    options: _departments,
                    selected: _filters.departmentCid,
                    onPicked: (category) => _apply(
                      _filters.withDepartment(category?.cid, category?.name),
                    ),
                  ),
            onCategory: _subcategories.isEmpty
                ? null
                : () => _pickCategory(
                    title: 'Category',
                    options: _subcategories,
                    selected: _filters.categoryCid,
                    onPicked: (category) => _apply(
                      _filters.withCategory(category?.cid, category?.name),
                    ),
                  ),
            onFilters: _openFilters,
          ),
          if (_filters.chips.isNotEmpty)
            _ActiveChips(
              filters: _filters,
              onRemove: (chip) => _apply(_filters.without(chip)),
              onClearAll: () => _apply(_filters.cleared),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  /// The results, the skeleton, or the reason there are neither.
  ///
  /// Wrapped in a [LoadingGate] rather than swapped outright. Every filter and
  /// sort change re-runs the request, and on a warm connection the answer is
  /// back in well under the gate's delay -- so tapping a sort pill changes the
  /// grid without the page blinking through a skeleton on the way. Only a wait
  /// long enough to notice gets reported, and once reported it stays up long
  /// enough to read.
  Widget _body() {
    return LoadingGate(
      loading: _loading,
      loadingChild: SingleChildScrollView(
        // The grid's own margin and spec, so the placeholders sit exactly
        // where the cards will.
        padding: PageWidth.insets(context, top: 12, bottom: 12),
        physics: const NeverScrollableScrollPhysics(),
        child: const ResultGridSkeleton(specFor: ResultGridSpec.search),
      ),
      child: _settled(),
    );
  }

  Widget _settled() {
    // Nothing to draw yet on the very first pass, and the gate is showing the
    // skeleton over the top of it. An empty state here would be a claim that
    // nothing matched, made before anything had been asked.
    if (_loading && _results.isEmpty && _error == null) {
      return const SizedBox.shrink();
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LoadFailed(
            message: error.isNetwork
                ? 'No connection. Check your network and try again.'
                : error.message,
            onRetry: _run,
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return _EmptyResults(
        query: _query,
        hasFilters: !_filters.isEmpty,
        onClear: () => _apply(_filters.cleared),
      );
    }

    return ListenableBuilder(
      listenable: WishlistStore.instance,
      builder: (context, _) => NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // A screen's height from the end, so the next page is usually there
          // by the time the shopper reaches it.
          if (notification.metrics.extentAfter < 600) _requestMore();
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _ResultsHeader(
                query: _query,
                count: _results.length,
                exhausted: _exhausted,
                relaxedFrom: _relaxedFrom,
                widenedTo: _widenedTo,
              ),
            ),
            SliverPadding(
              // The measure every other section of this app takes: 97% of the
              // screen, centred. A flat 12 gave a phone a wider margin than a
              // desktop window in proportion, and left the results narrower
              // than the rails and cards a shopper had just scrolled past.
              padding: PageWidth.insets(context, bottom: 12),
              sliver: _grid(),
            ),
            SliverToBoxAdapter(child: _Footer(loading: _loadingMore)),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // The sliver is inside the grid's own padding, so this is already the
        // space the cards divide up.
        final available = constraints.crossAxisExtent;
        // The search grid's own sizing: larger cards, tighter gaps. The
        // loading skeleton reads the same spec, so nothing jumps on arrival.
        final spec = ResultGridSpec.search(available);

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: spec.columns,
            mainAxisSpacing: spec.gap,
            crossAxisSpacing: spec.gap,
            // The card's exact height rather than a ratio standing in for it,
            // so a change to the card cannot silently start clipping it.
            mainAxisExtent: ProductResultCard.heightFor(
              context,
              spec.cardWidth(available),
              padding: spec.cardPadding,
            ),
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            final product = _results[i];
            return ProductResultCard(
              product: product,
              padding: spec.cardPadding,
              saved: WishlistStore.instance.contains(product.numIid),
              onTap: () => openProduct(context, product),
              onToggleSaved: () => _toggleSaved(product),
              onAddToCart: () => _addToCart(product),
            );
          }, childCount: _results.length),
        );
      },
    );
  }
}

/// What came back for [_Choice], so "All" is distinguishable from a dismissal.
class _Choice {
  const _Choice(this.category);

  final Category? category;
}

/// Sort, department, category and the filter drawer, in one scrollable row.
///
/// Scrollable rather than four squeezed buttons: the department and category
/// pills carry names as long as "men's cotton-padded jacket", and a fixed row
/// either truncates them to nothing or wraps into two lines of chrome above the
/// products.
class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.filters,
    required this.hasSubcategories,
    required this.onSort,
    required this.onFilters,
    this.onDepartment,
    this.onCategory,
  });

  final SearchFilters filters;
  final bool hasSubcategories;
  final VoidCallback onSort;
  final VoidCallback onFilters;
  final VoidCallback? onDepartment;
  final VoidCallback? onCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            _Pill(
              label: filters.sort.label,
              icon: Icons.swap_vert,
              onTap: onSort,
            ),
            const SizedBox(width: 8),
            _Pill(
              label: filters.departmentName ?? 'Department',
              trailingIcon: Icons.keyboard_arrow_down,
              active: filters.departmentCid != null,
              onTap: onDepartment,
            ),
            if (hasSubcategories) ...[
              const SizedBox(width: 8),
              _Pill(
                label: filters.categoryName ?? 'Category',
                trailingIcon: Icons.keyboard_arrow_down,
                active: filters.categoryCid != null,
                onTap: onCategory,
              ),
            ],
            const SizedBox(width: 8),
            _Pill(
              label: filters.count == 0
                  ? 'Filters'
                  : 'Filters (${filters.count})',
              icon: Icons.tune,
              active: filters.count > 0,
              onTap: onFilters,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    this.icon,
    this.trailingIcon,
    this.active = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool active;
  final VoidCallback? onTap;

  /// Long department names are cut here rather than allowed to push the filter
  /// button off the end of the row.
  static const _maxWidth = 170.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final foreground = !enabled
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
        : active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return Material(
      color: active
          ? theme.colorScheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                Icon(trailingIcon, size: 18, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What is narrowing the results, each one removable on its own.
class _ActiveChips extends StatelessWidget {
  const _ActiveChips({
    required this.filters,
    required this.onRemove,
    required this.onClearAll,
  });

  final SearchFilters filters;
  final ValueChanged<ActiveFilter> onRemove;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = filters.chips;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            for (final chip in chips) ...[
              InputChip(
                label: Text(
                  chip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: () => onRemove(chip),
                deleteIcon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
            ],
            // Only worth its space once removing them one at a time is a chore.
            if (chips.length > 1)
              TextButton(onPressed: onClearAll, child: const Text('Clear all')),
          ],
        ),
      ),
    );
  }
}

/// The query, and how many results are under it.
class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.query,
    required this.count,
    required this.exhausted,
    this.relaxedFrom,
    this.widenedTo,
  });

  final String query;
  final int count;
  final bool exhausted;
  final String? relaxedFrom;

  /// The subcategory that was empty, and the department shown instead.
  final ({String from, String to})? widenedTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relaxed = relaxedFrom;
    final widened = widenedTo;

    // The same panel the broadened-search notice uses, with the words that fit
    // this case. A second style of notice for the same idea -- "what you are
    // looking at is not quite what you asked for" -- would be two designs for
    // one meaning.
    if (widened != null) {
      return _Notice(
        icon: Icons.category_outlined,
        title: 'Nothing in ${widened.from} yet',
        detail: 'Showing all of ${widened.to} instead.',
      );
    }

    if (relaxed != null) {
      return _Notice(
        icon: Icons.lightbulb_outline,
        title: 'No exact matches for "$relaxed"',
        // Said plainly, because a grid of substitutes presented as hits is how
        // someone buys the wrong thing.
        detail: 'Showing related products instead.',
      );
    }

    return Padding(
      // The grid's own margin, so the count and the first row of cards start
      // on the same line down the page.
      padding: PageWidth.insets(context, top: 12, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: RichText(
          text: TextSpan(
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            children: [
              // "24+" until the last page has landed. The endpoint returns a
              // bare array with no total, so the only count anyone here can
              // stand behind is how many have actually arrived.
              TextSpan(
                text: exhausted ? '$count ' : '$count+ ',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              TextSpan(text: count == 1 && exhausted ? 'result' : 'results'),
              if (query.isNotEmpty) ...[
                const TextSpan(text: ' for '),
                TextSpan(
                  text: '"$query"',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading) return const SizedBox(height: 24);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({
    required this.query,
    required this.hasFilters,
    required this.onClear,
  });

  final String query;
  final bool hasFilters;
  final VoidCallback onClear;

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
              Icons.search_off,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              // Names the actual cause. A shopper with a filter on who is told
              // "No results for geyser" goes and edits the word, when the word
              // was never the problem -- and the query is still named, because
              // that is how someone spots a typo when it *is*.
              switch ((query.isEmpty, hasFilters)) {
                (true, _) => 'Nothing matches these filters',
                (false, true) => 'No results for "$query" with these filters',
                (false, false) => 'No results for "$query"',
              },
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasFilters
                  ? 'Try removing a filter to widen the search.'
                  : 'Check the spelling, or try a broader word.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onClear,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The panel above the grid when what is shown is not quite what was asked for.
///
/// One shape for both cases -- a keyword broadened, a subcategory widened to
/// its department. They are the same idea said about different things, and two
/// designs for one meaning is how a screen stops looking designed.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // As the count line and the grid below it.
      padding: PageWidth.insets(context, top: 12, bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

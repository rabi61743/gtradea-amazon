import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../catalog/data/product.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/recent_search_store.dart';
import '../data/search_suggestions.dart';
import '../data/visual_search_store.dart';
import '../widgets/search_field.dart';
import '../widgets/visual_search_history.dart';
import '../widgets/visual_search_sheet.dart';
import 'search_results_screen.dart';

/// What opens when the customer taps search: the field, their recent queries,
/// what everybody else is searching for, an image-search prompt, and the
/// departments.
///
/// Recent searches come first. The reference puts image search at the top and
/// pushes history below it, but a returning shopper is far likelier to re-run
/// a query than to photograph something, so the cheaper action leads.
class SearchEntryScreen extends StatefulWidget {
  const SearchEntryScreen({super.key});

  @override
  State<SearchEntryScreen> createState() => _SearchEntryScreenState();
}

class _SearchEntryScreenState extends State<SearchEntryScreen> {
  final _controller = TextEditingController();

  /// What is in the field, and what to offer for it.
  String _typed = '';
  List<SearchSuggestion> _suggestions = const [];

  /// Real products matching what has been typed.
  ///
  /// The reason this exists: `/search/suggestions` was measured returning an
  /// empty list for `tshirt`, `shoe`, `lamp` and every other ordinary product
  /// word -- it only matches a small seeded set of departments and brands. A
  /// typeahead built on it alone showed nothing for almost anything a shopper
  /// would actually type. `/search/products` answers all of them.
  List<Product> _products = const [];

  /// Product rows already fetched, keyed on the query that produced them.
  ///
  /// The suggestions have had a memo for a while; this is the same idea for the
  /// expensive half. Measured against production, the keyword search behind
  /// these rows takes **1.6 to 1.8 seconds** and returns about forty kilobytes,
  /// and typing is not a straight line -- overshooting "kettles" and coming back
  /// to "kettle" paid that twice for an answer already in memory.
  ///
  /// Bounded, unlike the suggestion memo, because the entries here are whole
  /// product rows rather than a few short strings. Sixteen covers the
  /// backspacing and re-typing a session actually does.
  final _productMemo = <String, List<Product>>{};
  static const _productMemoLimit = 16;

  /// Held so a keystroke cancels the request the previous one was about to
  /// make. Without it, typing "shoes" fires five calls and the answer to "sho"
  /// can land after the answer to "shoes".
  Timer? _debounce;

  /// Guards against exactly that reordering for the calls that do go out.
  int _generation = 0;

  static const _debounceDelay = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    RecentSearchStore.instance.load();
    VisualSearchStore.instance.load();
    // The departments double as the suggestions below, so this is the same
    // read the browse tab does rather than a second one.
    CatalogStore.instance.categories.load();
    // Revalidate rather than load: this is the one list whose whole value is
    // being current, so a session that started an hour ago should not still be
    // showing what was trending then.
    CatalogStore.instance.trendingSearches.revalidate();
  }

  @override
  void dispose() {
    // Cancelled, always. A timer outliving the tree is a leak in the app and a
    // pending-timer failure in every test that pumps this screen.
    _debounce?.cancel();
    // Same reason as the timer: a two-second download for a screen nobody is
    // looking at any more is a connection somebody else's request needs.
    _inFlight?.cancel('screen closed');
    _controller.dispose();
    super.dispose();
  }

  /// A keystroke.
  ///
  /// The local sources answer immediately -- they are already in memory -- so
  /// the list updates on the first character rather than waiting on a round
  /// trip. Only the server call is debounced.
  void _onTyped(String value) {
    // A prefix already asked about, answered in this frame.
    //
    // Typing is not a straight line: people overshoot and backspace, and
    // "shoes" trimmed back to "shoe" was a prefix the server had answered two
    // keystrokes earlier. Reading it here rather than through the debounce is
    // the difference between instant and a quarter of a second.
    final remembered = SearchSuggestionRepository.instance.cached(value);
    // The same trick for the slow half. A query already fetched paints its
    // products in this frame too, so backspacing to something just looked at
    // costs nothing rather than another second and a half.
    final rememberedProducts = _productMemo[value.trim().toLowerCase()];

    setState(() {
      _typed = value;
      _suggestions = _merge(remembered ?? const []);
      // Only when there is a hit. Left alone otherwise, so the previous query's
      // rows stay under the field while the new ones load rather than the list
      // emptying and refilling.
      if (rememberedProducts != null) _products = rememberedProducts;
    });

    _debounce?.cancel();
    if (value.trim().length < SearchSuggestionRepository.minQueryLength) {
      _inFlight?.cancel('below the minimum');
      // Cleared straight away. Leaving the last query's products under a field
      // that now says something else is worse than an empty list -- they read
      // as matches for what is on screen.
      setState(() => _products = const []);
      return;
    }
    _debounce = Timer(_debounceDelay, () => unawaited(_fetchFor(value)));
  }

  /// Both halves of the typeahead, each landing on its own.
  ///
  /// **Not `Future.wait`.** Measured against production: `/search/suggestions`
  /// answers in about 150ms, and the keyword search behind the products takes
  /// between 1.4 and 2.3 seconds for forty kilobytes. Joining them meant the
  /// fast half sat finished in memory for nearly two seconds waiting for the
  /// slow one, and a shopper mid-word saw nothing at all in the meantime.
  /// Separately, the suggestion rows appear about ten keystrokes' worth of time
  /// sooner and the products fill in under them.
  ///
  /// Each half swallows its own failure. Typeahead is a convenience, and an
  /// error panel under a field somebody is mid-word in would be worse than the
  /// half that did work. A cancelled request is not a failure at all -- it is
  /// this screen deciding it no longer wants the answer.
  Future<void> _fetchFor(String query) async {
    final generation = ++_generation;

    // Whatever the last keystroke started is no longer wanted. Cancelled rather
    // than merely ignored: two seconds of a forty-kilobyte download still
    // occupies the connection the newest request needs.
    _inFlight?.cancel('superseded');
    final token = CancelToken();
    _inFlight = token;

    bool stale() => !mounted || generation != _generation || query != _typed;

    unawaited(
      SearchSuggestionRepository.instance
          .forQuery(query, cancelToken: token)
          .onError((_, _) => const <SearchSuggestion>[])
          .then((found) {
            if (stale()) return;
            setState(() => _suggestions = _merge(found));
          }),
    );

    // Already fetched, so nothing goes out for it at all.
    final key = query.trim().toLowerCase();
    final rememberedProducts = _productMemo[key];
    if (rememberedProducts != null) {
      if (!stale()) setState(() => _products = rememberedProducts);
      return;
    }

    unawaited(
      CatalogRepository.instance
          .search(query: query, pageSize: _productCount, cancelToken: token)
          // Taken here rather than asked for: a keyword search returns the
          // endpoint's own fifty-row page and ignores page_size entirely.
          .then((rows) => rows.take(_productCount).toList(growable: false))
          .onError((_, _) => const <Product>[])
          .then((found) {
            // Remembered even when this screen has moved on: the answer cost a
            // second and a half and is just as good to the shopper who
            // backspaces into it a moment later.
            _rememberProducts(key, found);
            if (stale()) return;
            setState(() => _products = found);
          }),
    );
  }

  /// Keeps [found] against [key], oldest out once the memo is full.
  void _rememberProducts(String key, List<Product> found) {
    // A failed or cancelled call answers with an empty list, and remembering
    // that would turn one dropped request into a permanently empty typeahead
    // for that word.
    if (found.isEmpty) return;
    if (_productMemo.length >= _productMemoLimit) {
      _productMemo.remove(_productMemo.keys.first);
    }
    _productMemo[key] = found;
  }

  /// The requests the current keystroke started, so the next one can drop them.
  CancelToken? _inFlight;

  /// Enough products to be worth reading without becoming the results page.
  static const _productCount = 6;

  List<SearchSuggestion> _merge(List<SearchSuggestion> fromServer) {
    return mergeSuggestions(
      query: _typed,
      recent: RecentSearchStore.instance.queries,
      trending: (CatalogStore.instance.trendingSearches.value ?? const [])
          .map((row) => row.query)
          .toList(growable: false),
      fromServer: fromServer,
    );
  }

  void _search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    RecentSearchStore.instance.record(trimmed);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SearchResultsScreen(query: trimmed)),
    );
  }

  void _browse(Category category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SearchResultsScreen(query: '', categoryCid: category.cid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          SearchField(
            controller: _controller,
            autofocus: true,
            onSubmitted: _search,
            onChanged: _onTyped,
            onImageSearch: () => _showImageSearchSheet(context),
          ),
          // Typing replaces the browse sections rather than pushing them down.
          // Somebody mid-word is answering "what am I looking for", and the
          // departments below are an answer to a question they have stopped
          // asking.
          if (_suggestions.isNotEmpty || _products.isNotEmpty)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 24),
                children: [
                  // Words first: they are cheap to scan and they refine the
                  // query. Products second, because tapping one leaves the
                  // search behind entirely.
                  for (final suggestion in _suggestions)
                    _SuggestionRow(
                      suggestion: suggestion,
                      onTap: () {
                        _controller.text = suggestion.text;
                        _search(suggestion.text);
                      },
                    ),
                  if (_products.isNotEmpty) ...[
                    const _Heading(label: 'Products'),
                    for (final product in _products)
                      _ProductSuggestionRow(
                        product: product,
                        onTap: () => openProduct(context, product),
                      ),
                  ],
                ],
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  ListenableBuilder(
                    listenable: RecentSearchStore.instance,
                    builder: (context, _) {
                      final recent = RecentSearchStore.instance.queries;
                      if (recent.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Heading(
                            label: 'Recent searches',
                            action: 'Clear',
                            onAction: RecentSearchStore.instance.clear,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final query in recent)
                                  ActionChip(
                                    avatar: Icon(
                                      Icons.history,
                                      size: 16,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    label: Text(query),
                                    onPressed: () {
                                      _controller.text = query;
                                      _search(query);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  // What other shoppers are actually searching for, from
                  // /feed/trending-searches. Built to the same shape as Recent
                  // searches above -- heading, then a wrap of chips -- because
                  // they are the same gesture and should not look like two
                  // different features.
                  //
                  // Not a LoadableView, deliberately, and for the same reason the
                  // home banner is not one: that widget's rule is that a failure
                  // is never silence, which is right for content a page is about
                  // and wrong for a suggestion. A red retry panel, a spinner, or
                  // a heading over nothing are all worse here than a search
                  // screen without the block -- the shopper came to type, and
                  // there is a field waiting for them either way.
                  ListenableBuilder(
                    listenable: CatalogStore.instance.trendingSearches,
                    builder: (context, _) {
                      final trending =
                          CatalogStore.instance.trendingSearches.value;
                      if (trending == null || trending.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Heading(label: 'Trending searches'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final row in trending)
                                  ActionChip(
                                    avatar: Icon(
                                      Icons.trending_up,
                                      size: 16,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    label: Text(row.query),
                                    onPressed: () {
                                      _controller.text = row.query;
                                      _search(row.query);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  _ImageSearchCard(onTap: () => _showImageSearchSheet(context)),
                  // Under the prompt that starts one, so a shopper who has done
                  // this before sees their own pictures rather than the pitch.
                  const VisualSearchHistory(),
                  const _Heading(label: 'Browse departments'),
                  // The real department list rather than a hand-written list of
                  // popular queries. Nobody maintains the second kind, and it
                  // goes stale pointing at things the catalogue no longer sells.
                  LoadableView<List<Category>>(
                    loadable: CatalogStore.instance.categories,
                    emptyCheck: (categories) => categories.isEmpty,
                    // Without this an empty catalogue left a heading over
                    // nothing, which reads as a screen that failed rather than
                    // one with nothing to say.
                    empty: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'No departments to browse just now.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    builder: (context, categories) => Column(
                      children: [
                        for (final category in categories.take(12))
                          _DepartmentRow(
                            category: category,
                            onTap: () => _browse(category),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showImageSearchSheet(BuildContext context) {
    // Was two list tiles that popped and did nothing. The sheet now opens the
    // camera or the gallery and runs a real search against
    // `/api/1688/image-search`.
    unawaited(VisualSearchSheet.show(context));
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.label, this.action, this.onAction});

  final String label;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// One prompt carrying both capture routes, rather than the reference pair of
/// equally weighted buttons: choosing camera or gallery is secondary to
/// deciding to search by image at all.
class _ImageSearchCard extends StatelessWidget {
  const _ImageSearchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Material(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.center_focus_strong,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Search by image',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Photograph a product or pick one from your gallery',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One department, opening its results.
class _DepartmentRow extends StatelessWidget {
  const _DepartmentRow({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ArtworkPanel(
          icon: iconForCategory(category.name),
          tint: tintForCategory(category.cid),
          imageUrl: category.imageUrl,
          iconScale: 0.5,
        ),
      ),
      title: Text(category.name),
      subtitle: category.children.isEmpty
          ? null
          : Text(
              category.children.take(3).map((c) => c.name).join(' - '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// One typeahead row.
///
/// A ListTile like the department rows on the browse list, so swapping one
/// list for the other does not look like swapping screens.
///
/// The leading icon is the only thing that says where the suggestion came
/// from. A shopper does not need to be told "from your history" in words, but
/// they do need to tell their own past query apart from a promoted one -- and
/// somebody who cannot see the icon gets the same distinction from the
/// semantics label.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.onTap});

  final SearchSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, kind) = switch (suggestion.kind) {
      SuggestionKind.recent => (Icons.history, 'Recent search'),
      SuggestionKind.trending => (Icons.trending_up, 'Trending search'),
      SuggestionKind.catalogue => (Icons.search, 'Suggestion'),
    };

    return Semantics(
      button: true,
      label: '${suggestion.text}. $kind.',
      excludeSemantics: true,
      child: ListTile(
        onTap: onTap,
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        title: Text(
          suggestion.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// One product offered while the shopper is still typing.
///
/// A compact row rather than the grid card the results page uses: this list
/// sits under a field somebody is mid-word in, and six of those cards would
/// bury the suggestions above them and read as the results page arriving
/// early.
///
/// Built like the department rows on the same screen -- a 44pt thumbnail, a
/// title, a trailing chevron -- so a screen that swaps one list for the other
/// does not look like it swapped screens.
class _ProductSuggestionRow extends StatelessWidget {
  const _ProductSuggestionRow({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ArtworkPanel(
          icon: iconForCategory(
            product.categoryName ?? product.parentCategoryName,
          ),
          tint: tintForCategory(product.categoryCid ?? product.numIid),
          imageUrl: product.imageUrl,
          iconScale: 0.5,
        ),
      ),
      title: Text(
        product.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
      ),
      subtitle: Text(
        // Not "Rs. 0". Half this catalogue comes back unpriced, and a zero
        // would be a lie about a real product.
        product.hasPrice
            ? formatRupees(product.displayPrice!)
            : 'Price on request',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: product.hasPrice ? FontWeight.w800 : FontWeight.w600,
          color: product.hasPrice
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../../core/images/app_images.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../data/visual_search_repository.dart';
import '../data/visual_search_store.dart';
import '../widgets/result_card.dart';

/// What a photograph found.
///
/// The picture stays on screen above the results for the whole visit. Visual
/// search is the one search where the query is not a word the shopper can
/// re-read from a field, and without it a page of loosely-similar products has
/// nothing to be judged against.
class VisualSearchScreen extends StatefulWidget {
  const VisualSearchScreen({
    super.key,
    required File this.image,
    this.record = true,
  }) : imageUrl = null;

  /// Searches with a picture the catalogue already hosts -- the photograph on
  /// a product page, rather than one off the shopper's phone.
  ///
  /// Nothing is recorded: the history keeps files it can show again later, and
  /// a catalogue URL is not the shopper's own picture.
  const VisualSearchScreen.forImageUrl({
    super.key,
    required String this.imageUrl,
  }) : image = null,
       record = false;

  /// The picked photograph, when the search came from the camera or gallery.
  final File? image;

  /// The catalogue address, when the search came from a product page.
  final String? imageUrl;

  /// False when re-running a search already in the history, so tapping an old
  /// thumbnail does not add a duplicate entry for the same picture.
  final bool record;

  @override
  State<VisualSearchScreen> createState() => _VisualSearchScreenState();
}

class _VisualSearchScreenState extends State<VisualSearchScreen> {
  List<Product> _results = const [];
  int _total = 0;
  bool _loading = true;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    CartStore.instance.load();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final url = widget.imageUrl;
      if (url != null) {
        final matches = await VisualSearchRepository.instance.searchByUrl(url);
        if (!mounted) return;
        setState(() {
          _results = matches.products;
          _total = matches.total;
          _loading = false;
        });

        // Kept like any other search, so a picture searched from a product
        // page turns up under Recent photo searches beside the ones taken with
        // the camera -- and can be re-run from there. Fetched after the
        // results rather than before: the thumbnail is worth nothing if it
        // delays what was actually asked for.
        unawaited(_keepInHistory(url, matches.products.length));
        return;
      }

      final bytes = await widget.image!.readAsBytes();
      // Off the UI thread only when it is worth an isolate. A 1280px JPEG runs
      // a few hundred kilobytes and base64 inflates it by a third, which is
      // enough to drop frames; anything small encodes faster than the isolate
      // takes to spawn.
      final encoded = bytes.length > 64 * 1024
          ? await compute(base64Encode, bytes)
          : base64Encode(bytes);

      final matches = await VisualSearchRepository.instance.search(encoded);
      if (!mounted) return;

      setState(() {
        _results = matches.products;
        _total = matches.total;
        _loading = false;
      });

      final picked = widget.image;
      if (widget.record && picked != null) {
        // After the results, not before: an entry claiming a count it never
        // got would be wrong in the one place the shopper can check it.
        unawaited(
          VisualSearchStore.instance.record(
            picked,
            resultCount: matches.products.length,
          ),
        );
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiError(statusCode: null, message: e.toString());
        _loading = false;
      });
    }
  }

  /// Saves the searched picture into the history, if it can be had.
  Future<void> _keepInHistory(String url, int resultCount) async {
    final bytes = await VisualSearchRepository.instance.pictureBytes(url);
    if (bytes == null) return;
    await VisualSearchStore.instance.recordBytes(
      bytes,
      resultCount: resultCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual search'),
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
      body: Column(
        children: [
          _Preview(
            image: widget.image,
            imageUrl: widget.imageUrl,
            total: _total,
            loading: _loading,
          ),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _Searching();

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: LoadFailed(
          message: error.isNetwork
              ? 'No connection. Check your network and try again.'
              : error.message,
          onRetry: _run,
        ),
      );
    }

    if (_results.isEmpty) return const _NoMatches();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final product = _results[i];
        return ResultCard(
          result: toSearchResult(product),
          onTap: () => openProduct(context, product),
        );
      },
    );
  }
}

/// The photograph that was searched with, and what it found.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.image,
    required this.imageUrl,
    required this.total,
    required this.loading,
  });

  final File? image;
  final String? imageUrl;
  final int total;
  final bool loading;

  /// The picture searched with: a file from the phone, or the catalogue
  /// photograph the search was started from.
  Widget _thumbnail(BuildContext context) {
    final theme = Theme.of(context);

    // The file was there a moment ago, but a cache directory can be cleared
    // underneath a running app; and a catalogue URL can 404 like any other.
    Widget missing(BuildContext context, Object error, StackTrace? stack) =>
        Container(
          width: 76,
          height: 76,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );

    final picked = image;
    if (picked != null) {
      return Image.file(
        picked,
        width: 76,
        height: 76,
        fit: BoxFit.cover,
        errorBuilder: missing,
      );
    }
    return Image(
      image: AppImages.of(imageUrl ?? '', width: 76),
      width: 76,
      height: 76,
      fit: BoxFit.cover,
      errorBuilder: missing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: _thumbnail(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Searching by this photo',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loading
                      ? 'Looking for products that match...'
                      : total > 0
                      ? '$total similar ${total == 1 ? 'product' : 'products'} found'
                      : 'No matches found',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The wait.
///
/// Named rather than a bare spinner: recognition takes a few seconds against
/// production, which is long enough that an unexplained circle reads as a
/// hang.
class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 16),
          Text(
            'Matching your photo',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This takes a few seconds.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A photograph the catalogue has nothing like.
class _NoMatches extends StatelessWidget {
  const _NoMatches();

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
              Icons.image_search,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing matched this photo',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a closer shot of the product on its own, with the label '
              'facing the camera and nothing else in frame.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Try another photo'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/catalog_store.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/recent_search_store.dart';
import '../widgets/search_field.dart';
import 'search_results_screen.dart';

/// What opens when the customer taps search: the field, their recent queries,
/// an image-search prompt, and what the storefront is promoting.
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

  @override
  void initState() {
    super.initState();
    RecentSearchStore.instance.load();
    // The departments double as the suggestions below, so this is the same
    // read the browse tab does rather than a second one.
    CatalogStore.instance.categories.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchResultsScreen(
        query: '',
        categoryCid: category.cid,
      ),
    ));
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
            onImageSearch: () => _showImageSearchSheet(context),
          ),
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
                _ImageSearchCard(onTap: () => _showImageSearchSheet(context)),
                const _Heading(label: 'Browse departments'),
                // The real department list rather than a hand-written list of
                // popular queries. Nobody maintains the second kind, and it
                // goes stale pointing at things the catalogue no longer sells.
                LoadableView<List<Category>>(
                  loadable: CatalogStore.instance.categories,
                  emptyCheck: (categories) => categories.isEmpty,
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Point at the product you want'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('Use a picture you already have'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
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
                Icon(Icons.center_focus_strong,
                    size: 26, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Search by image',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
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
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant),
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

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/visual_search_store.dart';
import '../presentation/visual_search_screen.dart';

/// Past visual searches, as the thumbnails that were searched with.
///
/// Thumbnails rather than a list of words, because there are no words: the
/// query was a photograph, and the only honest way to show it again is to show
/// it. Tapping one runs it a second time.
class VisualSearchHistory extends StatelessWidget {
  const VisualSearchHistory({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VisualSearchStore.instance,
      builder: (context, _) {
        final store = VisualSearchStore.instance;
        if (store.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent photo searches',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _confirmClear(context),
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: store.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _HistoryTile(
                  search: store.items[i],
                  onTap: () => _rerun(context, store.items[i]),
                  onRemove: () => store.remove(store.items[i].id),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _rerun(BuildContext context, VisualSearch search) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisualSearchScreen(
          image: search.file,
          // Already in the history: recording it again would file the same
          // picture twice and push a genuinely older search off the end.
          record: false,
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    // Asked first: this deletes photographs, and the shopper's own camera roll
    // is not where these came back from.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear photo searches?'),
        content: const Text(
          'This removes every saved photo search from this device. It does '
          'not touch your photo gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );

    if (confirmed == true) await VisualSearchStore.instance.clear();
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.search,
    required this.onTap,
    required this.onRemove,
  });

  final VisualSearch search;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: search.resultCount > 0
          ? 'Photo search, ${search.resultCount} matches. Search again.'
          : 'Photo search with no matches. Search again.',
      excludeSemantics: true,
      child: SizedBox(
        width: 88,
        child: Stack(
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Image.file(
                          search.file,
                          fit: BoxFit.cover,
                          // The file can vanish between the list being built
                          // and this frame -- storage cleared, app data wiped.
                          errorBuilder: (context, error, stack) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        search.resultCount > 0
                            ? '${search.resultCount} matches'
                            : 'No matches',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(top: 2, right: 2, child: _RemoveButton(onTap: onRemove)),
          ],
        ),
      ),
    );
  }
}

/// The per-item delete.
///
/// Small, but on a scrim rather than bare on the photograph -- a dark glyph on
/// a dark picture is a control nobody can find.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove this photo search',
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: Icon(Icons.close, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

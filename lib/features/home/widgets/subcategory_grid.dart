import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../../shared/widgets/section_header.dart';
import '../../catalog/data/catalog_repository.dart' show Category;
import '../../catalog/data/category_thumbnails.dart';
import '../../catalog/presentation/catalog_visuals.dart';

/// A department's own subcategories: four pictures, two by two, each captioned
/// inside its own frame.
///
/// The caption sits *on* the picture rather than under it. Under it, the label
/// belonged to the grid rather than to the tile, and a long category name --
/// "Children's Knitted Sweaters", which is what this catalogue is full of --
/// ran past the bottom of its cell and was cut off mid-word. Inside the frame
/// there is nothing for it to overflow: the tile is a square, the text is laid
/// over the lower part of it, and a name too long for two lines ellipsises
/// where it can be seen to.
///
/// A scrim under the text, not a solid bar. These are photographs nobody
/// controls -- a white studio shot and a dark one both turn up in the same row
/// -- so white text needs something behind it, and a gradient does that
/// without hiding the part of the picture that says what the thing is.
///
/// The names and the pictures are the real ones from `/alibaba-categories`,
/// fetched with the department tree and cached. Nothing here invents a
/// shortcut.
class SubcategoryGrid extends StatelessWidget {
  const SubcategoryGrid({
    super.key,
    required this.children,
    required this.onSelected,
    this.onSeeAll,
    this.title,
    this.subtitle,
    this.leadingIcon = Icons.subdirectory_arrow_right,
    this.actionLabel = 'See All',
    this.shown = defaultShown,
    this.fillMissingImages = false,
  });

  /// Whether a category with no artwork should go and find a picture.
  ///
  /// Off by default, and deliberately: on the home page every tile comes from
  /// the department tree, where artwork is complete, so turning this on there
  /// would risk a request per tile for nothing. The category screen turns it
  /// on, because that is the level where the catalogue's pictures run out --
  /// see [CategoryThumbnails] for what the substitute is and what it is not.
  final bool fillMissingImages;

  /// The department's children, straight off [Category.children].
  final List<Category> children;
  final ValueChanged<Category> onSelected;
  final VoidCallback? onSeeAll;

  /// The section's heading -- "Browse Kidswear". The whole department is one
  /// tap past it, on [onSeeAll].
  final String? title;

  /// A line under the heading, for a block that is a chosen set rather than a
  /// department's own children and has something to say about what is in it.
  final String? subtitle;

  /// The glyph beside the heading. The arrow says "into this department";
  /// a curated block is not that, so it passes its own.
  final IconData leadingIcon;

  /// What the action says. "See All" for a department's children, since there
  /// are about forty and four are shown.
  final String actionLabel;

  /// How many tiles to draw.
  ///
  /// Four on the home page -- two rows of two. A department has about forty
  /// children, so four is a look at what is in there and "See All" is how
  /// somebody who wants the other thirty-six gets to them.
  ///
  /// The category screen passes the full count, because being the whole list
  /// of the level below is the entire reason that screen exists.
  final int shown;

  static const defaultShown = 4;

  static const columns = 2;
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final entries = children.take(shown).toList(growable: false);
    if (entries.isEmpty) return const SizedBox.shrink();

    final title = this.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          SectionHeader(
            title: title,
            subtitle: subtitle,
            leadingIcon: leadingIcon,
            onSeeAll: onSeeAll,
            actionLabel: actionLabel,
          )
        else
          const SizedBox(height: SectionHeader.gapBelow),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SectionHeader.edge),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  // Square, and stated rather than expressed as a ratio: with
                  // the caption inside the frame there is nothing below the
                  // picture for a text scale to grow, so the tile's height is
                  // its width and cannot drift from it.
                  mainAxisExtent: width,
                ),
                itemCount: entries.length,
                itemBuilder: (context, i) => _Tile(
                  // Keyed on the category, so a rebuilt grid does not hand one
                  // tile's resolved picture to a different category.
                  key: ValueKey(entries[i].cid),
                  category: entries[i],
                  width: width,
                  fillMissingImage: fillMissingImages,
                  onTap: () => onSelected(entries[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One subcategory: its picture, with its name written across the foot of it.
class _Tile extends StatefulWidget {
  const _Tile({
    super.key,
    required this.category,
    required this.width,
    required this.fillMissingImage,
    required this.onTap,
  });

  final Category category;
  final double width;
  final bool fillMissingImage;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  /// The category's own artwork, or the one found for it. Null until either is
  /// known, and null for good when there is neither.
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_Tile old) {
    super.didUpdateWidget(old);
    if (old.category.cid != widget.category.cid) _resolve();
  }

  void _resolve() {
    final own = widget.category.imageUrl;
    _url = own != null && own.isNotEmpty ? own : null;
    if (_url != null || !widget.fillMissingImage) return;

    // Memoised and de-duplicated by the service, so a grid of twelve tiles
    // makes at most twelve requests once, and a rebuild makes none.
    CategoryThumbnails.instance.forCategory(widget.category).then((found) {
      if (!mounted || found == null) return;
      setState(() => _url = found);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = _url;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard + 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        // Crossed rather than swapped: a picture that arrives after the tile is
        // already on screen should settle into it, not blink.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: url == null
              ? _plain(theme)
              : KeyedSubtree(key: ValueKey(url), child: _photo(theme, url)),
        ),
      ),
    );
  }

  Category get category => widget.category;
  double get width => widget.width;

  /// The tile as designed: the picture, with the name across the foot of it.
  Widget _photo(ThemeData theme, String url) => Stack(
    fit: StackFit.expand,
    children: [
      ArtworkPanel(
        icon: iconForCategory(category.name),
        tint: tintForCategory(category.cid),
        imageUrl: url,
        // Already known, so the panel skips the LayoutBuilder it would
        // otherwise need to size its decode -- and there are four of these per
        // department, five departments deep.
        knownWidth: width,
        iconScale: 0.34,
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Transparent to nearly black. Starting from transparent is what
              // keeps this from reading as a bar stuck on the bottom of the
              // photograph.
              colors: [Color(0x00000000), Color(0xCC000000)],
            ),
          ),
          child: Text(
            category.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.2,
              // These sit over photographs of every brightness. The shadow is
              // what carries the text across a white studio shot, where the
              // scrim alone is not quite enough.
              shadows: const [Shadow(color: Color(0x99000000), blurRadius: 4)],
            ),
          ),
        ),
      ),
    ],
  );

  /// The tile for a category the catalogue has no picture for.
  ///
  /// A designed card rather than the photo treatment with nothing under it.
  /// The scrim and the white text exist to carry a caption across a
  /// photograph; laid over a plain tint with no picture behind it they read as
  /// an image that failed to load, which is what this looked like.
  ///
  /// Not a rare case, and not a bug to be fixed in the app: artwork at the
  /// third level of this catalogue is patchy. Hanfu has it on four of five
  /// children and Women's Down Jackets on both of hers, while every one of
  /// Antenna's six, Audio Devices' five, Capacitor's twelve and Diode's eleven
  /// comes back with a null `image_url`. Populating those is a backoffice job;
  /// drawing them honestly is this one.
  Widget _plain(ThemeData theme) {
    final tint = tintForCategory(category.cid);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: 0.20), tint.withValues(alpha: 0.07)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              iconForCategory(category.name),
              size: width * 0.26,
              color: tint,
            ),
            const Spacer(),
            Text(
              category.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              // Dark on a light tint. White here -- the photo tile's colour --
              // is what made these unreadable as well as looking broken.
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

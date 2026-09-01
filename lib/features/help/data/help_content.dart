import '../../../core/network/json.dart';

/// A shelf of the knowledge base, as the gateway has it.
///
/// Read from `/help/categories` rather than compiled in: which topics a shop
/// publishes is editorial, changes without an app release, and is already
/// managed in the admin panel the website uses.
class HelpCategory {
  const HelpCategory({
    required this.id,
    required this.slug,
    required this.name,
    this.description = '',
    this.icon,
  });

  final String id;

  /// The key the article list filters on, and what tells the developer shelf
  /// apart from the shopper ones.
  final String slug;

  final String name;
  final String description;

  /// The server's own icon name. Mapped to a Material glyph where one fits and
  /// otherwise left null -- an unknown name draws the generic help icon rather
  /// than nothing.
  final String? icon;

  factory HelpCategory.fromJson(Map<String, dynamic> json) => HelpCategory(
    id: asString(json['id']) ?? '',
    slug: asString(json['slug']) ?? '',
    name: asString(json['name']) ?? asString(json['title']) ?? '',
    description: stripHtml(asString(json['description']) ?? ''),
    icon: asString(json['icon']),
  );
}

/// One article. The list carries enough to render a row; the body is fetched
/// only when one is opened.
class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.slug,
    required this.title,
    this.summary = '',
    this.categoryName = '',
    this.featured = false,
    this.views = 0,
  });

  final String id;
  final String slug;
  final String title;
  final String summary;

  /// Flattened from the nested category the server sends beside the article.
  final String categoryName;

  final bool featured;
  final int views;

  factory HelpArticle.fromJson(Map<String, dynamic> json) => HelpArticle(
    id: asString(json['id']) ?? '',
    slug: asString(json['slug']) ?? '',
    title: asString(json['title']) ?? '',
    summary: stripHtml(
      asString(json['summary']) ?? asString(json['excerpt']) ?? '',
    ),
    categoryName: asString(asMap(json['category'])['name']) ?? '',
    featured: asBool(json['is_featured']),
    views: asInt(json['views_count']) ?? 0,
  );
}

/// Who the shelf is written for.
///
/// The server's own two values, sent as the `audience` filter. The names are
/// its names -- 'user' rather than 'customer' -- because the query is not ours
/// to rename.
enum HelpAudience {
  user('user'),
  developer('developer');

  const HelpAudience(this.query);

  /// What goes on the wire.
  final String query;
}

/// The slug the gateway reserves for developer material.
///
/// Categories are not tagged with an audience, so this is how the two shelves
/// are told apart -- the same rule the website applies.
const String kDeveloperSlug = 'developers';

/// The categories to show for [audience].
List<HelpCategory> categoriesFor(
  List<HelpCategory> all,
  HelpAudience audience,
) => [
  for (final category in all)
    if ((category.slug == kDeveloperSlug) ==
        (audience == HelpAudience.developer))
      category,
];

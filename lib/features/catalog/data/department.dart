import 'package:flutter/material.dart';

import '../presentation/catalog_visuals.dart';
import 'catalog_repository.dart';
import '../../home/widgets/category_section.dart' show CategoryEntry;

/// A named block of subcategories inside a department.
class CatalogGroup {
  const CatalogGroup({required this.title, required this.entries});

  final String title;
  final List<CategoryEntry> entries;
}

/// A top-level department, as the browse rail lists it.
class Department {
  const Department({
    required this.label,
    required this.icon,
    required this.tint,
    required this.tagline,
    required this.groups,
    this.imageUrl,
  });

  final String label;
  final IconData icon;
  final Color tint;

  /// One line under the department name. Says what is actually in here, so the
  /// header is worth its height rather than repeating the name in a bigger font.
  final String tagline;

  final List<CatalogGroup> groups;

  /// The one photograph in a department's block. Null falls back to the
  /// tinted glyph, which is what the tiles below use anyway.
  final String? imageUrl;

  int get entryCount =>
      groups.fold(0, (sum, group) => sum + group.entries.length);

  /// The handful surfaced above the groups. Taken from the front of each group
  /// in turn rather than the first group only, so the strip is a sample of the
  /// whole department instead of a duplicate of the first section.
  List<CategoryEntry> get popular {
    final picks = <CategoryEntry>[];
    for (var depth = 0; depth < 2; depth++) {
      for (final group in groups) {
        if (group.entries.length > depth) picks.add(group.entries[depth]);
        if (picks.length == 6) return picks;
      }
    }
    return picks;
  }
}

/// The browse tree, built from the departments the server returns.
///
/// The catalogue is two levels deep -- a department and its subcategories --
/// so each department becomes one group. Names, photographs and ordering all
/// come from the server; only the icon and the accent colour are chosen here,
/// because the API has no artwork to send.
List<Department> departmentsFrom(
  List<Category> categories, {
  required void Function(Category category) onOpen,
}) {
  return categories
      .map((department) => Department(
            label: department.name,
            icon: iconForCategory(department.name),
            tint: tintForCategory(department.cid),
            imageUrl: department.imageUrl,
            tagline: _tagline(department),
            groups: department.children.isEmpty
                ? const []
                : [
                    CatalogGroup(
                      title: 'Browse ${department.name}',
                      entries: [
                        for (final child in department.children)
                          CategoryEntry(
                            label: child.name,
                            icon: iconForCategory(child.name),
                            tint: tintForCategory(child.cid),
                            imageUrl: child.imageUrl,
                            onTap: () => onOpen(child),
                          ),
                      ],
                    ),
                  ],
          ))
      .toList(growable: false);
}

/// One line under a department name.
///
/// Its own subcategories, which is both accurate and more useful than a
/// written-out description that would have to be maintained by hand for a tree
/// the server owns.
String _tagline(Category department) {
  final children = department.children;
  if (children.isEmpty) return 'Everything in ${department.name}';
  final names = children.take(3).map((c) => c.name).join(', ');
  final rest = children.length - 3;
  return rest > 0 ? '$names and $rest more' : names;
}

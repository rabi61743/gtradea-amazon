import 'package:flutter/material.dart';

/// A query the storefront is promoting, with a thumbnail.
class TrendingSearch {
  const TrendingSearch({
    required this.query,
    required this.icon,
    required this.tint,
    this.imageUrl,
  });

  final String query;
  final IconData icon;
  final Color tint;
  final String? imageUrl;
}

/// One result row.
///
/// Richer than the home rail's ProductItem: results carry the facts a shopper
/// compares on -- specs, savings, delivery -- which a browse tile does not.
class SearchResult {
  const SearchResult({
    required this.title,
    required this.price,
    required this.rating,
    required this.reviewCount,
    required this.icon,
    required this.tint,
    this.listPrice,
    this.specs = const [],
    this.imageUrl,
    this.freeDelivery = false,
    this.sponsored = false,
  });

  final String title;
  final num price;
  final num? listPrice;
  final double rating;
  final int reviewCount;
  final IconData icon;
  final Color tint;

  /// Short factual chips, e.g. "25 L", "5 star". Not marketing copy.
  final List<String> specs;

  final String? imageUrl;
  final bool freeDelivery;

  /// Paid placement. Labelled in the UI because not labelling it would be
  /// the deceptive choice.
  final bool sponsored;

  /// Whole-percent saving, or null when there is nothing to claim.
  int? get discountPercent {
    final list = listPrice;
    if (list == null || list <= price) return null;
    return (((list - price) / list) * 100).round();
  }
}

/// A filter the results can be narrowed by.
class FilterGroup {
  const FilterGroup({required this.label, required this.options});

  final String label;
  final List<String> options;
}

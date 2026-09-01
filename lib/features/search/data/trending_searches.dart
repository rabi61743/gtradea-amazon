import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// What other shoppers are actually searching for.
///
/// From `/feed/trending-searches`, which returns real queries with their real
/// counts, ranked. Nothing here is written by hand -- which is exactly why the
/// search screen never carried a trending list before: a hand-kept list of
/// "popular searches" goes stale pointing at things the catalogue stopped
/// selling, and nobody notices for months.
class TrendingQuery {
  const TrendingQuery({required this.query, required this.count});

  final String query;

  /// How many times it was searched. Not shown -- a shopper does not need the
  /// number, and printing "33" beside a term invites reading it as a stock
  /// level or a price. It is kept because it is what the ranking means.
  final int count;

  factory TrendingQuery.fromJson(Map<String, dynamic> json) => TrendingQuery(
    query: asString(json['query'])?.trim() ?? '',
    count: asInt(json['search_count']) ?? 0,
  );
}

/// Queries that do not get promoted, however often they are searched.
///
/// This list is a real editorial decision, not a bug fix. The endpoint reports
/// what people search for, and at the time of writing an adult term sat
/// seventh. Reporting it is right; putting it on the storefront's front door as
/// a suggestion is a different act, and one nobody chose.
///
/// Deliberately small and deliberately here in one named place rather than
/// scattered through a widget: it is meant to be read, argued with and edited.
/// It is a blunt instrument -- substring matching, no cleverness -- and it will
/// both miss things and occasionally catch an innocent phrase. The alternative
/// considered was filtering in the Go backend, which would protect the web
/// storefront too; if that lands, this can go.
const kNotPromoted = <String>[
  'penis',
  'vagina',
  'dildo',
  'vibrator',
  'sex',
  'condom',
  'lingerie sexy',
  'adult toy',
  'masturb',
  'anal',
  'nude',
  'porn',
];

/// Whether a query is fit to suggest.
bool isPromotable(String query) {
  final lower = query.toLowerCase();
  if (lower.isEmpty) return false;
  return !kNotPromoted.any(lower.contains);
}

class TrendingSearchRepository {
  TrendingSearchRepository._();

  static final TrendingSearchRepository instance = TrendingSearchRepository._();

  /// The ranked list, filtered and capped.
  ///
  /// Filtering happens before the cap, so dropping one term promotes the next
  /// real one rather than leaving a short list with a gap in it.
  Future<List<TrendingQuery>> list({int limit = 8}) => guarded(() async {
    final res = await ApiClient.http.get(
      '/feed/trending-searches',
      options: guestCall,
    );

    return asRows(res.data, key: 'searches')
        .map(TrendingQuery.fromJson)
        .where((row) => isPromotable(row.query))
        .take(limit)
        .toList(growable: false);
  });
}

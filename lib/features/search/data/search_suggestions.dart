import 'package:dio/dio.dart' show CancelToken;

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// Where a suggestion came from.
///
/// Shown as the row's icon rather than as words. A shopper does not need to be
/// told "this is from your history" -- a clock says it -- but they do need to
/// be able to tell their own past query apart from something the shop is
/// putting in front of them.
enum SuggestionKind {
  /// Something this shopper searched for before.
  recent,

  /// A query other shoppers are running now.
  trending,

  /// A department or brand the server matched on the prefix.
  catalogue,
}

class SearchSuggestion {
  const SearchSuggestion({required this.text, required this.kind});

  final String text;
  final SuggestionKind kind;

  /// Matching is on the text alone, so the same word arriving from two sources
  /// collapses to one row rather than appearing twice with different icons.
  @override
  bool operator ==(Object other) =>
      other is SearchSuggestion &&
      other.text.toLowerCase() == text.toLowerCase();

  @override
  int get hashCode => text.toLowerCase().hashCode;
}

/// Typeahead against `/search/suggestions`.
///
/// The endpoint returns departments and brands with a similarity score, already
/// ranked. It is **sparse**: it matches a seeded set, so most real prefixes
/// come back empty -- "sho", "kid" and "tshirt" all do. That is why the screen
/// blends these with the shopper's own history and the live trending list
/// rather than relying on this alone.
///
/// What it does not return is a category id this app can filter by. The `slug`
/// and `id` belong to a different table from the `category` parameter
/// `/search/products` accepts -- `category=mens-fashion` was measured returning
/// an empty list -- so tapping a suggestion runs a text search for its words,
/// which was measured working for every suggestion the endpoint produces.
class SearchSuggestionRepository {
  SearchSuggestionRepository._();

  static final SearchSuggestionRepository instance =
      SearchSuggestionRepository._();

  /// Below this a prefix matches most of the catalogue and the answer is noise.
  static const minQueryLength = 2;

  /// Answers already given, keyed on the prefix that produced them.
  ///
  /// Typing is not a straight line: people overshoot and backspace, and they
  /// come back to the field having searched the same thing yesterday. Without
  /// this, "shoes" backspaced to "shoe" asked the server again for something it
  /// had answered two keystrokes earlier.
  ///
  /// Unbounded is fine here. An entry is a short prefix and up to six short
  /// strings, and the map lives for one run of the app -- a shopper would have
  /// to type thousands of distinct prefixes in one session to make it worth
  /// evicting anything.
  final _memo = <String, List<SearchSuggestion>>{};

  /// Queries already answered with nothing.
  ///
  /// Kept apart from [_memo] because they support an inference the memo cannot:
  /// see [knownEmpty].
  final _empty = <String>{};

  /// The cached answer for [query], or null if it has not been asked yet.
  ///
  /// Separate from [forQuery] so the screen can paint a known answer in the
  /// same frame as the keystroke rather than a frame later, which is what
  /// makes a cache hit feel like no request at all.
  List<SearchSuggestion>? cached(String query) {
    final key = query.trim().toLowerCase();
    final remembered = _memo[key];
    if (remembered != null) return remembered;
    return knownEmpty(key) ? const <SearchSuggestion>[] : null;
  }

  /// Whether [query] must come back empty, without asking.
  ///
  /// The endpoint matches **substrings, case-insensitively** -- measured, not
  /// assumed: `ashion`, `shi` and `FASHION` all return the Fashion categories,
  /// and `shi` only matches because "fa*shi*on" contains it. Substring matching
  /// is monotone, so if `q` contains a word that matched nothing, `q` matches
  /// nothing either: anything containing `q` contains that word too.
  ///
  /// That inference is worth having because this endpoint is overwhelmingly
  /// empty. Measured on production, typing "kettle" asks five times and gets an
  /// answer once; typing "water" asks four times and never gets one. With this,
  /// the first miss ends the asking -- "kettle" costs two requests and "water"
  /// one, and every keystroke after the miss paints from memory in the same
  /// frame.
  ///
  /// Only substrings already known to be empty count. A query that has never
  /// been asked about proves nothing.
  bool knownEmpty(String query) {
    final key = query.trim().toLowerCase();
    if (key.length < minQueryLength) return false;
    for (final miss in _empty) {
      if (key.contains(miss)) return true;
    }
    return false;
  }

  Future<List<SearchSuggestion>> forQuery(
    String query, {
    int limit = 6,
    CancelToken? cancelToken,
  }) {
    final trimmed = query.trim();
    if (trimmed.length < minQueryLength) {
      return Future.value(const <SearchSuggestion>[]);
    }

    final key = trimmed.toLowerCase();
    final remembered = _memo[key];
    if (remembered != null) return Future.value(remembered);

    // Knowable without asking. See [knownEmpty]: this is where most of the
    // typing in a session stops costing a request at all.
    if (knownEmpty(key)) return Future.value(const <SearchSuggestion>[]);

    return guarded(() async {
      final res = await ApiClient.http.get(
        '/search/suggestions',
        queryParameters: {'q': trimmed},
        options: guestCall,
        cancelToken: cancelToken,
      );

      final found = asRows(res.data, key: 'suggestions')
          .map((row) => asString(row['text'])?.trim() ?? '')
          .where((text) => text.isNotEmpty)
          .map(
            (text) =>
                SearchSuggestion(text: text, kind: SuggestionKind.catalogue),
          )
          .take(limit)
          .toList(growable: false);

      // Remembered including the empty answer. This endpoint is sparse -- most
      // ordinary words come back with nothing -- so "nothing" is the common
      // result and re-asking for it is the common waste.
      _memo[key] = found;
      if (found.isEmpty) {
        // Remembered as a *miss*, which is stronger than remembering the answer:
        // it settles every longer query containing this one as well.
        //
        // Shorter misses subsume longer ones -- once "ket" is known empty,
        // "kettl" adds nothing and only lengthens the scan -- so they are
        // dropped as they are subsumed. The set stays a handful of short words
        // in practice, which is what keeps [knownEmpty]'s loop cheap.
        _empty.removeWhere((existing) => existing.contains(key));
        _empty.add(key);
      }
      return found;
    });
  }

  /// Forgets everything, for tests.
  void resetForTest() {
    _memo.clear();
    _empty.clear();
  }
}

/// Everything worth offering for [query], from every source, in one list.
///
/// Ordered by how likely each source is to be what the shopper meant:
///
///   1. **their own history**, because a query they have run before is the one
///      they are most often reaching for again;
///   2. **what the server matched**, which is a real department or brand;
///   3. **what is trending**, which is a real query other people are running.
///
/// The two local sources are filtered in memory on purpose, and it is not the
/// usual mistake: both are short, complete lists already held -- not a page of
/// a larger server-side set -- so narrowing them locally hides nothing.
List<SearchSuggestion> mergeSuggestions({
  required String query,
  required List<String> recent,
  required List<String> trending,
  required List<SearchSuggestion> fromServer,
  int limit = 6,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.length < SearchSuggestionRepository.minQueryLength) {
    return const [];
  }

  bool matches(String candidate) {
    final lower = candidate.toLowerCase();
    // Not an exact match: offering somebody the word they have already finished
    // typing is a row that does nothing.
    return lower.contains(needle) && lower != needle;
  }

  // A LinkedHashSet: insertion order is the ranking above, and the equality on
  // SearchSuggestion is what collapses the same word arriving twice.
  final merged = <SearchSuggestion>{};

  for (final query in recent.where(matches)) {
    merged.add(SearchSuggestion(text: query, kind: SuggestionKind.recent));
  }
  for (final suggestion in fromServer.where((s) => s.text.isNotEmpty)) {
    merged.add(suggestion);
  }
  for (final query in trending.where(matches)) {
    merged.add(SearchSuggestion(text: query, kind: SuggestionKind.trending));
  }

  return merged.take(limit).toList(growable: false);
}

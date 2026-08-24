/// Lenient readers for JSON that came off a wire.
///
/// Every one of these exists because a strict cast has already cost someone a
/// screen: Postgres `numeric` arrives as a string, a URL fragment has no types
/// at all, and an enum the server adds next month must not blank a page that
/// otherwise decodes fine. A field that cannot be read is missing, not fatal.
library;

num? asNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

int? asInt(Object? v) => asNum(v)?.toInt();

/// Trimmed, and empty means absent -- an empty string in a name field is not a
/// name, and rendering one leaves a mysterious gap.
String? asString(Object? v) {
  if (v is String) {
    final s = v.trim();
    return s.isEmpty ? null : s;
  }
  if (v is num || v is bool) return v.toString();
  return null;
}

bool asBool(Object? v, {bool orElse = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return orElse;
}

DateTime? asDate(Object? v) {
  if (v is DateTime) return v;
  final s = asString(v);
  if (s == null) return null;
  final parsed = DateTime.tryParse(s);
  return parsed?.toLocal();
}

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

/// The rows of a list response, whatever wrapper they arrived in.
///
/// The gateway is not consistent about this: `/orders` and `/notifications`
/// answer a bare array, `/addresses` answers either an array or
/// `{addresses: [...]}`, and `/returns` answers `{returns: [...]}`. Rather than
/// each repository guessing, they say which key to look under and get an empty
/// list instead of a crash when the server changes its mind.
List<Map<String, dynamic>> asRows(Object? v, {String? key}) {
  if (v is List) return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  if (v is Map) {
    if (key != null && v[key] is List) return asRows(v[key]);
    // Fall back to the first list-valued key, which covers a wrapper name we
    // did not anticipate.
    for (final value in v.values) {
      if (value is List) return asRows(value);
    }
  }
  return const [];
}

/// Strips HTML down to readable text.
///
/// Product blurbs come back with markup in them. Rendering that raw shows a
/// shopper angle brackets; rendering it as HTML would mean trusting a
/// third-party catalogue's markup, which is a worse trade.
String stripHtml(String input) {
  final withBreaks = input
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
  final text = withBreaks.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
      .trim();
}

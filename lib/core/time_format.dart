/// How this app talks about time.
///
/// One place, because a delivery estimate on the order page and the age of a
/// notification about that same delivery have to agree about what "today"
/// means.
library;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Dates the way a delivery is talked about: today and tomorrow by name, and
/// a short date otherwise. "Delivered on 23 Aug, 8:41 pm" is checkable in a
/// way that "2026-08-23T20:41:07" is not.
String formatWhen(DateTime when, {DateTime? now}) {
  final difference = _dayOffset(when, now ?? DateTime.now());
  final time = formatTime(when);

  if (difference == 0) return 'Today, $time';
  if (difference == 1) return 'Tomorrow, $time';
  if (difference == -1) return 'Yesterday, $time';
  return '${when.day} ${_months[when.month - 1]}, $time';
}

/// Just the day, for an estimate where the minute is false precision.
String formatDay(DateTime when, {DateTime? now}) {
  final difference = _dayOffset(when, now ?? DateTime.now());

  if (difference == 0) return 'today';
  if (difference == 1) return 'tomorrow';
  return '${when.day} ${_months[when.month - 1]}';
}

/// How long ago something happened, for a feed.
///
/// Coarse on purpose. "3 days ago" is what a shopper wants from a list of
/// notifications; the exact minute of a promotion three days old is noise, and
/// a ticking "179 seconds ago" is worse than useless.
String formatRelative(DateTime when, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final elapsed = at.difference(when);

  // A clock that has slipped, or an event stamped a moment in the future.
  // Reading "in -2 minutes" is worse than rounding to now.
  if (elapsed.isNegative) return 'Just now';

  if (elapsed.inSeconds < 60) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';

  // Calendar days, not 24-hour blocks. Hours are only used within today, so
  // something from 11pm last night reads as "Yesterday" rather than
  // "13 hours ago" -- which is the same night to a clock and a different day
  // to a person.
  final days = -_dayOffset(when, at);
  if (days == 0) {
    final hours = elapsed.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  }
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return '${when.day} ${_months[when.month - 1]}';
}

/// The heading a feed groups a day's entries under.
String formatDateHeading(DateTime when, {DateTime? now}) {
  final difference = _dayOffset(when, now ?? DateTime.now());

  if (difference == 0) return 'Today';
  if (difference == -1) return 'Yesterday';
  return '${when.day} ${_months[when.month - 1]} ${when.year}';
}

String formatTime(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${when.hour < 12 ? 'am' : 'pm'}';
}

/// Whole calendar days between [when] and [now], ignoring the time of day.
int _dayOffset(DateTime when, DateTime now) {
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  return day.difference(today).inDays;
}

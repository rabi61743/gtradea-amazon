import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';

/// When this device last opened each conversation.
///
/// The support API has no read state: a ticket carries no `unread_count`, and
/// no endpoint marks one seen. So "unread" here is worked out rather than
/// received -- a support reply stamped later than the last time this device
/// opened the thread is one the shopper has not read.
///
/// Two consequences worth being plain about, because they are the honest cost
/// of the server not modelling this:
///
///   * It is **per device**. Reading a reply in the web storefront does not
///     clear the badge here, and nothing this app writes is sent anywhere.
///   * A thread this device has **never** opened counts every support reply as
///     unread, because there is no evidence it was read. That errs towards
///     surfacing a reply rather than hiding one.
///
/// One set of markers per account, and one for a guest, keyed exactly the way
/// the other per-account stores key theirs: with two accounts on a device,
/// what one has read is not what the other has read.
class ThreadReads {
  ThreadReads._();

  static const _key = 'gtradea_message_reads';

  /// Where [accountId]'s markers live. A guest's are the bare key.
  static String storageKeyFor(String? accountId) =>
      (accountId == null || accountId.isEmpty) ? _key : '${_key}_$accountId';

  static String get _currentKey =>
      storageKeyFor(AuthStore.instance.account?.id);

  /// Every marker this account has, by ticket id.
  static Future<Map<String, DateTime>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_currentKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        // A marker that will not parse is dropped rather than guessed at: the
        // entry simply goes missing, and that thread reads as never opened.
        for (final entry in decoded.entries)
          '${entry.key}': ?DateTime.tryParse('${entry.value}'),
      };
    } catch (_) {
      // Unreadable markers mean everything reads as unread, which is the safe
      // direction: a reply is surfaced rather than quietly hidden.
      return const {};
    }
  }

  /// Records that the shopper has just looked at [ticketId].
  ///
  /// Stamped when the thread is *left* rather than when it is opened, so a
  /// reply that lands while it is on screen is not marked read before it has
  /// been seen.
  static Future<void> markOpened(String ticketId, {DateTime? at}) async {
    if (ticketId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _currentKey;
      final held = await all();
      final merged = {
        for (final entry in held.entries) entry.key: entry.value.toUtc()
            .toIso8601String(),
        ticketId: (at ?? DateTime.now()).toUtc().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(merged));
    } catch (_) {
      // Best effort, like the other local stores: a marker that fails to save
      // costs a badge that stays lit, nothing more.
    }
  }

  @visibleForTesting
  static Future<void> clearForTest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_currentKey);
    } catch (_) {
      // Nothing to clear.
    }
  }
}

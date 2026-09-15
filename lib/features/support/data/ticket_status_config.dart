import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/colors.dart';
import 'support_repository.dart';

/// How one conversation status is shown.
///
/// A status is whatever token the server put on the ticket. Nothing here is an
/// allowlist: a status this build has never heard of still gets a label, a
/// colour and a place in the filter row.
@immutable
class TicketStatusStyle {
  const TicketStatusStyle({
    required this.token,
    required this.label,
    this.order,
    this.colour,
    this.enabled = true,
    this.fromBackend = false,
  });

  /// The server's own value, e.g. `waiting_customer`.
  final String token;

  /// What to call it on screen.
  final String label;

  /// Where it sits in the filter row. Null sorts after everything configured.
  final int? order;

  /// The configured colour, when the shop set one.
  final Color? colour;

  /// False hides the status from the filter row. Rows still render their tag:
  /// a ticket in a hidden state is still in that state, and saying nothing
  /// about it would be a blank where the truth was.
  final bool enabled;

  /// True when the shop configured this, false when the app worked it out.
  ///
  /// Worth carrying so a test -- and anyone reading a bug report -- can tell a
  /// label the backend chose from one derived on the device.
  final bool fromBackend;

  /// The colour to draw the tag in.
  ///
  /// The configured one where there is one. Otherwise read from the token's
  /// own words, which is the only honest option while the shop configures
  /// nothing: a status asking the shopper to act is the accent, one that is
  /// finished is quiet, one in flight is the brand blue.
  Color colourOn(ThemeData theme) {
    final configured = colour;
    if (configured != null) return configured;

    final s = token.toLowerCase();
    if (s.contains('await') || s.contains('waiting') || s.contains('pending')) {
      return AppColors.accent;
    }
    if (s.contains('resolve') || s.contains('complete')) {
      return AppColors.successInk;
    }
    if (s.contains('close') || s.contains('cancel') || s.contains('archiv')) {
      return theme.colorScheme.onSurfaceVariant;
    }
    if (s.contains('open') || s.contains('progress') || s.contains('active')) {
      return theme.colorScheme.primary;
    }
    return theme.colorScheme.onSurfaceVariant;
  }
}

/// Turns a raw status token into words: `waiting_customer` -> "Waiting
/// Customer", `awaiting_seller_reply` -> "Awaiting Seller Reply".
///
/// The last resort, and the reason a status invented next month still reads as
/// English rather than as a database value.
String humaniseStatus(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  if (cleaned.isEmpty) return '';
  return cleaned
      .split(RegExp(r'\s+'))
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
}

/// The shop's conversation-status configuration.
///
/// Read from `site-settings/support_ticket_statuses`, which is the same
/// key/value store the payment methods, the flash sale and the support address
/// already come from -- and which answers the same shape they do:
///
/// ```json
/// { "waiting_customer": { "label": "Awaiting Your Reply",
///                         "color": "#E94724", "order": 1, "enabled": true } }
/// ```
///
/// A list of rows works too, each naming its own `status`/`value`/`token`.
///
/// **The key resolves today and its value is null**: nothing is configured, so
/// every label below is currently derived on the device. That is the whole
/// point of reading it anyway -- the day somebody seeds it, the labels, colours
/// and ordering become the shop's without an app release.
class TicketStatusConfig {
  TicketStatusConfig._();

  static final TicketStatusConfig instance = TicketStatusConfig._();

  static const settingKey = 'support_ticket_statuses';

  Dio get _dio => ApiClient.http;

  /// What the shop configured, by token. Empty until [load] has run, and still
  /// empty after it when the setting is unset -- which is the normal state.
  Map<String, TicketStatusStyle> _configured = const {};

  Future<void>? _inFlight;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// True when the shop actually configures statuses. False is the ordinary
  /// case and is not an error.
  bool get hasBackendConfig => _configured.isNotEmpty;

  /// Reads the configuration, once per run.
  ///
  /// Never throws: a status configuration that cannot be read is a cosmetic
  /// loss, and a Messages screen that refused to open because of it would be a
  /// far worse failure than labels derived on the device.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _inFlight ??= _read().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _read() async {
    try {
      final res = await _dio.get(
        '/site-settings/$settingKey',
        options: guestCall,
      );
      final body = asMap(res.data);
      final value = body.containsKey('setting_value')
          ? body['setting_value']
          : body;
      _configured = _parse(value);
    } catch (_) {
      // Unset, unreachable, or a shape this build cannot read. All three mean
      // the same thing here: nothing configured, carry on deriving.
      _configured = const {};
    } finally {
      _loaded = true;
    }
  }

  /// Reads either shape the settings store is used with.
  static Map<String, TicketStatusStyle> _parse(Object? value) {
    final out = <String, TicketStatusStyle>{};

    void add(String? token, Map<String, dynamic> row, int fallbackOrder) {
      final key = (token ?? '').trim();
      if (key.isEmpty) return;
      out[key.toLowerCase()] = TicketStatusStyle(
        token: key,
        label: asString(row['label']) ?? humaniseStatus(key),
        order: asInt(row['order']) ?? fallbackOrder,
        colour: _colour(asString(row['color']) ?? asString(row['colour'])),
        enabled: asBool(row['enabled'], orElse: true),
        fromBackend: true,
      );
    }

    if (value is Map) {
      var i = 0;
      for (final entry in value.entries) {
        final row = entry.value;
        if (row is Map) {
          add('${entry.key}', row.cast<String, dynamic>(), i);
        } else if (row is String) {
          // The terse shape: token -> label.
          add('${entry.key}', {'label': row}, i);
        }
        i++;
      }
    } else if (value is List) {
      var i = 0;
      for (final row in value.whereType<Map>()) {
        final map = row.cast<String, dynamic>();
        add(
          asString(map['status']) ??
              asString(map['value']) ??
              asString(map['token']) ??
              asString(map['key']),
          map,
          i,
        );
        i++;
      }
    }

    return out;
  }

  /// `#RRGGBB`, `RRGGBB` or `#AARRGGBB`. Null when it is not a colour.
  static Color? _colour(String? raw) {
    if (raw == null) return null;
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  /// How to show [token].
  ///
  /// Three tiers, in order: what the shop configured, then the labels this app
  /// and the storefront have always used for the statuses the support system
  /// ships with, then the token's own words. The middle tier is why a ticket
  /// still reads "Awaiting your reply" rather than "Waiting Customer" while
  /// nothing is configured -- and it is not an allowlist: anything it does not
  /// know falls through to the last tier rather than being hidden.
  TicketStatusStyle styleFor(String token) {
    final key = token.trim().toLowerCase();
    if (key.isEmpty) {
      return const TicketStatusStyle(token: '', label: '');
    }

    final configured = _configured[key];
    if (configured != null) return configured;

    // `customerTicketStatusLabel` returns the token with its underscores
    // stripped for anything it does not know, so an unknown status is detected
    // by the label coming back unchanged rather than by asking it twice.
    final known = customerTicketStatusLabel(key);
    final isKnown = known != key.replaceAll('_', ' ');

    return TicketStatusStyle(
      token: token,
      label: isKnown ? known : humaniseStatus(token),
    );
  }

  /// The statuses to offer as filters, for the tickets actually in hand.
  ///
  /// Built from the real data rather than from a list of what might exist: a
  /// filter that matches nothing is a dead tab, and one missing for a status
  /// the shopper has is worse. Configured statuses lead, in the shop's own
  /// order; anything unconfigured follows alphabetically so the row is stable
  /// between loads.
  List<TicketStatusStyle> filtersFor(Iterable<String> tokens) {
    final seen = <String, TicketStatusStyle>{};
    for (final token in tokens) {
      final style = styleFor(token);
      if (style.token.isEmpty || !style.enabled) continue;
      seen.putIfAbsent(style.token.toLowerCase(), () => style);
    }

    final styles = seen.values.toList()
      ..sort((a, b) {
        final ao = a.order;
        final bo = b.order;
        if (ao != null && bo != null) return ao.compareTo(bo);
        if (ao != null) return -1;
        if (bo != null) return 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return styles;
  }

  @visibleForTesting
  void resetForTest() {
    _configured = const {};
    _loaded = false;
    _inFlight = null;
  }

  /// Stands in for a shop that has configured its statuses.
  @visibleForTesting
  void seedForTest(Map<String, TicketStatusStyle> styles) {
    _configured = {
      for (final entry in styles.entries) entry.key.toLowerCase(): entry.value,
    };
    _loaded = true;
  }
}

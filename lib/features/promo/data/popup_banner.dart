import 'package:flutter/foundation.dart';

import '../../../core/network/json.dart';

/// The promotion shown once over the storefront after startup.
///
/// Read from the admin-managed site setting `app_popup_banner`. The artwork
/// carries the headline, the offer and the call to action itself, the way the
/// campaign designs are drawn, so the only text here is what a screen reader
/// says for it.
@immutable
class PopupBanner {
  const PopupBanner({
    required this.id,
    required this.imageUrl,
    this.buttonLink,
    this.altText,
    this.startDate,
    this.endDate,
    this.isActive = true,
  });

  /// Changes per campaign. What "already closed" is remembered against, so a
  /// new campaign is shown even to somebody who closed the last one.
  final String id;
  final String imageUrl;

  /// Where tapping the artwork goes. Optional: without one the tap just closes.
  final String? buttonLink;
  final String? altText;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;

  /// Null for anything that cannot be shown: no id, no picture, or not an
  /// object at all. A half-filled setting shows nothing rather than a blank.
  static PopupBanner? fromJson(Object? raw) {
    final json = asMap(raw);
    final id = asString(json['id']);
    final image = asString(json['image_url']);
    if (id == null || image == null) return null;
    return PopupBanner(
      id: id,
      imageUrl: image,
      buttonLink: asString(json['button_link']),
      altText: asString(json['alt_text']),
      startDate: asDate(json['start_date']),
      endDate: asDate(json['end_date']),
      isActive: asBool(json['is_active'], orElse: true),
    );
  }

  /// Switched on, and inside its dates. A bare date as the end runs to the
  /// end of that day, which is what an admin typing "ends on the 20th" means.
  bool isLive(DateTime now) {
    if (!isActive) return false;
    final start = startDate;
    if (start != null && now.isBefore(start)) return false;
    final end = endDate;
    if (end != null) {
      final dateOnly = end.hour == 0 && end.minute == 0 && end.second == 0;
      final last = dateOnly ? end.add(const Duration(days: 1)) : end;
      if (!now.isBefore(last)) return false;
    }
    return true;
  }
}

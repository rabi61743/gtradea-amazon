import 'package:flutter/material.dart';

import '../../../core/network/json.dart';

/// What kind of thing a payment method is.
///
/// Drives the icon and, for [card], whether a form is needed before the order
/// can be sent. Derived from the method's id rather than sent by the server,
/// which describes methods but does not classify them.
enum PaymentKind {
  wallet,
  bank,
  card,
  cashOnDelivery,
  other;

  static PaymentKind of(String id) {
    switch (id) {
      case 'khalti':
      case 'esewa':
        return PaymentKind.wallet;
      case 'connectips':
      case 'fonepay':
      case 'fonepayintent':
      case 'nps':
        return PaymentKind.bank;
      case 'card':
        return PaymentKind.card;
      case 'cod':
        return PaymentKind.cashOnDelivery;
      default:
        return PaymentKind.other;
    }
  }

  IconData get icon => switch (this) {
        PaymentKind.wallet => Icons.account_balance_wallet_outlined,
        PaymentKind.bank => Icons.account_balance_outlined,
        PaymentKind.card => Icons.credit_card,
        PaymentKind.cashOnDelivery => Icons.local_shipping_outlined,
        PaymentKind.other => Icons.payments_outlined,
      };
}

/// One way to pay, as the storefront has it configured.
///
/// Read from `site_settings.active_payment_methods` rather than hard-coded.
/// The set of methods a shop accepts is an operational decision that changes
/// without an app release -- and a method offered here that the server has
/// switched off fails at the gateway, after the shopper has committed.
@immutable
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.label,
    required this.description,
    required this.order,
    this.badge,
    this.isDefault = false,
    this.betaUserIds = const [],
  });

  /// The gateway path segment: khalti, esewa, connectips, cod.
  final String id;

  /// Server-authored, so a shop can rename a method without an app release.
  final String label;
  final String description;

  /// Where it sits in the list. The shop's ordering, not this app's opinion.
  final int order;

  /// "Recommended", "Nepal Only". Shown verbatim when present.
  final String? badge;

  final bool isDefault;

  /// When non-empty, only these accounts see the method. A half-finished
  /// integration is switched on for the people testing it and nobody else.
  final List<String> betaUserIds;

  PaymentKind get kind => PaymentKind.of(id);

  /// Whether [userId] is allowed to see this.
  ///
  /// Fail-closed: a beta method with no signed-in user is hidden. Showing one
  /// that then refuses at the gateway is worse than not offering it.
  bool isVisibleTo(String? userId) {
    if (betaUserIds.isEmpty) return true;
    return userId != null && betaUserIds.contains(userId);
  }

  factory PaymentMethod.fromJson(String id, Map<String, dynamic> json) {
    final beta = json['betaUserIds'];
    return PaymentMethod(
      id: id,
      label: asString(json['label']) ?? id,
      description: asString(json['description']) ?? '',
      order: asInt(json['order']) ?? 99,
      badge: asString(json['badge']),
      isDefault: asBool(json['isDefault']),
      betaUserIds: beta is List
          ? beta.map(asString).whereType<String>().toList(growable: false)
          : const [],
    );
  }
}

/// Decodes the whole `active_payment_methods` map.
///
/// Anything not `enabled` is dropped here rather than filtered later, so there
/// is no path by which a switched-off method reaches a screen.
List<PaymentMethod> decodePaymentMethods(Object? raw) {
  final map = asMap(raw);
  final methods = <PaymentMethod>[];

  for (final entry in map.entries) {
    final config = asMap(entry.value);
    if (config.isEmpty) continue;
    if (!asBool(config['enabled'])) continue;
    methods.add(PaymentMethod.fromJson(entry.key, config));
  }

  methods.sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    // A stable tiebreak: two methods share an order today, and a list that
    // reshuffled between builds would move the default under the finger.
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  });
  return methods;
}

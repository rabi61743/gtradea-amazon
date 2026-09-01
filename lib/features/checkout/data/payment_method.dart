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
    this.enabled = true,
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

  /// Accounts that see the method even while it is switched off. A
  /// half-finished integration is opened to the people testing it, and to
  /// nobody else, until it goes live for everyone.
  ///
  /// It **widens** access rather than restricting it -- see [isVisibleTo].
  final List<String> betaUserIds;

  /// Whether the shop has this switched on for everyone.
  final bool enabled;

  PaymentKind get kind => PaymentKind.of(id);

  /// Whether [userId] is allowed to see this.
  ///
  /// Switched on, or a tester of something not switched on yet. This is the
  /// storefront's own rule, and matching it is load-bearing: the live config
  /// gives eSewa `enabled: true` *and* a beta list, and reading that list as a
  /// restriction hid a working, fully implemented gateway from every shopper
  /// while the website offered it to all of them.
  bool isVisibleTo(String? userId) =>
      enabled || (userId != null && betaUserIds.contains(userId));

  factory PaymentMethod.fromJson(String id, Map<String, dynamic> json) {
    final beta = json['betaUserIds'];
    return PaymentMethod(
      id: id,
      enabled: asBool(json['enabled']),
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
/// A method that is switched off and has no testers is dropped here, so there
/// is no path by which it reaches a screen. One with a beta list survives --
/// it is not for everyone, but it is for someone, and only [PaymentMethod
/// .isVisibleTo] knows who is signed in. Dropping it here is what made the
/// beta gate unreachable.
List<PaymentMethod> decodePaymentMethods(Object? raw) {
  final map = asMap(raw);
  final methods = <PaymentMethod>[];

  for (final entry in map.entries) {
    final config = asMap(entry.value);
    if (config.isEmpty) continue;
    final beta = config['betaUserIds'];
    final hasTesters = beta is List && beta.isNotEmpty;
    if (!asBool(config['enabled']) && !hasTesters) continue;
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

import 'package:flutter/foundation.dart';

import '../../../core/network/json.dart';

/// The customer's profile row, as `/api/v1/profile` returns it.
///
/// Distinct from `Account`, and deliberately so. `Account` is a view of the
/// **GoTrue user** -- identity, and whatever the sign-up put in
/// `user_metadata`. This is the **gateway's own profile row**, which is where
/// the name, the phone and the avatar actually live and the only thing the
/// storefront writes to. The two overlap on name and email and disagree
/// whenever one has been updated and the other has not, which is why the
/// settings page reads this one.
///
/// Field names are the server's, verified against the storefront bundle rather
/// than guessed: `first_name`, `last_name`, `avatar_url`, `marketing_opt_in`.
@immutable
class Profile {
  const Profile({
    required this.id,
    this.email = '',
    this.firstName,
    this.lastName,
    this.phone,
    this.avatarUrl,
    this.marketingOptIn = false,
  });

  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;

  /// A public URL the media service handed back, or whatever an OAuth provider
  /// put there. Null for most accounts, and null is drawn as the initial.
  final String? avatarUrl;

  final bool marketingOptIn;

  /// What to show. The two names when there are any, the address otherwise --
  /// never a blank, because a heading with nothing in it reads as a page that
  /// failed to load.
  String get displayName {
    final full = [firstName, lastName]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    if (full.isNotEmpty) return full;
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// The whole name as one field, which is what the page edits.
  ///
  /// The server keeps two. A single "Name" box is what was asked for and is the
  /// better question -- plenty of Nepali names do not split into two halves at
  /// all -- so the split happens here, at the boundary, rather than in the UI.
  String get fullName => [firstName, lastName]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(' ');

  /// Splits a typed name back into the pair the server stores.
  ///
  /// Everything before the last space is the first name, so "Rabi Kumar Yadav"
  /// keeps "Rabi Kumar" together rather than dropping the middle. A name with
  /// no space at all is a first name and an empty last one, which the server
  /// accepts -- it is also the honest reading of a mononym.
  static ({String first, String last}) splitName(String value) {
    final parts = value.trim().split(RegExp(r'\s+'))
      ..removeWhere((s) => s.isEmpty);
    if (parts.isEmpty) return (first: '', last: '');
    if (parts.length == 1) return (first: parts.first, last: '');
    return (
      first: parts.sublist(0, parts.length - 1).join(' '),
      last: parts.last,
    );
  }

  static Profile? fromJson(Map<String, dynamic> json) {
    // The gateway wraps some payloads and returns others bare. Both shapes are
    // read rather than assuming this one is the bare kind.
    final row = json['profile'] is Map
        ? (json['profile'] as Map).cast<String, dynamic>()
        : json;

    final id = asString(row['id']) ?? asString(row['user_id']);
    if (id == null) return null;

    return Profile(
      id: id,
      email: asString(row['email']) ?? '',
      firstName: asString(row['first_name']),
      lastName: asString(row['last_name']),
      phone: asString(row['phone']),
      avatarUrl: asString(row['avatar_url']),
      marketingOptIn: asBool(row['marketing_opt_in']),
    );
  }

  Profile copyWith({
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    String? avatarUrl,
    bool? marketingOptIn,
  }) => Profile(
    id: id,
    email: email ?? this.email,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    phone: phone ?? this.phone,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    marketingOptIn: marketingOptIn ?? this.marketingOptIn,
  );
}

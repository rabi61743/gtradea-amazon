import 'package:flutter/foundation.dart';

import '../../../core/network/json.dart';

/// One phone number on the account.
///
/// The account's own number lives in two places and they do not agree by
/// themselves:
///
///   * the **gateway profile row** (`phone`), which is what checkout reads and
///     what a courier is given;
///   * the **GoTrue user** (`phone` and `phone_confirmed_at`), which is the only
///     place in this system that records whether a number was ever *proved* to
///     belong to whoever is holding it.
///
/// [verified] therefore comes from GoTrue and nowhere else. It is never set by
/// this app: a tick beside a number that no server checked is a claim about
/// someone's identity that nothing backs, and it would be believed.
@immutable
class PhoneNumber {
  const PhoneNumber({
    required this.e164,
    this.verified = false,
    this.primary = false,
  });

  /// The number in E.164 -- `+9779812345678`. The only format GoTrue accepts,
  /// and the only one two numbers can be compared in without guessing at a
  /// country.
  final String e164;

  /// Proved, by the server, to reach whoever entered it. From GoTrue's
  /// `phone_confirmed_at`; false until that field exists.
  final bool verified;

  /// The number the account actually uses -- what checkout sends and what a
  /// courier is given.
  ///
  /// Today the gateway profile holds exactly one `phone`, so the primary is
  /// whichever number that column carries. When the backend grows a phones
  /// table this becomes its own flag and nothing above here changes.
  final bool primary;

  /// What to show. Grouped the way the numbers are dialled locally rather than
  /// as one run of digits, because a number nobody can read cannot be checked
  /// by the person it belongs to.
  ///
  /// Nepali mobiles are +977 then ten digits; anything else is left alone,
  /// since inventing a grouping for a country this does not know is worse than
  /// showing the number as it was given.
  String get display {
    if (!e164.startsWith('+977')) return e164;
    final rest = e164.substring(4);
    return rest.length == 10 ? '+977 $rest' : e164;
  }

  /// The two spellings GoTrue uses. `phone` on the user object has no `+`,
  /// which is why a raw comparison against a typed number fails.
  static String normalise(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? '' : '+$digits';
  }

  /// Reads the pair out of a GoTrue user object.
  ///
  /// Returns null when the account has no number at all, which is the ordinary
  /// case: this app signs up with an email address.
  static PhoneNumber? fromGoTrueUser(Map<String, dynamic> user) {
    final raw = asString(user['phone']);
    if (raw == null || raw.isEmpty) return null;
    return PhoneNumber(
      e164: normalise(raw),
      // Present and non-empty is GoTrue saying it sent a code to this number
      // and someone typed it back. Absent means unproved, whatever else the
      // row says.
      verified: (asString(user['phone_confirmed_at']) ?? '').isNotEmpty,
    );
  }

  PhoneNumber copyWith({bool? verified, bool? primary}) => PhoneNumber(
    e164: e164,
    verified: verified ?? this.verified,
    primary: primary ?? this.primary,
  );

  @override
  bool operator ==(Object other) =>
      other is PhoneNumber &&
      other.e164 == e164 &&
      other.verified == verified &&
      other.primary == primary;

  @override
  int get hashCode => Object.hash(e164, verified, primary);

  @override
  String toString() =>
      'PhoneNumber($e164, verified: $verified, primary: $primary)';
}

/// How far along a verification is.
enum PhoneVerificationStage {
  /// Asking for the number.
  entering,

  /// A code has been sent and is being waited for.
  confirming,

  /// The server accepted the code.
  done,
}

/// What a send or a resend was refused for.
///
/// Told apart because the screens say different things and offer different
/// ways out: a cooldown is waited for, a bad number is retyped, and an
/// unconfigured SMS provider is not the shopper's problem at all.
enum PhoneOtpRefusal {
  /// GoTrue's own rate limit. [OtpCooldown.seconds] carries what it said.
  cooldown,

  /// The number was rejected as malformed or unroutable.
  badNumber,

  /// The account already carries this number, verified.
  alreadyYours,

  /// The project has no SMS provider wired up. Nothing the shopper can do.
  smsUnavailable,

  /// Anything else the server said.
  other,
}

/// A refusal, with whatever the server told us about it.
@immutable
class OtpCooldown implements Exception {
  const OtpCooldown({
    required this.reason,
    required this.message,
    this.seconds,
  });

  final PhoneOtpRefusal reason;

  /// The server's own words, which the screens show rather than paraphrase.
  final String message;

  /// How long until another code may be asked for, when the server said.
  final int? seconds;

  @override
  String toString() => 'OtpCooldown($reason, $seconds s): $message';
}

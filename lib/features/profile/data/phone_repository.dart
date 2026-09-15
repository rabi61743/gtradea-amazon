import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../auth/data/auth_repository.dart';
import 'phone_number.dart';

/// Sending and checking phone codes, and the numbers an account holds.
///
/// **Every call here is a real server call.** Nothing in this file invents a
/// code, a cooldown or a verification. The two that matter are GoTrue's own,
/// which this project already runs:
///
///   * `POST /auth/v1/otp` with `{phone}` -- the server generates the code and
///     sends the SMS. There is no code in this app to leak or guess.
///   * `POST /auth/v1/verify` with `{phone, token, type: 'sms'}` -- the server
///     decides. A wrong or expired code is refused there, and the only thing
///     this app does with the answer is read it.
///
/// After GoTrue confirms, the number is written to the gateway profile with the
/// existing `PATCH /profile`, because that is the row checkout and the couriers
/// read. Two writes, in that order: the profile is never told about a number
/// the server has not proved.
///
/// **What this cannot do yet.** The gateway profile holds exactly one `phone`
/// column and there is no phones table, so [list] returns at most one number
/// and [remove] is refused. The shape here is the one a phones endpoint would
/// fill: when it exists, this file changes and nothing above it does.
class PhoneRepository {
  PhoneRepository._();

  static final PhoneRepository instance = PhoneRepository._();

  AuthRepository _auth = AuthRepository.instance;

  /// Swaps GoTrue for a stub, the way [ProfileStore] already does.
  set authRepositoryForTest(AuthRepository repo) => _auth = repo;

  /// Walks the flow without an SMS provider, for looking at the screens.
  ///
  /// **This is a verification bypass and it must never ship.** Two things stop
  /// it. [kDebugMode] is a compile-time constant that is `false` in a release
  /// build, so every branch guarded by it is removed by the compiler rather
  /// than merely skipped -- the bypass does not exist in a release binary. And
  /// the screens draw a banner whenever it is on, so a demo can never be
  /// mistaken for a verification that happened.
  ///
  /// What it changes: no code is sent, and [demoCode] is accepted in place of
  /// one. What it does **not** change: the number is still written to the real
  /// profile through the real `PATCH /profile`, because the point of looking at
  /// the flow is to see the settings page update afterwards.
  ///
  /// It follows that a number confirmed this way is *not* verified, and this
  /// says so: [PhoneNumber.verified] stays false, so the success panel shows no
  /// tick. A demo that claimed a number was proved would be the exact lie the
  /// rest of this file exists to prevent.
  /// On in a debug build so the screens can be walked without an SMS provider,
  /// and impossible in a release one: [demoActive] ands this with [kDebugMode],
  /// which the compiler folds to `false` and removes the branch entirely.
  static bool demo = true;

  /// The code the demo accepts. Any six digits, so there is nothing to
  /// remember; a wrong *length* is still refused, so the box behaves.
  static const demoCode = 6;

  /// Whether the bypass is actually live: opted into, and a debug build.
  static bool get demoActive => kDebugMode && demo;

  Dio get _gateway => ApiClient.http;

  /// Every number the account holds, most trustworthy first.
  ///
  /// Reads GoTrue for whether a number is proved and the gateway for which one
  /// is actually used. One number today; a list because the screens are built
  /// for the plural and a second one changes nothing here but this method.
  Future<List<PhoneNumber>> list() => guarded(() async {
    final user = await _auth.currentUserOrNull();
    final fromAuth = user == null
        ? null
        : PhoneNumber.fromGoTrueUser(user);

    final res = await _gateway.get('/profile');
    final row = asMap(res.data);
    final profile = row['profile'] is Map
        ? (row['profile'] as Map).cast<String, dynamic>()
        : row;
    final onProfile = asString(profile['phone']);

    final out = <PhoneNumber>[];
    if (fromAuth != null) {
      // The number checkout uses is the primary, and that is the profile's.
      final same =
          onProfile != null &&
          PhoneNumber.normalise(onProfile) == fromAuth.e164;
      out.add(fromAuth.copyWith(primary: same));
    }
    if (onProfile != null && onProfile.trim().isNotEmpty) {
      final e164 = PhoneNumber.normalise(onProfile);
      if (!out.any((p) => p.e164 == e164)) {
        // On the profile but never proved through GoTrue: shown, and shown as
        // unverified, because that is what it is.
        out.add(PhoneNumber(e164: e164, primary: true));
      }
    }
    return List.unmodifiable(out);
  });

  /// Asks the server to text a code to [e164].
  ///
  /// Throws [OtpCooldown] with the server's own reason. The cooldown is
  /// GoTrue's, read off its 429 -- this app does not decide how long to wait,
  /// it reports what it was told.
  Future<void> sendCode(String e164) async {
    // Stripped from a release build: see [demo].
    if (demoActive) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return;
    }
    try {
      await _auth.sendPhoneOtp(e164);
    } on ApiError catch (e) {
      throw _refusalFor(e);
    }
  }

  /// Hands the typed code to the server.
  ///
  /// Returns the confirmed number. A wrong or expired code never reaches this
  /// return: GoTrue refuses it and the error carries its words.
  Future<PhoneNumber> confirmCode({
    required String e164,
    required String code,
  }) async {
    // Stripped from a release build: see [demo]. The number is still written
    // to the real profile, and is deliberately *not* marked verified -- no
    // server checked it, so nothing here may claim one did.
    if (demoActive) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (code.trim().length != demoCode) {
        throw const ApiError(
          statusCode: 400,
          message: 'Enter the 6-digit code.',
          local: true,
        );
      }
      await guarded(() async {
        await _gateway.patch('/profile', data: {'phone': e164});
      });
      return PhoneNumber(e164: e164, primary: true);
    }

    final Map<String, dynamic> user;
    try {
      user = await _auth.verifyPhoneOtp(phone: e164, token: code);
    } on ApiError catch (e) {
      throw _refusalFor(e);
    }

    final confirmed = PhoneNumber.fromGoTrueUser(user);
    if (confirmed == null || !confirmed.verified) {
      // The server answered without confirming. Reported rather than shown as
      // success: a "Verified" screen over an unconfirmed number is the one
      // outcome this whole flow exists to prevent.
      throw const ApiError(
        statusCode: null,
        message: 'The server did not confirm that number. Try again.',
        local: true,
      );
    }

    // Only now does the row checkout reads learn about it.
    await guarded(() async {
      await _gateway.patch('/profile', data: {'phone': confirmed.e164});
    });

    return confirmed.copyWith(primary: true);
  }

  /// Taking a number off the account.
  ///
  /// Refused, and deliberately: with one `phone` column there is no "other"
  /// number to fall back to, and an account with no number cannot check out --
  /// the server refuses an order that carries none. Clearing it here would
  /// break checkout silently.
  Future<void> remove(PhoneNumber number) async {
    throw const ApiError(
      statusCode: null,
      message:
          'This account keeps one phone number. Add a new one to replace it.',
      local: true,
    );
  }

  /// Reads a refusal into something the screens can act on.
  ///
  /// The strings are GoTrue's. Matched loosely on purpose: its wording has
  /// changed between versions and a flow that breaks on a reworded error is
  /// worse than one that falls back to showing the server's own sentence.
  static OtpCooldown _refusalFor(ApiError e) {
    final text = e.message.toLowerCase();

    if (e.statusCode == 429 || text.contains('rate limit')) {
      return OtpCooldown(
        reason: PhoneOtpRefusal.cooldown,
        message: e.message,
        seconds: _secondsIn(e.message),
      );
    }
    if (text.contains('sms provider') ||
        text.contains('not configured') ||
        text.contains('unsupported phone provider')) {
      return OtpCooldown(
        reason: PhoneOtpRefusal.smsUnavailable,
        message: e.message,
      );
    }
    if (text.contains('invalid phone') ||
        text.contains('phone number') && text.contains('invalid')) {
      return OtpCooldown(
        reason: PhoneOtpRefusal.badNumber,
        message: e.message,
      );
    }
    if (text.contains('already been registered') ||
        text.contains('already registered')) {
      return OtpCooldown(
        reason: PhoneOtpRefusal.alreadyYours,
        message: e.message,
      );
    }
    return OtpCooldown(reason: PhoneOtpRefusal.other, message: e.message);
  }

  /// The number of seconds out of "For security purposes, you can only request
  /// this after 54 seconds." Null when the sentence carries none, and then the
  /// screen falls back to its own wait rather than inventing a figure.
  static int? _secondsIn(String message) {
    final match = RegExp(r'(\d+)\s*second').firstMatch(message.toLowerCase());
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }
}

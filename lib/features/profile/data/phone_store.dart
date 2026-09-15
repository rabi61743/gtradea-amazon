import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_store.dart';
import 'phone_number.dart';
import 'phone_repository.dart';

/// One run through the phone verification, and the numbers the account holds.
///
/// A [ChangeNotifier] in the same shape as [ProfileStore], so the screens watch
/// it rather than each holding a copy of where the flow has got to.
///
/// **The countdowns here are the server's, not this app's.** The resend wait is
/// whatever GoTrue's refusal said, and the expiry is the one figure this app
/// does choose -- see [_defaultExpiry] -- because GoTrue does not publish it on
/// the send. Neither timer decides anything: a code is accepted or refused by
/// the server whatever the clock on screen says, so a countdown that runs out
/// early costs a shopper a resend, not a verification.
class PhoneStore extends ChangeNotifier {
  PhoneStore._();

  static final PhoneStore instance = PhoneStore._();

  PhoneRepository _phones = PhoneRepository.instance;

  @visibleForTesting
  set repositoryForTest(PhoneRepository repo) => _phones = repo;

  /// How long the code is shown as good for.
  ///
  /// GoTrue's default SMS lifetime, and it is a *display* figure: the server is
  /// what actually expires a code. Shown so the screen can say something true
  /// about roughly how long is left rather than leave someone waiting on a box
  /// that quietly stopped working.
  static const _defaultExpiry = Duration(minutes: 5);

  /// What the screen falls back to when a refusal carries no figure.
  static const _defaultCooldown = 60;

  List<PhoneNumber> _numbers = const [];
  bool _loading = false;
  String? _loadError;

  PhoneVerificationStage _stage = PhoneVerificationStage.entering;
  String? _pending;
  PhoneNumber? _confirmed;

  bool _sending = false;
  bool _confirming = false;
  String? _error;

  Timer? _ticker;
  int _expiresIn = 0;
  int _resendIn = 0;

  // ── What the screens read ─────────────────────────────────────────────────

  List<PhoneNumber> get numbers => _numbers;
  bool get loading => _loading;
  String? get loadError => _loadError;

  PhoneVerificationStage get stage => _stage;

  /// The number a code was sent to, in E.164. Null before the first send.
  String? get pending => _pending;

  /// The number the server confirmed, once it has.
  PhoneNumber? get confirmed => _confirmed;

  bool get sending => _sending;
  bool get confirming => _confirming;

  /// The last refusal, in the server's own words. Cleared on the next attempt.
  String? get error => _error;

  /// Seconds until the code is expected to stop working, or zero.
  int get expiresIn => _expiresIn;

  /// Seconds until another code may be asked for, or zero when it may now.
  int get resendIn => _resendIn;

  bool get canResend => _resendIn == 0 && !_sending;

  /// mm:ss, for the two places the reference prints a clock.
  static String clock(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── The numbers on the account ────────────────────────────────────────────

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_numbers.isNotEmpty && !force) return;
    if (!AuthStore.instance.isSignedIn) return;

    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      _numbers = await _phones.list();
    } on ApiError catch (e) {
      _loadError = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── The flow ──────────────────────────────────────────────────────────────

  /// Starts again at the number box, keeping nothing from the last run.
  void reset() {
    _cancelTicker();
    _stage = PhoneVerificationStage.entering;
    _pending = null;
    _confirmed = null;
    _sending = false;
    _confirming = false;
    _error = null;
    _expiresIn = 0;
    _resendIn = 0;
    notifyListeners();
  }

  /// Back to the number box from the code box, so it can be retyped.
  void changeNumber() {
    _cancelTicker();
    _stage = PhoneVerificationStage.entering;
    _error = null;
    _expiresIn = 0;
    _resendIn = 0;
    notifyListeners();
  }

  /// Asks the server to send a code to [e164].
  ///
  /// Returns whether it went. False leaves [error] set with the server's own
  /// sentence, and on a cooldown the countdown is already running.
  Future<bool> sendCode(String e164) async {
    if (_sending) return false;

    final number = PhoneNumber.normalise(e164);
    if (number.length < 8) {
      _error = 'Enter a valid phone number.';
      notifyListeners();
      return false;
    }

    // Already on the account and already proved. Refused here rather than
    // sending an SMS for a number that would change nothing.
    final existing = _numbers.where((p) => p.e164 == number);
    if (existing.isNotEmpty && existing.first.verified) {
      _error = 'That number is already verified on your account.';
      notifyListeners();
      return false;
    }

    _sending = true;
    _error = null;
    notifyListeners();

    try {
      await _phones.sendCode(number);
      _pending = number;
      _stage = PhoneVerificationStage.confirming;
      _startTimers(expiry: _defaultExpiry.inSeconds, resend: _defaultCooldown);
      return true;
    } on OtpCooldown catch (e) {
      _error = e.message;
      if (e.reason == PhoneOtpRefusal.cooldown) {
        // The server's wait, not one this app chose.
        _pending = number;
        _stage = PhoneVerificationStage.confirming;
        _startTimers(
          expiry: _defaultExpiry.inSeconds,
          resend: e.seconds ?? _defaultCooldown,
        );
      }
      return false;
    } on ApiError catch (e) {
      _error = e.message;
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Asks again for a code, if the server is willing yet.
  Future<bool> resend() async {
    final number = _pending;
    if (number == null || !canResend) return false;

    _sending = true;
    _error = null;
    notifyListeners();
    try {
      await _phones.sendCode(number);
      _startTimers(expiry: _defaultExpiry.inSeconds, resend: _defaultCooldown);
      return true;
    } on OtpCooldown catch (e) {
      _error = e.message;
      if (e.reason == PhoneOtpRefusal.cooldown) {
        _startTimers(expiry: _expiresIn, resend: e.seconds ?? _defaultCooldown);
      }
      return false;
    } on ApiError catch (e) {
      _error = e.message;
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Hands the typed code to the server.
  ///
  /// Only the server's yes moves this to [PhoneVerificationStage.done].
  Future<bool> confirm(String code) async {
    final number = _pending;
    if (number == null || _confirming) return false;

    if (code.trim().length < 4) {
      _error = 'Enter the code from the message.';
      notifyListeners();
      return false;
    }

    _confirming = true;
    _error = null;
    notifyListeners();

    try {
      final verified = await _phones.confirmCode(e164: number, code: code);
      _confirmed = verified;
      _stage = PhoneVerificationStage.done;
      _cancelTicker();
      // The account's list is stale the moment this lands.
      _numbers = [
        verified,
        ..._numbers.where((p) => p.e164 != verified.e164),
      ];
      return true;
    } on OtpCooldown catch (e) {
      _error = e.message;
      return false;
    } on ApiError catch (e) {
      _error = e.message;
      return false;
    } finally {
      _confirming = false;
      notifyListeners();
    }
  }

  // ── The clocks ────────────────────────────────────────────────────────────

  void _startTimers({required int expiry, required int resend}) {
    _expiresIn = expiry;
    _resendIn = resend;
    _cancelTicker();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_expiresIn > 0) _expiresIn--;
      if (_resendIn > 0) _resendIn--;
      if (_expiresIn == 0 && _resendIn == 0) _cancelTicker();
      notifyListeners();
    });
  }

  /// Stops the countdown without touching what the flow knows.
  ///
  /// For a screen being closed. This is a singleton, so its own [dispose] is
  /// never called: a flow left part-way through kept a one-second timer
  /// running for the life of the app, notifying listeners that were no longer
  /// on screen. Narrower than [reset] on purpose -- closing the screen is not
  /// the same as abandoning the attempt, and reopening calls [reset] anyway.
  void stopClocks() => _cancelTicker();

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _cancelTicker();
    super.dispose();
  }

  @visibleForTesting
  void resetForTest() {
    _cancelTicker();
    _numbers = const [];
    _loading = false;
    _loadError = null;
    _stage = PhoneVerificationStage.entering;
    _pending = null;
    _confirmed = null;
    _sending = false;
    _confirming = false;
    _error = null;
    _expiresIn = 0;
    _resendIn = 0;
    _phones = PhoneRepository.instance;
  }
}

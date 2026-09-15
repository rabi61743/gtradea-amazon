import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/auth_store.dart';
import 'profile_store.dart';

/// Changing the address the account signs in with, and proving it.
///
/// The same shape as the phone flow, and for the same reason: an address
/// nobody proved is an address an order confirmation goes to somebody else at.
///
/// **What the server actually does.** GoTrue offers two ways and this uses the
/// one that matches the reference:
///
///   * `POST /otp` with `{email}` sends a six-digit code, and
///   * `POST /verify` with `{type: 'email_change', email, token}` checks it.
///
/// The older way -- `PUT /user {email}`, which mails a *link* -- is what
/// [ProfileStore.changeEmail] already does and is left alone. Whether a given
/// GoTrue project sends a code or a link is its own configuration, so a refusal
/// here is reported in the server's words rather than guessed at.
///
/// GoTrue holds **one** email per user, and it is the sign-in identity. There
/// is no list to keep and no primary to choose: a second address would be a
/// second account. That is why this flow changes an address rather than adding
/// one.
class EmailVerificationStore extends ChangeNotifier {
  EmailVerificationStore._();

  static final EmailVerificationStore instance = EmailVerificationStore._();

  AuthRepository _auth = AuthRepository.instance;

  @visibleForTesting
  set authRepositoryForTest(AuthRepository repo) => _auth = repo;

  /// Walks the flow without a mail round-trip, for looking at the screens.
  ///
  /// **A verification bypass, and it cannot ship.** [active] ands it with
  /// [kDebugMode], a compile-time constant that is `false` in release, so the
  /// branch is removed by the compiler rather than skipped at runtime. The
  /// screens draw a banner whenever it is on.
  ///
  /// It does **not** change the address on the account: GoTrue owns the
  /// sign-in identity, and writing one there without a real confirmation would
  /// be a way to take over an account. The demo shows the screens and stops.
  static bool demo = true;

  static bool get demoActive => kDebugMode && demo;

  /// How long the code is shown as good for. GoTrue's default; the server is
  /// what actually expires it.
  static const _expiry = Duration(minutes: 5);
  static const _cooldown = 60;

  _Stage _stage = _Stage.entering;
  String? _pending;
  String? _confirmed;

  bool _sending = false;
  bool _confirming = false;
  String? _error;

  Timer? _ticker;
  int _expiresIn = 0;
  int _resendIn = 0;

  bool get entering => _stage == _Stage.entering;
  bool get confirming => _stage == _Stage.confirming;
  bool get done => _stage == _Stage.done;

  String? get pending => _pending;
  String? get confirmed => _confirmed;
  bool get sending => _sending;
  bool get checking => _confirming;
  String? get error => _error;
  int get expiresIn => _expiresIn;
  int get resendIn => _resendIn;
  bool get canResend => _resendIn == 0 && !_sending;

  static String clock(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Loose on purpose. A strict RFC 5322 pattern rejects addresses that work,
  /// and the server is what actually decides -- this catches the typo.
  static final _shape = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');

  void reset() {
    _cancel();
    _stage = _Stage.entering;
    _pending = null;
    _confirmed = null;
    _sending = false;
    _confirming = false;
    _error = null;
    _expiresIn = 0;
    _resendIn = 0;
    notifyListeners();
  }

  void changeAddress() {
    _cancel();
    _stage = _Stage.entering;
    _error = null;
    _expiresIn = 0;
    _resendIn = 0;
    notifyListeners();
  }

  /// Asks the server to send a code to [address].
  Future<bool> send(String address) async {
    if (_sending) return false;
    final email = address.trim();

    if (!_shape.hasMatch(email)) {
      _error = 'Enter a valid email address.';
      notifyListeners();
      return false;
    }
    final current = AuthStore.instance.account?.email;
    if (current != null && current.toLowerCase() == email.toLowerCase()) {
      _error = 'That is already your email address.';
      notifyListeners();
      return false;
    }

    _sending = true;
    _error = null;
    notifyListeners();

    try {
      if (!demoActive) {
        await _auth.sendEmailOtp(email);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      _pending = email;
      _stage = _Stage.confirming;
      _start(expiry: _expiry.inSeconds, resend: _cooldown);
      return true;
    } on ApiError catch (e) {
      _error = e.message;
      if (e.statusCode == 429) {
        _pending = email;
        _stage = _Stage.confirming;
        _start(expiry: _expiry.inSeconds, resend: _secondsIn(e.message));
      }
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<bool> resend() async {
    final email = _pending;
    if (email == null || !canResend) return false;

    _sending = true;
    _error = null;
    notifyListeners();
    try {
      if (!demoActive) {
        await _auth.sendEmailOtp(email);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      _start(expiry: _expiry.inSeconds, resend: _cooldown);
      return true;
    } on ApiError catch (e) {
      _error = e.message;
      if (e.statusCode == 429) {
        _start(expiry: _expiresIn, resend: _secondsIn(e.message));
      }
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Hands the typed code to the server. Only its yes finishes this.
  Future<bool> confirm(String code) async {
    final email = _pending;
    if (email == null || _confirming) return false;
    if (code.trim().length != 6) {
      _error = 'Enter the 6-digit code.';
      notifyListeners();
      return false;
    }

    _confirming = true;
    _error = null;
    notifyListeners();

    try {
      if (demoActive) {
        // Deliberately does not touch the account: GoTrue owns the sign-in
        // identity, and writing an address there unproved would be a way to
        // take an account over.
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } else {
        await _auth.verifyEmailOtp(email: email, token: code);
        await AuthStore.instance.reloadFromSession();
        await ProfileStore.instance.load(force: true);
      }
      _confirmed = email;
      _stage = _Stage.done;
      _cancel();
      return true;
    } on ApiError catch (e) {
      _error = e.message;
      return false;
    } finally {
      _confirming = false;
      notifyListeners();
    }
  }

  static int _secondsIn(String message) {
    final match = RegExp(r'(\d+)\s*second').firstMatch(message.toLowerCase());
    return int.tryParse(match?.group(1) ?? '') ?? _cooldown;
  }

  void _start({required int expiry, required int resend}) {
    _expiresIn = expiry;
    _resendIn = resend;
    _cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_expiresIn > 0) _expiresIn--;
      if (_resendIn > 0) _resendIn--;
      if (_expiresIn == 0 && _resendIn == 0) _cancel();
      notifyListeners();
    });
  }

  /// Stops the countdown without touching what the flow knows.
  ///
  /// For a screen being closed. This is a singleton, so its own [dispose] is
  /// never called, and a flow left part-way through kept a one-second timer
  /// running for the life of the app. Narrower than [reset] on purpose:
  /// reopening calls that anyway.
  void stopClocks() => _cancel();

  void _cancel() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @visibleForTesting
  void resetForTest() {
    _cancel();
    _stage = _Stage.entering;
    _pending = null;
    _confirmed = null;
    _sending = false;
    _confirming = false;
    _error = null;
    _expiresIn = 0;
    _resendIn = 0;
    _auth = AuthRepository.instance;
  }
}

enum _Stage { entering, confirming, done }

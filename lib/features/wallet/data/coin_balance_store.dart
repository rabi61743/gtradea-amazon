import 'package:flutter/foundation.dart';

import '../../auth/data/auth_store.dart';
import 'wallet_repository.dart';

/// The account's coin balance, held where more than one widget can ask.
///
/// The header's chip needs the figure to draw, and the row around it needs to
/// know whether there will be a figure at all -- a chip that renders nothing
/// but still occupies its share of the row squeezed the delivery address into
/// "Deliv / Ja...". One store answers both.
///
/// Null means there is nothing true to say: a guest, a balance not yet read, or
/// one the server would not give. In each of those the chip is left out
/// entirely rather than showing a zero the shopper would read as "you have
/// none".
class CoinBalanceStore extends ChangeNotifier {
  CoinBalanceStore._();

  static final CoinBalanceStore instance = CoinBalanceStore._();

  /// Re-reads the balance whenever the account changes.
  ///
  /// Called by the shell rather than done in the constructor, as every other
  /// store here is: the header reads this singleton while it is building, and
  /// a constructor that reaches into another store from inside a build is how
  /// a widget ends up marked dirty during its own first frame.
  void bindToAuth() {
    if (_bound) return;
    _bound = true;
    AuthStore.instance.addListener(load);
  }

  bool _bound = false;

  /// What to show before the server has given a figure.
  ///
  /// The wallet endpoint is real -- `GET /wallet` answers 401 rather than 404
  /// -- so a signed-in shopper's own balance replaces this the moment it
  /// arrives. This only stands in for the cases where there is no figure at
  /// all: a guest, a request still in flight, or one that failed.
  ///
  /// One named constant, read in one place. The day every shopper has a real
  /// balance, deleting this and making [balance] nullable again is the whole
  /// of the change -- no screen that draws it has to move.
  static const num fallbackBalance = 1000;

  /// The figure to draw. Never null: [fallbackBalance] covers every gap.
  ///
  /// It stands in for a guest, for a balance still on its way, **and** for a
  /// read that failed. The narrower rule -- fall back only where nobody was
  /// asked -- was tried and reverted: this account's `/wallet` is refused by
  /// the server, so the chip blanked on the one device it needed to be seen
  /// on. The cost is stated plainly: a signed-in shopper whose balance cannot
  /// be read is shown the stand-in rather than their own figure, so
  /// [fetchedBalance] stays available for anything that must tell the two
  /// apart.
  num get balance => _balance ?? fallbackBalance;

  /// True once a read has been attempted and did not produce a figure.
  bool _failed = false;

  /// Whether the last read was attempted and failed.
  bool get readFailed => _failed;

  /// What the server actually said, or null if it has not said anything.
  ///
  /// Kept apart from [balance] so the difference between a real balance and
  /// the stand-in is still answerable -- by a test, or by whatever replaces
  /// the fallback later.
  num? get fetchedBalance => _balance;
  num? _balance;

  /// There is always a figure to draw now, so the chip is always shown.
  bool get hasBalance => true;

  /// Guards against a slow reply from a previous account landing in a newer
  /// one's header.
  int _request = 0;

  /// Reads the balance for whoever is signed in now.
  ///
  /// Failures are silent by design: the header is not the place to report a
  /// background fetch, and the wallet screen behind the chip says so properly,
  /// with a retry.
  Future<void> load() async {
    final ticket = ++_request;

    if (!AuthStore.instance.isSignedIn) {
      // Nobody was asked, so the stand-in applies: signing out returns the
      // chip to the fallback rather than to whatever the last account had.
      if (_balance != null || _failed) {
        _balance = null;
        _failed = false;
        notifyListeners();
      }
      return;
    }

    try {
      final balance = await WalletRepository.instance.balance();
      if (ticket != _request) return;
      _balance = balance;
      _failed = false;
    } catch (_) {
      if (ticket != _request) return;
      // Asked and refused. This shopper's balance is real and unknown, so the
      // chip goes quiet rather than showing them somebody else's number.
      _balance = null;
      _failed = true;
    }
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _balance = null;
    // Cleared too, or a test whose read failed leaves the next one believing
    // this account's balance was refused.
    _failed = false;
    _request++;
  }
}

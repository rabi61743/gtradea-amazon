import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/auth_store.dart';
import 'profile.dart';
import 'profile_repository.dart';

/// How an email change ended.
///
/// Two outcomes, because GoTrue has two and telling them apart is the whole
/// point: a project with confirmations on leaves the old address in place and
/// mails a link, and saying "email updated" there would be a lie the shopper
/// only discovers when they next try to sign in.
enum EmailChange {
  /// The address changed there and then.
  applied,

  /// A confirmation link went out. The address is unchanged until it is used.
  confirmationSent,
}

/// The signed-in customer's profile, shared across screens.
///
/// A [ChangeNotifier] over [ProfileRepository] and [AuthRepository], in the
/// same shape as every other store here. It exists so the account header and
/// the settings page cannot disagree about the name or the photograph: both
/// watch this, so a save is on screen everywhere the instant it lands.
///
/// Identity still belongs to [AuthStore]. This does not decide who is signed
/// in; it holds what the gateway knows *about* them.
class ProfileStore extends ChangeNotifier {
  ProfileStore._() {
    // One shopper's name and photograph must not survive into the next one's
    // session, and sign-out happens in more places than the account screen --
    // an expired refresh token clears the session on its own. Watching the
    // identity store catches all of them.
    AuthStore.instance.addListener(_onAuthChanged);
    _ownerId = AuthStore.instance.account?.id;
  }

  static final ProfileStore instance = ProfileStore._();

  /// Whose profile this is. A switch to another account changes it, and
  /// everything held for the last one goes.
  String? _ownerId;

  /// Bumped with [_ownerId], so a profile asked for as one account and
  /// answered after a switch is dropped rather than shown as the next one's.
  int _generation = 0;

  void _onAuthChanged() {
    final id = AuthStore.instance.account?.id;
    if (id == _ownerId) return;
    _ownerId = id;
    _generation++;
    if (_profile != null || _error != null || _loading || _saving) clear();
    // Another account now: its own name and photograph, not a blank header.
    if (id != null) load(force: true);
  }

  ProfileRepository _profiles = ProfileRepository.instance;
  AuthRepository _auth = AuthRepository.instance;

  @visibleForTesting
  set profileRepositoryForTest(ProfileRepository repo) => _profiles = repo;

  @visibleForTesting
  set authRepositoryForTest(AuthRepository repo) => _auth = repo;

  Profile? _profile;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  Profile? get profile => _profile;

  /// True while the first read is in flight. The page shows the fields it
  /// already knows from the session rather than a spinner, so this only drives
  /// the quiet loading line.
  bool get loading => _loading;

  /// True while any write is in flight. Every submit button reads it, which is
  /// what stops a second tap starting a second request.
  bool get saving => _saving;

  /// Why the last load failed, or null. Save failures are reported to the
  /// caller instead -- they belong beside the field that caused them.
  String? get loadError => _error;

  /// The picture to draw for this account, or null for the initial.
  ///
  /// Falls back to whatever the identity provider supplied, so an account that
  /// signed in with Google has a photograph before it has a profile row.
  String? get avatarUrl {
    final own = _profile?.avatarUrl;
    if (own != null && own.isNotEmpty) return own;
    return AuthStore.instance.account?.avatarUrl;
  }

  /// The name to show, preferring the gateway's row over the session's copy.
  String? get displayName {
    final name = _profile?.fullName;
    if (name != null && name.isNotEmpty) return name;
    return AuthStore.instance.account?.displayName;
  }

  /// Reads the profile. Safe to call from `initState` on every screen that
  /// wants it -- a second call while one is in flight is dropped.
  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_profile != null && !force) return;
    if (!AuthStore.instance.isSignedIn) return;

    _loading = true;
    _error = null;
    notifyListeners();

    final generation = _generation;
    try {
      final profile = await _profiles.fetch();
      if (generation != _generation) return;
      _profile = profile;
      // A photo changed on the website, or before this device kept the
      // sign-in copy in step, still reaches the list of accounts here.
      final photo = profile.avatarUrl;
      if (photo != null && photo.isNotEmpty) {
        AuthStore.instance.adoptProfilePhoto(photo).ignore();
      }
    } on ApiError catch (e) {
      if (generation != _generation) return;
      _error = e.message;
    } finally {
      // After a switch the new account's own load owns these flags.
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Saves the name.
  ///
  /// Throws [ApiError] with the server's own words, which the page shows. On a
  /// failure nothing local changes -- [_profile] is only replaced by the row
  /// the server sends back, so a rejected save leaves the old values on screen
  /// rather than a hopeful copy of what was typed.
  /// Saves the name and the contact number together.
  ///
  /// The phone is here rather than on each address because it belongs to the
  /// person, not the doorstep -- and because the new-address form deliberately
  /// no longer asks for one. **An order without a phone is refused by the
  /// server** ("Phone is required"), so with no field anywhere this account
  /// could not check out at all. Checkout reads it from here.
  Future<void> saveName(String name, {String? phone}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ApiError(
        statusCode: null,
        message: 'Enter your name.',
        local: true,
      );
    }

    final parts = Profile.splitName(trimmed);
    await _write(
      () => _profiles.update(
        firstName: parts.first,
        lastName: parts.last,
        // Null leaves it alone; the repository only sends what it is given.
        phone: phone?.trim(),
      ),
    );

    // GoTrue keeps its own copy in user_metadata, and it is what the app reads
    // before the profile row arrives. Best effort: the profile row is the
    // source of truth and has already been written, so a failure here is worth
    // neither an error message nor rolling the save back.
    try {
      await _auth.updateUser(
        data: {'first_name': parts.first, 'last_name': parts.last},
      );
      await AuthStore.instance.reloadFromSession();
    } on ApiError {
      // Deliberately swallowed. See above.
    }
  }

  /// Files a contact number on the account, changing nothing else.
  ///
  /// [saveName] is the account screen's door, where the shopper is editing
  /// their name anyway. Checkout has only a number, and sending a name it was
  /// never given -- or refusing the save because the account has no name on it
  /// yet -- would be writing over one field to store another.
  Future<void> savePhone(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    await _write(() => _profiles.update(phone: trimmed));
  }

  /// Uploads a new profile photo and stores it on the profile.
  ///
  /// Two requests, and the order matters: nothing is written to the profile
  /// until the picture is actually stored, so a failed upload cannot leave the
  /// row pointing at an address that holds nothing.
  Future<void> savePhoto(File file) async {
    // Whose photo this is. A switch while the upload runs must not carry this
    // picture into the next account's sign-in record.
    final owner = AuthStore.instance.account?.id;
    String? stored;
    await _write(() async {
      final url = await _profiles.uploadAvatar(file);
      stored = url;
      return _profiles.update(avatarUrl: url);
    });
    final url = stored;
    if (url != null && AuthStore.instance.account?.id == owner) {
      await _syncSignInPhoto(url);
    }
  }

  /// Copies the profile's photograph to the account's sign-in record.
  ///
  /// GoTrue keeps its own `avatar_url` in user_metadata, as it keeps the
  /// name, and that copy is what the list of accounts on this device draws --
  /// for every saved account, not only the active one. Left alone, a new photo
  /// showed in the header while the account list kept the old one.
  ///
  /// Best effort, like the name: the profile row is the source of truth and
  /// is already written. When GoTrue cannot be told, this device's copy is
  /// still brought up to date so the list is right here.
  Future<void> _syncSignInPhoto(String url) async {
    try {
      await _auth.updateUser(data: {'avatar_url': url});
      await AuthStore.instance.reloadFromSession();
    } on ApiError {
      await AuthStore.instance.adoptProfilePhoto(url);
    }
  }

  /// Changes the sign-in address through GoTrue.
  ///
  /// Returns which of the two things happened. The current password is checked
  /// first, so the address on an unlocked phone cannot be moved to an attacker's
  /// without knowing it.
  Future<EmailChange> changeEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    final account = AuthStore.instance.account;
    if (account == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Sign in again to change your email.',
      );
    }

    _saving = true;
    notifyListeners();
    try {
      await _auth.verifyPassword(
        email: account.email,
        password: currentPassword,
      );
      final user = await _auth.updateUser(email: newEmail);
      await AuthStore.instance.reloadFromSession();

      // GoTrue parks the address in `new_email` until the link is followed and
      // leaves `email` alone. Anything else means confirmations are off and the
      // change is already live.
      final pending = user['new_email'];
      final applied =
          (user['email'] as String?)?.toLowerCase() ==
          newEmail.trim().toLowerCase();
      if (applied && (pending == null || pending == '')) {
        // The gateway keeps its own copy of the address on the profile row.
        await load(force: true);
        return EmailChange.applied;
      }
      return EmailChange.confirmationSent;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Changes the password through GoTrue.
  ///
  /// The current one is verified first. `PUT /user` does not require it, which
  /// means without this step a found phone is a stolen account.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final account = AuthStore.instance.account;
    if (account == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Sign in again to change your password.',
      );
    }

    _saving = true;
    notifyListeners();
    try {
      await _auth.verifyPassword(
        email: account.email,
        password: currentPassword,
      );
      await _auth.updateUser(password: newPassword);
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Runs a write with the in-flight flag set, and adopts whatever the server
  /// returns. Failures propagate untouched and leave [_profile] alone.
  Future<void> _write(Future<Profile> Function() call) async {
    if (_saving) return;
    _saving = true;
    notifyListeners();
    try {
      final generation = _generation;
      final profile = await call();
      // Saved to the account it was made in; shown only if that is still the
      // one on screen.
      if (generation == _generation) _profile = profile;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Dropped on sign-out. One shopper's photograph must not survive into the
  /// next one's session.
  void clear() {
    _profile = null;
    _loading = false;
    _saving = false;
    _error = null;
    notifyListeners();
  }

  @visibleForTesting
  void seedForTest(Profile? profile) {
    _profile = profile;
    _loading = false;
    _saving = false;
    _error = null;
  }

  @visibleForTesting
  void resetForTest() {
    _profile = null;
    _loading = false;
    _saving = false;
    _error = null;
    _profiles = ProfileRepository.instance;
    _auth = AuthRepository.instance;
  }
}

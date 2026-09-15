import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../address/data/address_store.dart';
import '../../address/presentation/address_list_screen.dart';
import '../../auth/data/auth_store.dart';
import '../../legal/presentation/legal_page_screen.dart';
import '../../notifications/presentation/notification_settings_screen.dart';
import '../../search/data/image_source_picker.dart';
import '../../security/presentation/login_activity_screen.dart';
import '../../settings/presentation/language_screen.dart';
import '../../settings/presentation/theme_screen.dart';
import '../data/profile_store.dart';
import 'email_verification_screen.dart';
import 'phone_verification_screen.dart';
import 'photo_source_sheet.dart';

/// View and change the account: photograph, name, contact details, password.
///
/// Laid out to the supplied reference: a header with the page's own title, a
/// card carrying the photograph and the name, then Personal Information and
/// Account Security as icon-led groups.
///
/// Each field is edited on its own, in a sheet, and saves on its own. A name
/// and a password have nothing to do with each other, they fail for different
/// reasons, and one "Save everything" button would make a rejected password
/// look like a rejected name.
///
/// **What the reference shows and this does not**, by decision:
///
///   * "Verified" badges and "Member since" -- left out on request.
///   * "Profile Preferences" -- left out on request.
///
/// **Two-factor authentication** is on the page, as the reference has it, but
/// states "Not enabled" and says plainly that it is not available yet. There
/// is no 2FA anywhere in this codebase or on the server, so the row must never
/// look like it turned anything on.
///
/// "Profile complete" is *derived* here from what the profile actually holds
/// rather than read from a field the server never sent. Location is the
/// default delivery address, and is edited where addresses are edited.
///
/// The page is set in Nunito Sans (see [_Type]) to match the reference. That
/// is deliberate and local to this page; the rest of the app keeps its font.
class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _store = ProfileStore.instance;
  final _addresses = AddressStore.instance;

  /// The picked file, held until it is saved, so the shopper sees the actual
  /// photograph in place before anything is uploaded and can back out of it.
  File? _pendingPhoto;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _addresses.addListener(_onStore);
    _store.load();
    // The Location row reads the default delivery address. Loaded here rather
    // than assumed, so it never says "Not set" to someone with saved addresses.
    _addresses.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _addresses.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  void _say(String message, {bool bad = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: bad ? theme.colorScheme.error : null,
        ),
      );
  }

  // ── Photo ─────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final source = await PhotoSourceSheet.show(context);
    if (source == null || !mounted) return;

    final outcome = await ImageSourcePicker.instance.pick(source);
    if (!mounted) return;

    switch (outcome) {
      case PhotoTaken(:final file):
        setState(() => _pendingPhoto = file);
        await _savePhoto();
      case PhotoCancelled():
        break;
      case PhotoPermissionDenied(source: final denied):
        _say(
          denied == PhotoSource.camera
              ? 'Allow camera access to take a photo.'
              : 'Allow photo access to choose a picture.',
          bad: true,
        );
      case PhotoNoCamera():
        _say('This device has no camera.', bad: true);
      case PhotoFailed(:final reason):
        _say(reason, bad: true);
    }
  }

  Future<void> _savePhoto() async {
    final file = _pendingPhoto;
    if (file == null || _store.saving) return;
    try {
      await _store.savePhoto(file);
      if (!mounted) return;
      setState(() => _pendingPhoto = null);
      _say('Profile photo updated');
    } on ApiError catch (e) {
      if (!mounted) return;
      // The preview goes with the failure: leaving it would show a photograph
      // that is not on the account.
      setState(() => _pendingPhoto = null);
      _say(e.message, bad: true);
    }
  }

  // ── Fields ────────────────────────────────────────────────────────────────

  Future<void> _editName() async {
    final value = await _EditSheet.show(
      context,
      title: 'Full Name',
      label: 'Full name',
      icon: Icons.person_outline,
      initial: _store.profile?.fullName ?? _store.displayName ?? '',
      keyboard: TextInputType.name,
      capitalisation: TextCapitalization.words,
      validate: (v) => v.trim().isEmpty ? 'Enter your name.' : null,
    );
    if (value == null) return;
    try {
      await _store.saveName(value);
      _say('Name updated');
    } on ApiError catch (e) {
      _say(e.message, bad: true);
    }
  }

  /// Opens the verification flow rather than a text box.
  ///
  /// A phone number is the one detail here that has to be *proved* rather than
  /// simply typed: it is what a courier rings and what an order is refused
  /// without. Editing it in place would write whatever was entered, including a
  /// number belonging to somebody else. The flow sends a real code and only
  /// stores the number once the server confirms it.
  Future<void> _editPhone() async {
    final changed = await PhoneVerificationScreen.open(context);
    if (!changed || !mounted) return;
    // The flow refreshes the profile itself; this is the word to the shopper.
    _say('Phone number verified and updated');
  }

  /// Opens the verification flow rather than a text box, for the same reason
  /// the phone row does: the address is the account's sign-in identity, and one
  /// that nobody proved is one somebody else's confirmations go to.
  Future<void> _editEmail(String current) async {
    final changed = await EmailVerificationScreen.open(context);
    if (!changed || !mounted) return;
    _say('Email address verified and updated');
  }

  Future<void> _changePassword() async {
    await _PasswordSheet.show(context, onDone: () => _say('Password updated'));
  }

  void _openLoginActivity() => _push(const LoginActivityScreen());

  /// Location is the default delivery address, so it is changed in the address
  /// book. A second place to type a city would be a second answer to where a
  /// parcel goes.
  void _openLocation() => _push(const AddressListScreen());

  /// Says so rather than pretending. There is no 2FA on the server, and a
  /// setting that appears to enable something that is not there is a security
  /// promise the app would be breaking.
  void _openTwoFactor() {
    _say('Two-factor authentication isn’t available yet.');
  }

  void _openPrivacy() =>
      _push(const LegalPageScreen(slug: 'privacy', title: 'Privacy policy'));

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final account = AuthStore.instance.account;

    if (account == null) {
      // Reachable only by getting here and then signing out -- the account
      // screen does not offer the row to a guest.
      return Scaffold(
        appBar: AppBar(title: const Text('Profile Settings')),
        body: const Center(child: Text('Sign in to manage your profile.')),
      );
    }

    final profile = _store.profile;
    final name = _store.displayName ?? account.displayName;
    final email = profile?.email.isNotEmpty == true
        ? profile!.email
        : account.email;
    final phone = profile?.phone;
    final home = _addresses.defaultAddress;
    final location = home == null
        ? null
        : [home.city, home.province]
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .join(', ');

    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      // The reference's ground is a cool near-white. The app's page wash is
      // Premium Ivory, which turned every tinted disc on this page grey, so the
      // ground here is the brand teal at 3% over white instead -- derived, not a
      // new colour.
      backgroundColor: Color.alphaBlend(
        primary.withValues(alpha: 0.03),
        Colors.white,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _store.load(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: _PageFrame.padding(context),
            children: [
              // The page's width, by screen size -- see [_PageFrame]: about
              // 97% on a phone, a centred column on a tablet or desktop.
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _PageFrame.maxWidth(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Header(),
                      const SizedBox(height: 12),

                      if (_store.loadError != null) ...[
                        _LoadNotice(
                          message: _store.loadError!,
                          onRetry: () => _store.load(force: true),
                        ),
                        const SizedBox(height: 14),
                      ],

                      _ProfileCard(
                        name: name,
                        pending: _pendingPhoto,
                        photo: _store.avatarUrl,
                        complete: _isComplete(name, phone, _store.avatarUrl),
                        busy: _store.saving,
                        onEditName: _editName,
                        onChangePhoto: _pickPhoto,
                      ),
                      const SizedBox(height: 20),

                      _GroupHeading(
                        icon: Icons.person_outline,
                        title: 'Personal Information',
                        subtitle:
                            'Your basic details used for communication and '
                            'verification.',
                      ),
                      const SizedBox(height: 12),
                      _Card(
                        children: [
                          _FieldRow(
                            icon: Icons.person_outline,
                            label: 'Full Name',
                            value: name,
                            onEdit: _editName,
                          ),
                          _FieldRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone Number',
                            value: phone,
                            empty: 'Not added',
                            onEdit: _editPhone,
                          ),
                          _FieldRow(
                            icon: Icons.mail_outline,
                            label: 'Email Address',
                            value: email,
                            onEdit: () => _editEmail(email),
                          ),
                          _FieldRow(
                            icon: Icons.location_on_outlined,
                            label: 'Location',
                            optional: true,
                            value: location,
                            onEdit: _openLocation,
                            last: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _GroupHeading(
                        icon: Icons.shield_outlined,
                        title: 'Account Security',
                        subtitle: 'Keep your account safe and secure.',
                      ),
                      const SizedBox(height: 12),
                      _Card(
                        children: [
                          _ActionRow(
                            icon: Icons.lock_outline,
                            title: 'Change Password',
                            subtitle:
                                'Update your password regularly for better '
                                'security.',
                            onTap: _changePassword,
                          ),
                          _ActionRow(
                            icon: Icons.shield_outlined,
                            title: 'Two-Factor Authentication (2FA)',
                            subtitle: 'Add extra protection to your account.',
                            status: 'Not enabled',
                            onTap: _openTwoFactor,
                          ),
                          _ActionRow(
                            icon: Icons.fingerprint,
                            title: 'Login Activity',
                            subtitle: 'View devices and recent logins.',
                            onTap: _openLoginActivity,
                            last: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _SafetyNote(onTap: _openPrivacy),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Derived here, not read from the server: the profile row carries no
  /// "complete" flag, and inventing one would be stating something about the
  /// account that nothing checked.
  static bool _isComplete(String name, String? phone, String? photo) =>
      name.trim().isNotEmpty &&
      (phone?.trim().isNotEmpty ?? false) &&
      (photo?.isNotEmpty ?? false);
}

/// This page's type scale, set in Nunito Sans to match the reference.
///
/// The ratios between ranks are taken from the reference image; the absolute
/// sizes are fitted to a phone, with a floor of 12 so supporting text stays
/// readable at arm's length. Gathered here so the hierarchy is one decision.
///
/// Nunito Sans ships as a single variable font (see `pubspec.yaml`), so each
/// weight is selected with a `wght` [FontVariation] as well as [FontWeight] --
/// the variation is what actually moves the glyphs, the weight keeps the
/// semantics for accessibility and for any fallback font.
///
/// Colour and the reader's text scaling still come from the theme. Only the
/// family is local to this page; the rest of the app keeps its own.
class _Type {
  const _Type._();

  static const family = 'NunitoSans';

  static TextStyle? _set(
    TextStyle? base,
    double size,
    FontWeight weight, {
    double height = 1.25,
    Color? color,
  }) => base?.copyWith(
    fontFamily: family,
    fontSize: size,
    height: height,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
  );

  /// "Profile Settings". The largest thing here, and the only thing at this rank.
  static TextStyle? pageTitle(ThemeData t) =>
      _set(t.textTheme.titleLarge, 24, FontWeight.w700, height: 1.15);

  /// "Manage your profile information".
  static TextStyle? pageNote(ThemeData t) => _set(
    t.textTheme.bodyMedium,
    14,
    FontWeight.w400,
    height: 1.3,
    color: t.colorScheme.onSurfaceVariant,
  );

  /// The shopper's name on the card.
  static TextStyle? cardName(ThemeData t) =>
      _set(t.textTheme.titleMedium, 20, FontWeight.w700, height: 1.2);

  /// A section's name: Personal Information, Account Security.
  static TextStyle? groupTitle(ThemeData t) =>
      _set(t.textTheme.titleSmall, 17, FontWeight.w700, height: 1.2);

  /// The line under a section's name.
  static TextStyle? groupNote(ThemeData t) => _set(
    t.textTheme.bodySmall,
    13,
    FontWeight.w400,
    height: 1.3,
    color: t.colorScheme.onSurfaceVariant,
  );

  /// What a row is about -- "Full Name", "Phone Number".
  static TextStyle? rowLabel(ThemeData t) => _set(
    t.textTheme.bodySmall,
    13,
    FontWeight.w400,
    height: 1.2,
    color: t.colorScheme.onSurfaceVariant,
  );

  /// What it says. Regular weight, as the reference sets it: the size and the
  /// darker ink carry it, not boldness.
  static TextStyle? rowValue(ThemeData t) =>
      _set(t.textTheme.bodyMedium, 15, FontWeight.w400);

  /// A row that opens something rather than holding a value.
  static TextStyle? rowTitle(ThemeData t) =>
      _set(t.textTheme.bodyMedium, 14.5, FontWeight.w600, height: 1.2);

  /// The line under such a row.
  static TextStyle? rowNote(ThemeData t) => _set(
    t.textTheme.bodySmall,
    12,
    FontWeight.w400,
    height: 1.3,
    color: t.colorScheme.onSurfaceVariant,
  );

  /// Pills, chips and small buttons.
  static TextStyle? control(ThemeData t) =>
      _set(t.textTheme.labelLarge, 13, FontWeight.w600, height: 1.1);

  /// The Change Photo button.
  static TextStyle? button(ThemeData t) =>
      _set(t.textTheme.labelLarge, 14, FontWeight.w600, height: 1.1);

  /// A sheet's own heading.
  static TextStyle? sheetTitle(ThemeData t) =>
      _set(t.textTheme.titleSmall, 17, FontWeight.w700, height: 1.2);
}

/// Where the header's gear leads. The settings that sit beside a profile, each
/// an existing screen -- the gear is a shortcut, not a new destination.
enum _SettingsLink { theme, language, notifications }

/// The page's own title, the back arrow beside it, and the gear opposite.
///
/// Not an [AppBar]: the reference puts the title and its line of explanation in
/// the body, above a card that runs to the page margin.
class _Header extends StatelessWidget {
  const _Header();

  void _open(BuildContext context, _SettingsLink link) {
    final Widget screen = switch (link) {
      _SettingsLink.theme => const ThemeScreen(),
      _SettingsLink.language => const LanguageScreen(),
      _SettingsLink.notifications => const NotificationSettingsScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 24),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Profile Settings', style: _Type.pageTitle(theme)),
                const SizedBox(height: 3),
                Text(
                  'Manage your profile information',
                  style: _Type.pageNote(theme),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // The reference's round gear, top right.
          PopupMenuButton<_SettingsLink>(
            tooltip: 'Settings',
            onSelected: (link) => _open(context, link),
            position: PopupMenuPosition.under,
            itemBuilder: (_) => [
              _menuItem(_SettingsLink.theme, Icons.contrast, 'Theme', theme),
              _menuItem(
                _SettingsLink.language,
                Icons.translate,
                'Language',
                theme,
              ),
              _menuItem(
                _SettingsLink.notifications,
                Icons.notifications_none,
                'Notifications',
                theme,
              ),
            ],
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.08),
              ),
              child: Icon(Icons.settings_outlined, size: 22, color: tint),
            ),
          ),
        ],
      ),
    );
  }

  static PopupMenuItem<_SettingsLink> _menuItem(
    _SettingsLink value,
    IconData icon,
    String label,
    ThemeData theme,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(label, style: _Type.rowValue(theme)),
      ],
    ),
  );
}

/// The photograph, the name, and the way to change either.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.pending,
    required this.photo,
    required this.complete,
    required this.busy,
    required this.onEditName,
    required this.onChangePhoto,
  });

  final String name;
  final File? pending;
  final String? photo;
  final bool complete;
  final bool busy;
  final VoidCallback onEditName;
  final VoidCallback onChangePhoto;

  /// The width from which the card can hold the button beside it.
  ///
  /// The reference puts Change Photo opposite the avatar, and on its own 1024
  /// canvas that fits easily. This card gets about 375 points on a 406-point
  /// phone -- the page margin and the 620 reading cap take the rest -- and of
  /// that the avatar and its gutter want 82 and the button 150, leaving 143 for
  /// a name that needs about 160. So on a phone the reference's arrangement
  /// would ship an ellipsis where the shopper's name should be.
  ///
  /// 420, and measured rather than chosen. 330 was tried and shipped a
  /// 40-pixel overflow with the name clipped to "Pra…": the card gets about
  /// 375 on this phone, the avatar and its gutter take 82 and the button 150,
  /// which leaves 133 for a name needing about 160.
  ///
  /// So the phone stacks the button under the chip -- the arrangement that
  /// renders cleanly -- and only a tablet or a desktop window, which has the
  /// room the reference's own canvas had, puts it opposite the avatar.
  static const _sideBySideFrom = 420.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _sideBySideFrom;
        return _build(context, theme, tint, wide);
      },
    );
  }

  Widget _build(BuildContext context, ThemeData theme, Color tint, bool wide) {
    final ground = theme.colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: tint.withValues(alpha: 0.14)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint.withValues(alpha: 0.10),
            tint.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // The white ring the reference draws around the photograph.
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: ground,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _Avatar(
                  file: pending,
                  url: photo,
                  initial: _initialOf(name),
                  radius: 36,
                ),
              ),
              // The camera badge from the reference, and a real second way to
              // reach the picker rather than decoration.
              Positioned(
                right: -2,
                bottom: 0,
                child: Material(
                  color: tint,
                  shape: CircleBorder(side: BorderSide(color: ground, width: 2)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : onChangePhoto,
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 14,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Two lines before an ellipsis. On a 406-dp phone an
                    // ordinary two-part name does not fit beside the photo on
                    // one, and "Prabhakar Adhik..." hides the surname.
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _Type.cardName(theme),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined, size: 16, color: tint),
                      tooltip: 'Edit name',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: busy ? null : onEditName,
                    ),
                  ],
                ),
                if (complete) ...[
                  const SizedBox(height: 6),
                  const _Chip(
                    icon: Icons.check_circle,
                    label: 'Profile complete',
                    ink: AppColors.successInk,
                  ),
                ],
                // Only when the button is *not* beside the card, which is the
                // narrow case handled below.
                if (!wide) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _ChangePhotoButton(
                      busy: busy,
                      onTap: onChangePhoto,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // The reference puts this to the right of the card, opposite the
          // avatar. It only goes there when the row can hold it: at 406 points
          // with a long name there is not room for both, and a button squeezed
          // to two characters is worse than one on its own line.
          if (wide) ...[
            const SizedBox(width: 10),
            _ChangePhotoButton(busy: busy, onTap: onChangePhoto),
          ],
        ],
      ),
    );
  }

  static String _initialOf(String value) =>
      value.trim().isEmpty ? '?' : value.trim().characters.first.toUpperCase();
}

/// The pill that opens the photo picker.
///
/// Its own widget because the card draws it in one of two places depending on
/// the room it has, and a second copy of the styling would be a second thing to
/// keep right.
class _ChangePhotoButton extends StatelessWidget {
  const _ChangePhotoButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;
    return OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: tint,
        backgroundColor: theme.colorScheme.surface,
        side: BorderSide(color: tint.withValues(alpha: 0.35)),
        padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: tint),
                )
              : Icon(Icons.photo_camera_outlined, size: 18, color: tint),
          const SizedBox(width: 8),
          // Flexible, so a narrow phone or a large accessibility text size
          // shortens the label instead of striping the card with an overflow.
          Flexible(
            child: Text(
              'Change Photo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _Type.button(theme)?.copyWith(color: tint),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: tint),
        ],
      ),
    );
  }
}

/// A section's icon, name and line of explanation.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _IconDisc(icon: icon, size: 40, iconSize: 21, alpha: 0.10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _Type.groupTitle(theme)),
              const SizedBox(height: 2),
              Text(subtitle, style: _Type.groupNote(theme)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bordered card the rows of a group share.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        // The reference lifts its cards off the page by a breath, not a drop.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Column(children: children),
      ),
    );
  }
}

/// The tinted circle behind every icon on this page, as the reference draws
/// them. One widget so the rows, the headings and the banner cannot drift.
class _IconDisc extends StatelessWidget {
  const _IconDisc({
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
    this.alpha = 0.08,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final tint = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: alpha),
      ),
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

/// The hairline between rows, inset to start where the text starts so the
/// icon column reads as one, as in the reference.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.7),
    );
  }
}

/// One editable detail: what it is, what it says, and the way to change it.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onEdit,
    this.empty = 'Not set',
    this.optional = false,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String? value;

  /// What to say when the account has not filled this in. Shown held back, so
  /// an empty field reads as empty rather than as a value.
  final String empty;
  final VoidCallback onEdit;

  /// Adds the reference's muted "(Optional)" after the label.
  final bool optional;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = value != null && value!.trim().isNotEmpty;

    return Column(
      children: [
        InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
            child: Row(
              children: [
                _IconDisc(icon: icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: label,
                          children: [
                            if (optional)
                              TextSpan(
                                text: ' (Optional)',
                                style: _Type.rowNote(theme),
                              ),
                          ],
                        ),
                        style: _Type.rowLabel(theme),
                      ),
                      const SizedBox(height: 3),
                      // One line that shrinks only when it must. An email is
                      // one unbreakable token: an ellipsis hides the half that
                      // identifies the account ("pravakarcoding@gmai..."), and
                      // wrapping splits it mid-word.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          filled ? value! : empty,
                          maxLines: 1,
                          softWrap: false,
                          style: _Type.rowValue(theme)?.copyWith(
                            color: filled
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _EditPill(onTap: onEdit),
              ],
            ),
          ),
        ),
        if (!last) const _RowDivider(),
      ],
    );
  }
}

/// The reference's pill for changing a detail: pencil, "Change", chevron.
///
/// Tapping it does what the row always did -- the phone and email rows open
/// their own change-and-verify pages, the name opens its sheet, and Location
/// opens the address book. "Change" rather than "Edit": a contact method is
/// replaced and proved, not edited in place.
class _EditPill extends StatelessWidget {
  const _EditPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;
    return Material(
      color: tint.withValues(alpha: 0.05),
      shape: StadiumBorder(
        side: BorderSide(color: tint.withValues(alpha: 0.18)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, size: 15, color: tint),
              const SizedBox(width: 6),
              Text(
                'Change',
                style: _Type.control(theme)?.copyWith(color: tint),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 16, color: tint),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row that opens something rather than editing a value in place.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.status,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// A quiet grey state beside the chevron -- the reference's "Not enabled".
  final String? status;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget? chip() => status == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status!,
              style: _Type.control(theme)?.copyWith(color: muted),
            ),
          );

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The reference sets the status beside the chevron, and on its
                // wide canvas the title still fits on one line. On a phone the
                // chip would crush "Two-Factor Authentication (2FA)" into three
                // lines, so below this width it moves under the note instead.
                final beside = constraints.maxWidth >= _chipBesideFrom;
                final status = chip();
                return Row(
                  children: [
                    _IconDisc(icon: icon),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: _Type.rowTitle(theme)),
                          const SizedBox(height: 3),
                          Text(subtitle, style: _Type.rowNote(theme)),
                          if (status != null && !beside) ...[
                            const SizedBox(height: 7),
                            status,
                          ],
                        ],
                      ),
                    ),
                    if (status != null && beside) ...[
                      const SizedBox(width: 8),
                      status,
                    ],
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 22, color: muted),
                  ],
                );
              },
            ),
          ),
        ),
        if (!last) const _RowDivider(),
      ],
    );
  }

  /// Row width from which a status chip fits beside the chevron without
  /// forcing the title onto several lines. A tablet or desktop window.
  static const _chipBesideFrom = 460.0;
}

/// The reassurance at the foot of the reference. Tapping it opens the privacy
/// policy that backs the claim, rather than asking to be taken on trust.
class _SafetyNote extends StatelessWidget {
  const _SafetyNote({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;

    return Material(
      color: tint.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(color: tint.withValues(alpha: 0.14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your information is safe with us',
                      style: _Type.rowTitle(theme)?.copyWith(color: tint),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'We use industry-standard security to protect your data.',
                      style: _Type.rowNote(theme),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small tinted badge.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.ink});

  final IconData icon;
  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 12, 5),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: ink),
          const SizedBox(width: 6),
          Text(label, style: _Type.control(theme)?.copyWith(color: ink)),
        ],
      ),
    );
  }
}

/// The load failed. Shown rather than swallowed: the rows below are seeded from
/// the session and would otherwise look like the whole truth.
class _LoadNotice extends StatelessWidget {
  const _LoadNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// One field, edited on its own.
///
/// A sheet rather than a page: the thing being changed is a single line, and
/// the row it came from stays visible above it.
class _EditSheet extends StatefulWidget {
  const _EditSheet({
    required this.title,
    required this.label,
    required this.icon,
    required this.initial,
    required this.validate,
    this.helper,
    this.keyboard,
    this.capitalisation = TextCapitalization.none,
  });

  final String title;
  final String label;
  final IconData icon;
  final String initial;
  final String? helper;
  final TextInputType? keyboard;
  final TextCapitalization capitalisation;

  /// Returns the complaint, or null when the value will do. Local only: the
  /// server is what actually decides, and this catches the typo.
  final String? Function(String value) validate;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String label,
    required IconData icon,
    required String initial,
    required String? Function(String value) validate,
    String? helper,
    TextInputType? keyboard,
    TextCapitalization capitalisation = TextCapitalization.none,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditSheet(
        title: title,
        label: label,
        icon: icon,
        initial: initial,
        validate: validate,
        helper: helper,
        keyboard: keyboard,
        capitalisation: capitalisation,
      ),
    );
  }

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final complaint = widget.validate(_field.text);
    if (complaint != null) {
      setState(() => _error = complaint);
      return;
    }
    Navigator.of(context).pop(_field.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: widget.title,
      children: [
        TextField(
          controller: _field,
          autofocus: true,
          keyboardType: widget.keyboard,
          textCapitalization: widget.capitalisation,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helper,
            helperMaxLines: 2,
            prefixIcon: Icon(widget.icon),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          _ErrorLine(_error!),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Current, new, confirm.
class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.onDone});

  final VoidCallback onDone;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onDone,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PasswordSheet(onDone: onDone),
    );
  }

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  String? _error;

  /// GoTrue's own floor is 6. Asking for 8 is a choice this app can make and
  /// the server will accept.
  static const _minLength = 8;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (_next.text.length < _minLength) {
      setState(
        () => _error =
            'Use at least $_minLength characters for the new password.',
      );
      return;
    }
    if (_next.text == _current.text) {
      setState(() => _error = 'The new password must be different.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'The two new passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ProfileStore.instance.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      // Cleared the moment it succeeds: three password boxes left sitting
      // filled behind a "done" message is a credential on screen for no reason.
      _current.clear();
      _next.clear();
      _confirm.clear();
      Navigator.of(context).pop();
      widget.onDone();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Change Password',
      children: [
        _PasswordField(controller: _current, label: 'Current password'),
        const SizedBox(height: 10),
        _PasswordField(
          controller: _next,
          label: 'New password',
          helper: 'At least $_minLength characters.',
        ),
        const SizedBox(height: 10),
        _PasswordField(
          controller: _confirm,
          label: 'Confirm new password',
          onSubmitted: _submit,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          _ErrorLine(_error!),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy ? const _ButtonSpinner() : const Text('Update password'),
        ),
      ],
    );
  }
}

/// The frame every sheet on this page shares: a title, the keyboard inset, and
/// a width cap so a tablet does not stretch one field across the screen.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: _Type.sheetTitle(theme)),
                  const SizedBox(height: 12),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture: the pending file, else the stored URL, else the initial.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.file,
    required this.url,
    required this.initial,
    required this.radius,
  });

  final File? file;
  final String? url;
  final String initial;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primary,
      child: Text(
        initial,
        style: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (file != null) {
      return CircleAvatar(radius: radius, backgroundImage: FileImage(file!));
    }

    final address = url;
    if (address == null || address.isEmpty) return fallback;

    // Through the same cache every other remote picture in the app uses, and
    // falling back to the initial rather than to a broken-image glyph.
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: address,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

/// An obscured field with a reveal toggle.
///
/// The toggle matters: obscured boxes are where typos live, and someone who
/// cannot see what they typed retries by guessing.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.helper,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: widget.onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility),
          tooltip: _hidden ? 'Show' : 'Hide',
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

/// A validation or server message, beside the fields it is about rather than
/// in a snackbar that covers them.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

/// The in-flight state of a submit button, sized to the text it replaces so the
/// button does not resize when it starts working.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

/// How wide the page is, by the width of the screen it is on.
///
/// Measured against what used to render: a fixed 16-point margin and a 620 cap
/// left the column at 374 of 406 points on a phone (92%) -- a strip of unused
/// margin down both sides -- while a desktop window got a narrow 620 column.
///
///   * **Phone (< 600):** 1.5% margin each side, no cap -- about 97% width.
///   * **Tablet (600-1024):** 24-point margins, capped at 680 and centred.
///   * **Desktop (1024+):** 24-point margins, capped at 720 and centred --
///     balanced whitespace, never near full-screen.
abstract final class _PageFrame {
  static const tabletFrom = 600.0;
  static const desktopFrom = 1024.0;

  static double _width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static double side(BuildContext context) {
    final width = _width(context);
    return width < tabletFrom ? width * 0.015 : 24;
  }

  static double maxWidth(BuildContext context) {
    final width = _width(context);
    if (width < tabletFrom) return double.infinity;
    return width < desktopFrom ? 680 : 720;
  }

  static EdgeInsets padding(BuildContext context) {
    final margin = side(context);
    return EdgeInsets.fromLTRB(margin, 4, margin, 32);
  }
}

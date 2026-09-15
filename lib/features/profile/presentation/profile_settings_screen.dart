import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../auth/data/auth_store.dart';
import '../../search/data/image_source_picker.dart';
import '../../security/presentation/login_activity_screen.dart';
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
/// **What the reference shows and this does not.** Three things on it have
/// nothing behind them on the server, and a settings page that states an
/// untruth about an account is worse than one that stays quiet:
///
///   * "Verified" beside the phone and the email. Neither `Profile` nor the
///     session carries a verification flag, and a green tick nobody checked is
///     a security claim this app would be inventing.
///   * "Member since". No `created_at` is read anywhere in this app.
///   * Two-factor authentication. There is no 2FA in this codebase at all, so
///     the row would open nothing.
///
/// [LoginActivityScreen] already takes the same line for the same reason.
/// "Profile complete" is kept because it is *derived* here from what the
/// profile actually holds rather than read from a field the server never sent.
class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _store = ProfileStore.instance;

  /// The picked file, held until it is saved, so the shopper sees the actual
  /// photograph in place before anything is uploaded and can back out of it.
  File? _pendingPhoto;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
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

  void _openLoginActivity() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginActivityScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _store.load(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              // A page-width cap, so this is a form on a tablet or a desktop
              // window rather than one line of rows stretched across it.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
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
                      const SizedBox(height: 16),

                      _GroupHeading(
                        icon: Icons.person_outline,
                        title: 'Personal Information',
                        subtitle:
                            'Your basic details used for communication and '
                            'delivery.',
                      ),
                      const SizedBox(height: 10),
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
                            last: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _GroupHeading(
                        icon: Icons.shield_outlined,
                        title: 'Account Security',
                        subtitle: 'Keep your account safe and secure.',
                      ),
                      const SizedBox(height: 10),
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
                            icon: Icons.fingerprint,
                            title: 'Login Activity',
                            subtitle: 'View devices and recent sign-ins.',
                            onTap: _openLoginActivity,
                            last: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      const _SafetyNote(),
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

/// This page's type scale, a step down from the app's defaults.
///
/// Gathered here rather than spelled out at each widget so the hierarchy is a
/// decision in one place: four ranks, each clearly apart from the one above it,
/// and nothing below 11 -- which is where supporting text stops being readable
/// on a phone held at arm's length.
///
/// Every style is still derived from the theme, so the app's font and the
/// reader's own text-size setting both carry through. These are sizes, not a
/// second typography.
class _Type {
  const _Type._();

  /// The page's name. The largest thing here, and the only thing at this rank.
  static TextStyle? pageTitle(ThemeData t) => t.textTheme.titleLarge?.copyWith(
    fontSize: 22,
    height: 1.15,
    fontWeight: FontWeight.w800,
  );

  /// The line under it, and the line under each group heading.
  static TextStyle? pageNote(ThemeData t) => t.textTheme.bodySmall?.copyWith(
    fontSize: 12.5,
    height: 1.3,
    color: t.colorScheme.onSurfaceVariant,
  );

  /// The shopper's name on the card.
  static TextStyle? cardName(ThemeData t) => t.textTheme.titleMedium?.copyWith(
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w800,
  );

  /// A section's name: Personal Information, Account Security.
  static TextStyle? groupTitle(ThemeData t) => t.textTheme.titleSmall?.copyWith(
    fontSize: 15.5,
    height: 1.2,
    fontWeight: FontWeight.w800,
  );

  /// What a row is about -- "Full Name", "Phone Number".
  static TextStyle? rowLabel(ThemeData t) => t.textTheme.bodySmall?.copyWith(
    fontSize: 12.5,
    height: 1.2,
    color: t.colorScheme.onSurfaceVariant,
  );

  /// What it says. The rank that carries the actual information.
  static TextStyle? rowValue(ThemeData t) => t.textTheme.bodyMedium?.copyWith(
    fontSize: 15.5,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );

  /// A row that opens something rather than holding a value.
  static TextStyle? rowTitle(ThemeData t) => t.textTheme.bodyMedium?.copyWith(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  /// The line under such a row.
  static TextStyle? rowNote(ThemeData t) => t.textTheme.bodySmall?.copyWith(
    fontSize: 12.5,
    height: 1.3,
    color: t.colorScheme.onSurfaceVariant,
  );

  /// Buttons, pills and badges.
  static TextStyle? control(ThemeData t) => t.textTheme.labelLarge?.copyWith(
    fontSize: 13,
    height: 1.1,
    fontWeight: FontWeight.w700,
  );

  /// A sheet's own heading.
  static TextStyle? sheetTitle(ThemeData t) => t.textTheme.titleSmall?.copyWith(
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w800,
  );
}

/// The page's own title, with the back arrow beside it.
///
/// Not an [AppBar]: the reference puts the title and its line of explanation in
/// the body, above a card that runs to the page margin.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text('Profile Settings', style: _Type.pageTitle(theme)),
              const SizedBox(height: 1),
              Text(
                'Manage your profile information',
                style: _Type.pageNote(theme),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: tint.withValues(alpha: 0.18)),
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
            children: [
              _Avatar(
                file: pending,
                url: photo,
                initial: _initialOf(name),
                radius: 35,
              ),
              // The camera badge from the reference, and a real second way to
              // reach the picker rather than decoration.
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: tint,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : onChangePhoto,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 13,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _Type.cardName(theme),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 15),
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
                  const SizedBox(height: 3),
                  const _Chip(
                    icon: Icons.check_circle,
                    label: 'Profile complete',
                    ink: AppColors.successInk,
                  ),
                ],
                // Only when the button is *not* beside the card, which is the
                // narrow case handled below.
                if (!wide) ...[
                  const SizedBox(height: 8),
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
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      icon: busy
          ? const _ButtonSpinner()
          : const Icon(Icons.photo_camera_outlined, size: 16),
      label: Text('Change Photo', style: _Type.control(theme)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _Type.groupTitle(theme)),
              const SizedBox(height: 1),
              Text(subtitle, style: _Type.pageNote(theme)),
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
      ),
      child: Column(children: children),
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
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String? value;

  /// What to say when the account has not filled this in. Shown held back, so
  /// an empty field reads as empty rather than as a value.
  final String empty;
  final VoidCallback onEdit;
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
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AppTheme.radiusControl,
                    ),
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: _Type.rowLabel(theme)),
                      const SizedBox(height: 1),
                      Text(
                        filled ? value! : empty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _Type.rowValue(theme)?.copyWith(
                          color: filled
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _EditPill(onTap: onEdit),
              ],
            ),
          ),
        ),
        if (!last)
          Divider(
            height: 1,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
      ],
    );
  }
}

/// The reference's pill-shaped affordance for changing a detail.
///
/// It says "Change" rather than "Edit" on every row. The word is the promise:
/// a contact method is not edited in place, it is replaced and then proved,
/// and the name goes through a box of its own rather than being typed over.
class _EditPill extends StatelessWidget {
  const _EditPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_outlined,
                size: 15,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 5),
              Text(
                'Change',
                style: _Type.control(
                  theme,
                )?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 1),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.primary,
              ),
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
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AppTheme.radiusControl,
                    ),
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: _Type.rowTitle(theme)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: _Type.rowNote(theme)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (!last)
          Divider(
            height: 1,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
      ],
    );
  }
}

/// The reassurance at the foot of the reference.
class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: tint.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(
              Icons.shield_outlined,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your information is safe with us',
                  style: _Type.rowTitle(theme)?.copyWith(color: tint),
                ),
                const SizedBox(height: 1),
                Text(
                  'Your name and photo are visible on reviews and to sellers '
                  'you buy from. Nothing else here is shown to anyone.',
                  style: _Type.rowNote(theme),
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ink),
          const SizedBox(width: 4),
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

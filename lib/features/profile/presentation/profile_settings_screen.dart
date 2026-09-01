import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_store.dart';
import '../../search/data/image_source_picker.dart';
import '../data/profile_store.dart';
import 'photo_source_sheet.dart';

/// View and change the account: photograph, name, sign-in address, password.
///
/// One page with four sections rather than four pages, because the four are
/// asked about together and three of them are a single field. It is a page and
/// not a sheet: a password change is not something to do half-covered by the
/// screen behind it.
///
/// Each section saves on its own. That is the whole structure: a name and a
/// password have nothing to do with each other, they fail for different
/// reasons, and one "Save everything" button would make a rejected password
/// look like a rejected name.
class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _store = ProfileStore.instance;

  final _name = TextEditingController();

  /// The contact number a courier rings. It lives on the account rather than on
  /// each address because it is the same number wherever a parcel is sent, and
  /// because the new-address form deliberately does not ask for one -- yet the
  /// server refuses an order that carries no phone. Without this field there is
  /// nowhere in the app to supply one, and checkout cannot complete at all.
  final _phone = TextEditingController();

  /// True once the boxes have been filled from the server, so a profile that
  /// arrives while someone is typing does not overwrite what they typed.
  bool _nameSeeded = false;
  bool _phoneSeeded = false;

  /// The picked file, held until it is saved. This is the preview: the shopper
  /// sees the actual photograph in place before anything is uploaded, and can
  /// back out of it.
  File? _pendingPhoto;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _seedName();
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    _seedName();
    setState(() {});
  }

  void _seedName() {
    if (!_nameSeeded) {
      final name = _store.displayName;
      if (name != null && name.isNotEmpty) {
        _name.text = name;
        _nameSeeded = true;
      }
    }
    if (!_phoneSeeded) {
      final phone = _store.profile?.phone;
      if (phone != null && phone.isNotEmpty) {
        _phone.text = phone;
        _phoneSeeded = true;
      }
    }
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
      _say(e.message, bad: true);
    }
  }

  // ── Name ──────────────────────────────────────────────────────────────────

  Future<void> _saveName() async {
    if (_store.saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _say('Enter your name.', bad: true);
      return;
    }

    FocusScope.of(context).unfocus();
    try {
      await _store.saveName(name, phone: _phone.text);
      _say('Profile updated');
    } on ApiError catch (e) {
      _say(e.message, bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = AuthStore.instance.account;

    if (account == null) {
      // Reachable only by getting here and then signing out -- the account
      // screen does not offer the row to a guest. Saying so beats an empty form
      // that would 401 on every button.
      return Scaffold(
        appBar: AppBar(title: const Text('Profile settings')),
        body: const Center(child: Text('Sign in to manage your profile.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile settings')),
      body: ListView(
        // A page-width cap, so the form is a form on a tablet or a desktop
        // window rather than one line of boxes stretched across it.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_store.loadError != null) ...[
                    _LoadNotice(message: _store.loadError!, onRetry: _retry),
                    const SizedBox(height: 14),
                  ],

                  _Section(
                    title: 'Profile photo',
                    icon: Icons.account_circle_outlined,
                    child: _PhotoSection(
                      pending: _pendingPhoto,
                      url: _store.avatarUrl,
                      initial: _initialOf(_store.displayName ?? account.email),
                      busy: _store.saving,
                      onPick: _pickPhoto,
                      onSave: _savePhoto,
                      onDiscard: () => setState(() => _pendingPhoto = null),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _Section(
                    title: 'Personal information',
                    icon: Icons.badge_outlined,
                    child: _NameSection(
                      controller: _name,
                      phoneController: _phone,
                      busy: _store.saving,
                      onSave: _saveName,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _Section(
                    title: 'Email',
                    icon: Icons.alternate_email,
                    child: _EmailSection(
                      current: account.email,
                      onChanged: (message) => _say(message),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _Section(
                    title: 'Security',
                    icon: Icons.lock_outline,
                    child: _PasswordSection(
                      onChanged: () => _say('Password updated'),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    'Your name and photo are visible on reviews and to sellers '
                    'you buy from.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _retry() => _store.load(force: true);

  static String _initialOf(String value) =>
      value.isEmpty ? '?' : value.trim().characters.first.toUpperCase();
}

/// The load failed. Shown rather than swallowed: the fields below are seeded
/// from the session and would otherwise look like the whole truth.
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

/// One titled card. The page is four of these, so they are one widget.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// The avatar, the picker, and the preview-then-save step.
class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.pending,
    required this.url,
    required this.initial,
    required this.busy,
    required this.onPick,
    required this.onSave,
    required this.onDiscard,
  });

  final File? pending;
  final String? url;
  final String initial;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewing = pending != null;

    return Column(
      children: [
        Row(
          children: [
            _Avatar(file: pending, url: url, initial: initial, radius: 34),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    previewing ? 'New photo' : 'Your photo',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewing ? 'Not saved yet.' : 'JPG or PNG, up to 5 MB.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!previewing)
              OutlinedButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(url == null ? 'Upload' : 'Change'),
              ),
          ],
        ),
        if (previewing) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDiscard,
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onSave,
                  child: busy
                      ? const _ButtonSpinner()
                      : const Text('Save photo'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The picture itself: the pending file, else the stored URL, else the initial.
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
        style: theme.textTheme.titleLarge?.copyWith(
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
    // falling back to the initial rather than to a broken-image glyph: a dead
    // avatar URL must not leave a grey hole where a face was.
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

/// The name, and the Save Changes button for it.
class _NameSection extends StatelessWidget {
  const _NameSection({
    required this.controller,
    required this.phoneController,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController controller;
  final TextEditingController phoneController;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSave(),
          decoration: const InputDecoration(
            labelText: 'Phone number',
            prefixIcon: Icon(Icons.phone_outlined),
            // Not decoration: the courier needs it, and an order that carries
            // no number is refused outright.
            helperText: 'Used to reach you about deliveries.',
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: busy ? null : onSave,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: busy ? const _ButtonSpinner() : const Text('Save changes'),
        ),
      ],
    );
  }
}

/// The sign-in address. Shown plainly, changed behind the current password.
class _EmailSection extends StatefulWidget {
  const _EmailSection({required this.current, required this.onChanged});

  final String current;

  /// Called with the message to show, which differs by outcome: a project with
  /// confirmations on has not changed the address yet.
  final void Function(String message) onChanged;

  @override
  State<_EmailSection> createState() => _EmailSectionState();
}

class _EmailSectionState extends State<_EmailSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _open = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Deliberately loose. A strict RFC 5322 pattern rejects addresses that work,
  /// and the server is the thing that actually decides -- this catches the
  /// typo, it does not adjudicate.
  static final _shape = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!_shape.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (email.toLowerCase() == widget.current.toLowerCase()) {
      setState(() => _error = 'That is already your email address.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ProfileStore.instance.changeEmail(
        newEmail: email,
        currentPassword: _password.text,
      );
      if (!mounted) return;
      setState(() {
        _open = false;
        _busy = false;
      });
      _email.clear();
      _password.clear();
      widget.onChanged(
        result == EmailChange.applied
            ? 'Email updated'
            : 'Check $email for the link that confirms the change',
      );
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
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.current,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You sign in with this address.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _open = !_open;
                      _error = null;
                    }),
              child: Text(_open ? 'Cancel' : 'Change'),
            ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'New email address',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 10),
          _PasswordField(
            controller: _password,
            label: 'Current password',
            onSubmitted: _submit,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ErrorLine(_error!),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy ? const _ButtonSpinner() : const Text('Update email'),
          ),
          const SizedBox(height: 8),
          Text(
            'We may email the new address to confirm it before the change '
            'takes effect.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Current, new, confirm.
class _PasswordSection extends StatefulWidget {
  const _PasswordSection({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _open = false;
  bool _busy = false;
  String? _error;

  /// GoTrue's own floor is 6. Asking for 8 is a choice this app can make and
  /// the server will accept; asking for less than 6 would be a rule the server
  /// then rejects, which is a worse experience than the honest one.
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
            'Use at least $_minLength characters for the new '
            'password.',
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
      // Cleared the moment it succeeds. Three password boxes left sitting
      // filled behind a "done" message is a credential on screen for no
      // reason.
      _current.clear();
      _next.clear();
      _confirm.clear();
      setState(() {
        _busy = false;
        _open = false;
      });
      widget.onChanged();
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
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Password',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Change the password you sign in with.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _open = !_open;
                      _error = null;
                    }),
              child: Text(_open ? 'Cancel' : 'Change'),
            ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const _ButtonSpinner()
                : const Text('Update password'),
          ),
        ],
      ],
    );
  }
}

/// An obscured field with a reveal toggle.
///
/// The toggle matters: obscured boxes are where typos live, and a shopper who
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

/// A validation or server message, in the error colour, beside the fields it
/// is about rather than in a snackbar that covers them.
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

/// The in-flight state of a submit button. Sized to the text it replaces so
/// the button does not resize when it starts working.
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_theme.dart';
import '../data/image_source_picker.dart';
import '../presentation/visual_search_screen.dart';

/// Camera or gallery, and everything that can go wrong with either.
///
/// A sheet rather than a dialog for the same reason the location and voice
/// features use one: every way this can end has its own remedy -- allow the
/// camera, open settings, pick from the gallery instead -- and a message that
/// slides away after four seconds takes its own remedy with it.
class VisualSearchSheet extends StatefulWidget {
  const VisualSearchSheet({super.key});

  /// Opens the sheet, and on a successful pick pushes the results screen.
  static Future<void> show(BuildContext context) async {
    final file = await showModalBottomSheet<File>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const VisualSearchSheet(),
    );
    if (file == null || !context.mounted) return;

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VisualSearchScreen(image: file)));
  }

  @override
  State<VisualSearchSheet> createState() => _VisualSearchSheetState();
}

class _VisualSearchSheetState extends State<VisualSearchSheet> {
  PhotoOutcome? _problem;
  bool _busy = false;

  Future<void> _pick(PhotoSource source) async {
    setState(() {
      _busy = true;
      _problem = null;
    });

    final outcome = await ImageSourcePicker.instance.pick(source);
    if (!mounted) return;

    switch (outcome) {
      case PhotoTaken(:final file):
        Navigator.of(context).pop(file);
      case PhotoCancelled():
        // Backing out of the camera is not a failure and gets no message.
        setState(() => _busy = false);
      default:
        setState(() {
          _busy = false;
          _problem = outcome;
        });
    }
  }

  /// Borrowed from geolocator, already a dependency.
  ///
  /// The call is not location-specific -- it opens this app's own settings
  /// page, where every permission including the camera lives. A second
  /// permissions plugin to reach the same screen would be a dependency for
  /// nothing.
  Future<void> _openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // Some devices have no settings activity to open. The message beside the
      // button still says what to do.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _problem;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Search by photo',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Point at a product, or pick a picture you already have. We will '
            'find what looks closest in the catalogue.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _SourceTile(
            icon: Icons.photo_camera_outlined,
            title: 'Take a photo',
            subtitle: 'Point the camera at the product',
            enabled: !_busy,
            onTap: () => _pick(PhotoSource.camera),
          ),
          const SizedBox(height: 10),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            title: 'Choose from gallery',
            subtitle: 'Use a picture already on your phone',
            enabled: !_busy,
            onTap: () => _pick(PhotoSource.gallery),
          ),
          if (problem != null) ...[
            const SizedBox(height: 14),
            _Problem(outcome: problem, onOpenSettings: _openSettings),
          ],
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                ),
                child: Icon(icon, size: 21, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What went wrong and what to do about it.
///
/// Every case names its own remedy. "Something went wrong" is the one message
/// that leaves a shopper stuck, so it is never the message.
class _Problem extends StatelessWidget {
  const _Problem({required this.outcome, required this.onOpenSettings});

  final PhotoOutcome outcome;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (message, needsSettings) = _describe();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
          if (needsSettings) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: onOpenSettings,
                child: const Text('Open settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  (String, bool) _describe() => switch (outcome) {
    PhotoPermissionDenied(source: PhotoSource.camera) => (
      'The camera is off for this app. It is only used while you are '
          'taking a photo to search with.',
      true,
    ),
    PhotoPermissionDenied() => (
      'Photo access is off for this app. It is only used to read the '
          'picture you choose.',
      true,
    ),
    PhotoNoCamera() => (
      'This device has no camera available. You can choose a picture '
          'from the gallery instead.',
      false,
    ),
    PhotoFailed(:final reason) => (
      'That did not work: $reason. You can try the other option.',
      false,
    ),
    // Neither is ever rendered: a taken photo closes the sheet and a
    // cancellation says nothing. Kept so the switch stays exhaustive.
    PhotoTaken() || PhotoCancelled() => ('', false),
  };
}

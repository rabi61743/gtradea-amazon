import 'package:flutter/material.dart';

import '../../search/data/image_source_picker.dart';

/// Camera or gallery.
///
/// Its own small sheet rather than the visual-search one: that sheet runs the
/// pick itself and then hands the picture to a product search, which is not
/// what an avatar wants. What is shared is the part worth sharing --
/// [ImageSourcePicker], with its permission and no-camera handling already
/// worked out.
class PhotoSourceSheet extends StatelessWidget {
  const PhotoSourceSheet({super.key});

  static Future<PhotoSource?> show(BuildContext context) {
    return showModalBottomSheet<PhotoSource>(
      context: context,
      useSafeArea: true,
      builder: (_) => const PhotoSourceSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Profile photo',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(context).pop(PhotoSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

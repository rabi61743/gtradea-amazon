import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/support_attachment.dart';

/// Choosing files to send, and seeing what has been chosen.
///
/// One widget for both places the shop takes an attachment -- the Contact
/// Support form and the product query sheet -- because they upload to the same
/// bucket under the same rules, and two of these would drift apart the first
/// time one of the rules changed.
///
/// It draws the button, what the server will take, and a row per file with its
/// name, kind and size. The heading above it belongs to the caller, so each
/// form can label it in its own voice.

class AttachmentPicker extends StatelessWidget {
  const AttachmentPicker({
    super.key,
    required this.files,
    required this.problem,
    required this.uploading,
    required this.uploaded,
    required this.canAttach,
    required this.onAttach,
    required this.onRemove,
    required this.enabled,
    this.showButton = true,
  });

  final List<PickedAttachment> files;
  final String? problem;
  final bool uploading;
  final int uploaded;
  final bool canAttach;
  final VoidCallback onAttach;
  final ValueChanged<PickedAttachment> onRemove;
  final bool enabled;

  /// Whether to draw the Attach File button.
  ///
  /// A chat composer puts its own paperclip beside the input, where a hand
  /// reaches for it, and only wants the chosen-files half of this.
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap rather than Row: on a narrow phone the button and the limit
        // stack instead of the caption being squeezed to nothing.
        if (showButton)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: enabled && canAttach && !uploading ? onAttach : null,
                icon: const Icon(Icons.attach_file, size: 18),
                label: const Text('Attach File'),
              ),
              Text(
                canAttach
                    // The size the server will take, said before anybody spends
                    // time picking something larger.
                    ? 'Max ${formatFileSize(SupportAttachmentRepository.maxBytes)} '
                          '• ${SupportAttachmentRepository.allowedLabel}'
                    : 'Sign in to attach files.',
                style: muted,
              ),
            ],
          ),

        if (problem != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  problem!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],

        for (final (index, file) in files.indexed) ...[
          const SizedBox(height: 8),
          _AttachedFile(
            file: file,
            // Done, in progress, or still waiting its turn.
            uploading: uploading && index == uploaded,
            done: uploading && index < uploaded,
            onRemove: enabled && !uploading ? () => onRemove(file) : null,
          ),
        ],
      ],
    );
  }
}

/// One chosen file: what it is called, what kind it is, how big, and a way to
/// take it back off.
class _AttachedFile extends StatelessWidget {
  const _AttachedFile({
    required this.file,
    required this.uploading,
    required this.done,
    required this.onRemove,
  });

  final PickedAttachment file;
  final bool uploading;
  final bool done;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          _Thumbnail(file: file),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${file.kindLabel} • ${formatFileSize(file.sizeBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (uploading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (done)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.check_circle,
                size: 18,
                color: AppColors.successInk,
              ),
            )
          else
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove ${file.name}',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// What the file looks like, when it is something that can be looked at.
///
/// An image is shown as itself rather than as an icon: the point of attaching
/// a screenshot to a support ticket is that it is the right screenshot, and a
/// paperclip beside a filename does not tell anybody that. The bytes are
/// already in memory from the pick, so this costs no fetch.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file});

  final PickedAttachment file;

  static const _size = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!file.isImage) {
      return SizedBox(
        width: _size,
        height: _size,
        child: Icon(_icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return Semantics(
      label: 'Preview ${file.name}',
      button: true,
      child: InkWell(
        onTap: () => _openPreview(context),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            file.bytes,
            width: _size,
            height: _size,
            fit: BoxFit.cover,
            // A file that says .png but does not decode is still a file the
            // shopper chose; it keeps its row and falls back to the icon
            // rather than the row collapsing into a red error box.
            errorBuilder: (context, _, _) => Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// The whole picture, for checking it is the right one before it goes.
  void _openPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(file.bytes, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _icon => switch (file.extension) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'doc' || 'docx' => Icons.description_outlined,
    'txt' => Icons.article_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

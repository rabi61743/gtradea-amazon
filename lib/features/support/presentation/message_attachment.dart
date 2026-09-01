import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/support_attachment.dart';

/// One file that was sent with a message, shown inside the thread.
///
/// A picture is shown as itself and a document is named, because those are the
/// two things a reader wants: to see the photograph without opening anything,
/// and to know what the document is before deciding to.
///
/// The bytes come through the media endpoint with the reader's own
/// credentials -- the bucket is private, so there is no address to hand an
/// [Image] directly, and that is also what keeps one shopper out of another's
/// files.
class MessageAttachment extends StatelessWidget {
  const MessageAttachment({
    super.key,
    required this.storageKey,
    required this.onDark,
  });

  /// The key the message carried.
  final String storageKey;

  /// Whether it sits in the shopper's own bubble, which is the filled one.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return SupportAttachmentRepository.isImageKey(storageKey)
        ? _Picture(storageKey: storageKey, onDark: onDark)
        : _Document(storageKey: storageKey, onDark: onDark);
  }
}

/// Opens the file with whatever on the device can read it.
///
/// Written to a temporary file first: the bytes live in memory and the system
/// hands other apps a path, not a buffer. The share sheet is the route --
/// Android puts "Open with" in it -- because it needs no permission and no
/// extra dependency.
Future<void> _open(BuildContext context, String storageKey) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await SupportAttachmentRepository.instance.download(
      storageKey,
    );
    final dir = await getTemporaryDirectory();
    final name = SupportAttachmentRepository.fileNameFor(storageKey);
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('That file could not be opened.')),
      );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.storageKey, required this.onDark});

  final String storageKey;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: FutureBuilder(
          future: SupportAttachmentRepository.instance.download(storageKey),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _Document(storageKey: storageKey, onDark: onDark);
            }
            final bytes = snapshot.data;
            if (bytes == null) {
              return SizedBox(
                height: 120,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onDark ? theme.colorScheme.onPrimary : null,
                    ),
                  ),
                ),
              );
            }
            return InkWell(
              onTap: () => _preview(context, bytes, storageKey),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                // A picture that will not decode is still a file that was
                // sent: it falls back to being named rather than vanishing.
                errorBuilder: (context, _, _) =>
                    _Document(storageKey: storageKey, onDark: onDark),
              ),
            );
          },
        ),
      ),
    );
  }

  void _preview(BuildContext context, Uint8List bytes, String key) {
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
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      SupportAttachmentRepository.fileNameFor(key),
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
}

class _Document extends StatelessWidget {
  const _Document({required this.storageKey, required this.onDark});

  final String storageKey;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = onDark
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final name = SupportAttachmentRepository.fileNameFor(storageKey);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => _open(context, storageKey),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(name), size: 18, color: ink),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ink,
                  decoration: TextDecoration.underline,
                  decorationColor: ink.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.open_in_new, size: 14, color: ink),
          ],
        ),
      ),
    );
  }

  IconData _icon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.txt')) return Icons.article_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

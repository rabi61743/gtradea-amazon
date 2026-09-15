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
/// One corner for everything a message carries -- sent or received, picture
/// or document -- so a thread of mixed attachments reads as one set.
const double _attachmentRadius = 10;

/// How large a picture may be before it stops being a preview.
///
/// It had no ceiling at all: inside the bubble's column the height was
/// unbounded, so a portrait photograph took the full 78% of the width the
/// bubble allows and as much height again as its aspect asked for. One
/// attachment filled the screen and the conversation around it disappeared.
const Size _pictureCapPhone = Size(220, 200);

/// Roomier where there is room. A phone's ceiling on a tablet or a desktop
/// window reads as a stamp in the corner of a bubble twice its width.
const Size _pictureCapWide = Size(300, 260);

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
    // The gap above belongs to the attachment as a whole rather than to either
    // shape it can take. A picture that will not decode falls back to being
    // named, and while both carried their own padding that fallback set itself
    // twice as far from the message as the picture it replaced.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SupportAttachmentRepository.isImageKey(storageKey)
          ? _Picture(storageKey: storageKey, onDark: onDark)
          : _Document(storageKey: storageKey, onDark: onDark),
    );
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
    final cap = MediaQuery.sizeOf(context).shortestSide >= 600
        ? _pictureCapWide
        : _pictureCapPhone;
    final repository = SupportAttachmentRepository.instance;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_attachmentRadius),
      child: FutureBuilder(
        future: repository.download(storageKey),
        // A picture already fetched paints on its first frame rather than
        // spending one as the loading box, which is what made the thread
        // jerk as pictures scrolled back into view.
        initialData: repository.downloaded(storageKey),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Document(storageKey: storageKey, onDark: onDark);
          }
          final bytes = snapshot.data;
          if (bytes == null) return _loading(theme, cap);
          return InkWell(
            onTap: () => _preview(context, bytes, storageKey),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: cap.width,
                maxHeight: cap.height,
              ),
              // Contain rather than cover: the cap is a ceiling, not a shape
              // to fill. The picture keeps its own proportions, and nothing is
              // cropped out of the preview to make it fit -- which is what a
              // cover fit would have done as soon as the box stopped matching
              // the photograph's aspect.
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                // Decoded at the size it is shown, not the camera's. A phone
                // photograph decoded whole is ~48 MB for a 220pt preview: two
                // or three of them overran the image cache, so every picture
                // scrolled back to was decoded again -- laid out at nothing
                // until it was -- and the full texture was scaled down on
                // every frame of the scroll. The preview dialog below still
                // opens the original.
                cacheWidth: (cap.width * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                // A picture that will not decode is still a file that was
                // sent: it falls back to being named rather than vanishing.
                errorBuilder: (context, _, _) =>
                    _Document(storageKey: storageKey, onDark: onDark),
                // The badge rides with the decoded frame rather than sitting
                // over the whole slot, because the error path above replaces
                // the picture with a named file and skips this builder --
                // stacked outside, an "open larger" mark would have been
                // stamped across the very file that could not be shown.
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  return Stack(
                    children: [
                      child,
                      // Says the picture opens, without laying a control
                      // across the face of it -- what a gallery uses.
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.open_in_full,
                              size: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// A box roughly the size of what is coming, rather than a bare spinner on
  /// an unconstrained line: the bubble settles once instead of jumping when
  /// the bytes land.
  Widget _loading(ThemeData theme, Size cap) {
    return Container(
      width: cap.width,
      height: cap.height * 0.7,
      alignment: Alignment.center,
      color: onDark
          ? theme.colorScheme.onPrimary.withValues(alpha: 0.12)
          : theme.colorScheme.surface.withValues(alpha: 0.65),
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: onDark ? theme.colorScheme.onPrimary : null,
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

    return InkWell(
      onTap: () => _open(context, storageKey),
      borderRadius: BorderRadius.circular(_attachmentRadius),
      child: Container(
        // A chip rather than an underlined line of text. The underline was the
        // only thing saying this could be opened, and against the filled
        // bubble it read as part of the message: a bounded surface carries
        // that better, and gives the picture beside it a shape to match.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: onDark
              ? theme.colorScheme.onPrimary.withValues(alpha: 0.12)
              : theme.colorScheme.surface.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(_attachmentRadius),
          border: Border.all(color: ink.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(name), size: 18, color: ink),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _kind(name),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.withValues(alpha: 0.70),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.open_in_new, size: 14, color: ink),
          ],
        ),
      ),
    );
  }

  /// What kind of file it is, taken from its own name.
  ///
  /// The message carries a key and nothing else -- no size, no mime type --
  /// so this says only what is actually known. Inventing a figure to fill the
  /// line would be worse than the line not being there.
  static String _kind(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return 'File';
    return '${name.substring(dot + 1).toUpperCase()} file';
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

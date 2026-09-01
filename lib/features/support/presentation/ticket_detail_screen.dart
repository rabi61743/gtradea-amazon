import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../auth/data/auth_store.dart';
import '../data/support_attachment.dart';
import '../data/support_repository.dart';
import 'attachment_picker.dart';
import 'message_attachment.dart';

/// One conversation.
///
/// Opened with the row the list already has, so the subject and status paint on
/// the first frame, and then re-read from the server -- support can close a
/// ticket while it is being looked at, and inviting a reply to a closed thread
/// is worse than saying it is closed.
class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key, required this.ticket});

  final SupportTicket ticket;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  late SupportTicket _ticket = widget.ticket;
  List<SupportMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;

  /// Files chosen for the next message.
  final List<PickedAttachment> _files = [];
  String? _fileProblem;
  int _uploaded = 0;
  bool _uploading = false;

  /// The message the next one answers, if any.
  SupportMessage? _replyingTo;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Together, so a slow status call does not hold up the messages.
      final results = await Future.wait([
        SupportRepository.instance.messages(_ticket.id),
        SupportRepository.instance.byId(_ticket.id),
      ]);
      if (!mounted) return;
      setState(() {
        _messages = results[0] as List<SupportMessage>;
        _ticket = results[1] as SupportTicket;
        _loading = false;
      });
      _toBottom();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The newest message is the one worth seeing first.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Chooses files for the next message.
  Future<void> _attach() async {
    setState(() => _fileProblem = null);
    final List<PickedAttachment> picked;
    try {
      picked = await SupportAttachmentRepository.instance.pick();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fileProblem = 'The file picker could not be opened.');
      return;
    }
    if (!mounted || picked.isEmpty) return;

    String? refusal;
    final accepted = <PickedAttachment>[];
    for (final file in picked) {
      final reason = SupportAttachmentRepository.rejectionFor(file);
      if (reason != null) {
        refusal ??= reason;
        continue;
      }
      if (_files.any((held) => held.name == file.name)) continue;
      accepted.add(file);
    }

    setState(() {
      _files.addAll(accepted);
      _fileProblem = refusal;
    });
  }

  /// The message an id points at, when it is one this thread holds.
  SupportMessage? _messageById(String? id) {
    if (id == null) return null;
    for (final message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  /// Answers one message in particular.
  void _replyTo(SupportMessage message) {
    setState(() => _replyingTo = message);
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  void _removeFile(PickedAttachment file) {
    setState(() {
      _files.remove(file);
      _fileProblem = null;
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    // Words, a file, or both -- but not nothing.
    if ((text.isEmpty && _files.isEmpty) || _sending) return;

    setState(() => _sending = true);
    try {
      final keys = <String>[];
      if (_files.isNotEmpty) {
        setState(() {
          _uploading = true;
          _uploaded = 0;
        });
        for (final file in _files) {
          keys.add(await SupportAttachmentRepository.instance.upload(file));
          if (!mounted) return;
          setState(() => _uploaded = keys.length);
        }
        if (mounted) setState(() => _uploading = false);
      }
      await SupportRepository.instance.send(
        _ticket.id,
        // A row with no words of its own reads as a blank in the thread.
        text.isEmpty ? '(attachment)' : text,
        attachments: keys,
        replyToId: _replyingTo?.id,
      );
      if (!mounted) return;
      // Cleared only once the server has it. Clearing on tap and then failing
      // loses what somebody wrote.
      _composer.clear();
      _files.clear();
      _replyingTo = null;
      final fresh = await SupportRepository.instance.messages(_ticket.id);
      if (!mounted) return;
      setState(() {
        _messages = fresh;
        _sending = false;
      });
      _toBottom();
    } on ApiError catch (e) {
      if (!mounted) return;
      // The files stay chosen so the message can be sent again without
      // picking them a second time.
      setState(() {
        _sending = false;
        _uploading = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              e.isNetwork
                  ? 'No connection. Your message was not sent.'
                  : e.message,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ticket.subject.isEmpty ? 'Support request' : _ticket.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _ticket.ticketNumber.isEmpty
                  ? _ticket.statusLabel
                  : '${_ticket.ticketNumber} · ${_ticket.statusLabel}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          if (_ticket.isOpen)
            _Composer(
              controller: _composer,
              sending: _sending,
              onSend: _send,
              files: _files,
              fileProblem: _fileProblem,
              uploading: _uploading,
              uploaded: _uploaded,
              canAttach: AuthStore.instance.account != null,
              onAttach: _attach,
              onRemoveFile: _removeFile,
              replyingTo: _replyingTo,
              onCancelReply: _cancelReply,
            )
          else
            const _Closed(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LoadFailed(
            message: error.isNetwork
                ? 'No connection. Check your network and try again.'
                : error.message,
            onRetry: _load,
          ),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      children: [
        // The ticket's own description is the first thing said in the thread,
        // and the server does not repeat it as a message.
        if (_ticket.description.isNotEmpty)
          _Bubble(text: _ticket.description, mine: true, at: _ticket.createdAt),
        for (final message in _messages)
          _Bubble(
            text: message.message,
            mine: message.isMine,
            at: message.createdAt,
            attachments: message.attachments,
            // Looked up in the thread rather than carried in the message: the
            // server stores the id, and the thread already holds the rows.
            quoted: _messageById(message.replyToId),
            onReply: () => _replyTo(message),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.mine,
    this.at,
    this.attachments = const [],
    this.quoted,
    this.onReply,
  });

  final String text;
  final bool mine;
  final DateTime? at;

  /// Storage keys the message carried. They come back from the server with
  /// the message, so a thread reopened tomorrow still shows them.
  final List<String> attachments;

  /// The message this one answers, when the server says it answers one.
  final SupportMessage? quoted;

  /// Starts a reply to this message. Absent on the ticket's opening
  /// description, which is not a message and has no id to answer.
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            // Never the full width: a bubble that reaches both edges stops
            // reading as one side of a conversation.
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: GestureDetector(
              // Held rather than tapped, which is how a chat offers this and
              // keeps the bubble free of a control on every line.
              onLongPress: onReply == null ? null : () => _offerReply(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: mine
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(AppTheme.radiusCard),
                    topRight: const Radius.circular(AppTheme.radiusCard),
                    bottomLeft: Radius.circular(mine ? AppTheme.radiusCard : 3),
                    bottomRight: Radius.circular(
                      mine ? 3 : AppTheme.radiusCard,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (quoted case final original?) ...[
                      _QuotedMessage(message: original, onDark: mine),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        color: mine
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    for (final key in attachments)
                      MessageAttachment(storageKey: key, onDark: mine),
                  ],
                ),
              ),
            ),
          ),
          if (at != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: Text(
                formatRelative(at!),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.files,
    required this.fileProblem,
    required this.uploading,
    required this.uploaded,
    required this.canAttach,
    required this.onAttach,
    required this.onRemoveFile,
    required this.replyingTo,
    required this.onCancelReply,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final List<PickedAttachment> files;
  final String? fileProblem;
  final bool uploading;
  final int uploaded;
  final bool canAttach;
  final VoidCallback onAttach;
  final ValueChanged<PickedAttachment> onRemoveFile;

  /// The message being answered, shown above the field so it is plain which
  /// one this will attach to.
  final SupportMessage? replyingTo;
  final VoidCallback onCancelReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (replyingTo case final replying?) ...[
              _ReplyPreview(message: replying, onCancel: onCancelReply),
              const SizedBox(height: 8),
            ],
            // What has been chosen, above the field it will be sent with.
            if (files.isNotEmpty || fileProblem != null) ...[
              AttachmentPicker(
                files: files,
                problem: fileProblem,
                uploading: uploading,
                uploaded: uploaded,
                canAttach: canAttach,
                onAttach: onAttach,
                onRemove: onRemoveFile,
                enabled: !sending,
                // The button lives in the row below, beside the field.
                showButton: false,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Beside the input, which is where a hand reaches for it.
                IconButton(
                  onPressed: sending || !canAttach ? null : onAttach,
                  icon: const Icon(Icons.attach_file, size: 20),
                  tooltip: canAttach
                      ? 'Attach File'
                      : 'Sign in to attach files',
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Write a message',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: sending
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      : IconButton.filled(
                          onPressed: onSend,
                          icon: const Icon(Icons.send, size: 20),
                          tooltip: 'Send',
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on _Bubble {
  void _offerReply(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.of(sheet).pop();
                onReply?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The message about to be answered, above the composer.
///
/// Names who wrote it and what it said, and shows the picture when it was
/// one -- so it is plain which message this reply will attach to before it is
/// sent, and not merely that some reply is in progress.
class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.message, required this.onCancel});

  final SupportMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = message.attachments
        .where(SupportAttachmentRepository.isImageKey)
        .firstOrNull;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          if (image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FutureBuilder(
                future: SupportAttachmentRepository.instance.download(image),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return const SizedBox(width: 36, height: 36);
                  }
                  return Image.memory(
                    bytes,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, _) =>
                        const SizedBox(width: 36, height: 36),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.isMine ? 'You' : 'Support',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quotedSummary(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cancel reply',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// The message a reply answers, drawn inside the reply's own bubble.
///
/// Tinted and ruled down one side so it reads as something quoted rather than
/// as more of the same message.
class _QuotedMessage extends StatelessWidget {
  const _QuotedMessage({required this.message, required this.onDark});

  final SupportMessage message;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = onDark
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: ink, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.isMine ? 'You' : 'Support',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quotedSummary(message),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ink.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a quoted message says in one line.
///
/// A message that is only a file has no words worth quoting, so it is named by
/// the file instead -- which is what the reader needs to know they are being
/// answered about the receipt and not the sentence above it.
String quotedSummary(SupportMessage message) {
  final text = message.message.trim();
  if (text.isNotEmpty && text != '(attachment)') return text;
  if (message.attachments.isEmpty) return text;
  final name = SupportAttachmentRepository.fileNameFor(
    message.attachments.first,
  );
  final more = message.attachments.length - 1;
  return more > 0 ? '$name and $more more' : name;
}

/// A thread support has finished with.
class _Closed extends StatelessWidget {
  const _Closed();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Text(
          // No composer at all rather than one that fails on send: the server
          // rejects a reply to a closed ticket, and offering the box would be
          // an invitation to write something that goes nowhere.
          'This conversation is closed. Start a new message if you still '
          'need help.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../auth/data/auth_store.dart';
import '../../support/data/support_attachment.dart';
import '../../support/presentation/attachment_picker.dart';
import '../../support/data/support_repository.dart';
import '../../support/presentation/ticket_detail_screen.dart';

/// Contact Support: what has already been asked, and a form to ask something
/// new.
///
/// Both halves are the support system this app already has -- the list is
/// `GET /support/tickets`, the form is `POST /support/tickets` through the same
/// [SupportRepository] the message sheet uses. Nothing here is a second
/// ticketing system; a ticket raised on this page is the same ticket, in the
/// same thread list, as one raised anywhere else.
class ContactSupportScreen extends StatefulWidget {
  const ContactSupportScreen({super.key});

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _description = TextEditingController();

  String? _category;

  bool _sending = false;
  String? _problem;

  /// Files chosen but not yet sent.
  final List<PickedAttachment> _files = [];

  /// Why the last pick was refused -- an unsupported type or an oversized
  /// file. Kept beside the attachment row rather than shown as a snackbar, so
  /// it stays on screen next to the control it is about.
  String? _fileProblem;

  /// How many of [_files] have reached storage, for the progress line.
  int _uploaded = 0;
  bool _uploading = false;

  /// A ticket that was raised while its files were not.
  ///
  /// The ticket is real and support has it; only the upload failed. Holding it
  /// here is what lets Retry send the files against that same ticket instead
  /// of raising a second one for the same problem.
  SupportTicket? _awaitingFiles;

  /// The ticket just raised, so the page can say so in place of the form
  /// rather than leaving somebody wondering whether it went.
  SupportTicket? _sent;

  List<SupportTicket> _recent = const [];
  bool _loadingRecent = true;

  @override
  void initState() {
    super.initState();
    // The address support will reply to. Prefilled from the session because
    // the shop already knows it, and still editable because a shopper may want
    // the reply somewhere else -- and because a guest has to type one.
    _email.text = AuthStore.instance.account?.email ?? '';
    unawaited(_loadRecent());
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Best effort: the list is context, and the form is the point of the page.
  /// A failure to read past tickets must not stop somebody raising a new one.
  Future<void> _loadRecent() async {
    if (!AuthStore.instance.isSignedIn) {
      if (mounted) setState(() => _loadingRecent = false);
      return;
    }
    try {
      final tickets = await SupportRepository.instance.listMine();
      if (!mounted) return;
      setState(() {
        _recent = tickets;
        _loadingRecent = false;
      });
    } on ApiError {
      if (!mounted) return;
      setState(() => _loadingRecent = false);
    }
  }

  /// Chooses files, and says so when one cannot be sent.
  ///
  /// Refusals are reported one at a time and the good files are still kept:
  /// picking four photographs and one oversized video should attach the four,
  /// not throw the lot away.
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

  void _removeFile(PickedAttachment file) {
    setState(() {
      _files.remove(file);
      _fileProblem = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _problem = null);
    if (!(_form.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _sending = true);

    final SupportTicket ticket;
    try {
      ticket = await SupportRepository.instance.create(
        email: _email.text.trim(),
        subject: _subject.text.trim(),
        description: _description.text.trim(),
        category: _category ?? 'general',
        name: _name.text.trim(),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _problem = e.isNetwork
            ? 'No connection. Your ticket was not sent.'
            : e.message;
      });
      return;
    }

    if (!mounted) return;
    // The ticket exists from here on. Whatever happens to the files, it must
    // not be raised a second time.
    if (_files.isNotEmpty && !await _sendFiles(ticket)) return;
    if (!mounted) return;

    setState(() {
      _sent = ticket;
      _sending = false;
      _awaitingFiles = null;
      _files.clear();
      // The new one belongs at the top of the list behind the confirmation.
      _recent = [ticket, ..._recent];
    });
  }

  /// Uploads the chosen files and posts them to [ticket].
  ///
  /// Returns whether it got there. On failure the ticket is held in
  /// [_awaitingFiles] and the form stays put with a Retry, because the
  /// alternative -- reporting success -- would tell somebody their screenshot
  /// is with support when it is nowhere.
  Future<bool> _sendFiles(SupportTicket ticket) async {
    setState(() {
      _uploading = true;
      _uploaded = 0;
    });
    try {
      final keys = <String>[];
      for (final file in _files) {
        keys.add(await SupportAttachmentRepository.instance.upload(file));
        if (!mounted) return false;
        setState(() => _uploaded = keys.length);
      }
      await SupportRepository.instance.send(
        ticket.id,
        'Attached: ${_files.map((f) => f.name).join(', ')}',
        attachments: keys,
      );
      if (mounted) setState(() => _uploading = false);
      return true;
    } on ApiError catch (e) {
      if (!mounted) return false;
      setState(() {
        _uploading = false;
        _sending = false;
        _awaitingFiles = ticket;
        _problem = e.isNetwork
            ? 'Ticket ${ticket.ticketNumber} was raised, but there was no '
                  'connection to upload your files. You can try again.'
            : 'Ticket ${ticket.ticketNumber} was raised, but the files could '
                  'not be uploaded: ${e.message}';
      });
      return false;
    }
  }

  /// Sends the files again, against the ticket already raised.
  Future<void> _retryFiles() async {
    final ticket = _awaitingFiles;
    if (ticket == null) return;
    setState(() {
      _problem = null;
      _sending = true;
    });
    if (!await _sendFiles(ticket)) return;
    if (!mounted) return;
    setState(() {
      _sent = ticket;
      _sending = false;
      _awaitingFiles = null;
      _files.clear();
      _recent = [ticket, ..._recent];
    });
  }

  void _startAnother() {
    setState(() {
      _sent = null;
      _subject.clear();
      _description.clear();
      _category = null;
      _problem = null;
      _files.clear();
      _fileProblem = null;
      _awaitingFiles = null;
      _uploaded = 0;
    });
  }

  void _open(SupportTicket ticket) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TicketDetailScreen(ticket: ticket)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sent;

    return Scaffold(
      appBar: AppBar(title: const Text('Contact Support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (_loadingRecent)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_recent.isNotEmpty) ...[
              _RecentTickets(tickets: _recent, onOpen: _open),
              const SizedBox(height: 16),
            ],
            if (sent != null)
              _Sent(
                ticket: sent,
                onView: () => _open(sent),
                onAnother: _startAnother,
              )
            else
              _TicketForm(
                formKey: _form,
                name: _name,
                email: _email,
                subject: _subject,
                description: _description,
                category: _category,
                onCategory: (value) => setState(() => _category = value),
                sending: _sending,
                problem: _problem,
                onSubmit: _submit,
                files: _files,
                fileProblem: _fileProblem,
                uploading: _uploading,
                uploaded: _uploaded,
                canAttach: AuthStore.instance.account != null,
                onAttach: _attach,
                onRemoveFile: _removeFile,
                onRetryFiles: _awaitingFiles == null ? null : _retryFiles,
              ),
          ],
        ),
      ),
    );
  }
}

/// The last few conversations, newest first.
class _RecentTickets extends StatelessWidget {
  const _RecentTickets({required this.tickets, required this.onOpen});

  final List<SupportTicket> tickets;
  final ValueChanged<SupportTicket> onOpen;

  /// Enough to recognise the thing you asked about, without turning this page
  /// into the messages list it links to.
  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = tickets.take(_shown).toList(growable: false);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Recent Tickets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final ticket in shown)
              InkWell(
                onTap: () => onOpen(ticket),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (ticket.ticketNumber.isNotEmpty)
                              Text(
                                ticket.ticketNumber,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              ticket.subject,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (ticket.createdAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                formatDay(ticket.createdAt!),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StatusPill(ticket: ticket),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where the ticket has got to. The same wording and the same colour rule as
/// the messages list, so one page does not call it something the other does
/// not.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = ticket.isOpen
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        ticket.statusLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colour,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The form itself.
class _TicketForm extends StatelessWidget {
  const _TicketForm({
    required this.formKey,
    required this.name,
    required this.email,
    required this.subject,
    required this.description,
    required this.category,
    required this.onCategory,
    required this.sending,
    required this.problem,
    required this.onSubmit,
    required this.files,
    required this.fileProblem,
    required this.uploading,
    required this.uploaded,
    required this.canAttach,
    required this.onAttach,
    required this.onRemoveFile,
    required this.onRetryFiles,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController subject;
  final TextEditingController description;
  final String? category;
  final ValueChanged<String?> onCategory;
  final bool sending;
  final String? problem;
  final VoidCallback onSubmit;
  final List<PickedAttachment> files;
  final String? fileProblem;
  final bool uploading;
  final int uploaded;

  /// The bucket requires a signed-in account, so a guest is told that rather
  /// than handed a button that cannot work.
  final bool canAttach;
  final VoidCallback onAttach;
  final ValueChanged<PickedAttachment> onRemoveFile;

  /// Set only when a ticket was raised but its files were not sent.
  final VoidCallback? onRetryFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Submit a Support Ticket',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Fill out the form below and we'll respond within 2-4 hours",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),

              const _Label('Name', required: true),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Your name'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter your name so support knows who is asking.'
                    : null,
              ),
              const SizedBox(height: 14),

              const _Label('Email', required: true),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'you@example.com'),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) {
                    return 'Enter an email so support can reply.';
                  }
                  // Deliberately loose. The server is the authority on what it
                  // accepts; this only catches the obvious typo before a round
                  // trip, and a stricter rule here would reject real addresses.
                  if (!text.contains('@') || !text.contains('.')) {
                    return 'That does not look like an email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              const _Label('Category', required: true),
              DropdownButtonFormField<String>(
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(),
                hint: const Text('Select a category'),
                // The shop's own list, so a ticket is filed under something
                // support actually sorts by.
                items: [
                  for (final entry in supportTicketCategories.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: sending ? null : onCategory,
                validator: (value) =>
                    value == null ? 'Choose a category.' : null,
              ),
              const SizedBox(height: 14),

              const _Label('Subject', required: true),
              TextFormField(
                controller: subject,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Brief description of your issue',
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Add a short subject.'
                    : null,
              ),
              const SizedBox(height: 14),

              const _Label('Description', required: true),
              TextFormField(
                controller: description,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText:
                      'Please provide as much detail as possible about your '
                      'issue...',
                  alignLabelWithHint: true,
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Tell support what happened.'
                    : null,
              ),

              const SizedBox(height: 14),
              const _Label('Attachments'),
              AttachmentPicker(
                files: files,
                problem: fileProblem,
                uploading: uploading,
                uploaded: uploaded,
                canAttach: canAttach,
                onAttach: onAttach,
                onRemove: onRemoveFile,
                enabled: !sending,
              ),

              if (problem != null) ...[
                const SizedBox(height: 14),
                _Problem(problem!),
              ],

              if (onRetryFiles != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: sending ? null : onRetryFiles,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry upload'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: sending || onRetryFiles != null ? null : onSubmit,
                  icon: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(
                    uploading
                        ? 'Uploading ${uploaded + 1} of ${files.length}...'
                        : sending
                        ? 'Sending...'
                        : 'Submit Ticket',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The attachment row: the button, what the server will take, and whatever
/// has been chosen so far.
///
/// The ceiling and the type list are the storage bucket's own, not numbers
/// picked here -- see [SupportAttachmentRepository].
/// A field caption, with the asterisk the reference puts on the required ones.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (required)
              TextSpan(
                text: ' *',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Why the ticket did not go. Stated in the form rather than in a snackbar
/// that slides away before it has been read.
class _Problem extends StatelessWidget {
  const _Problem(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The confirmation, in place of the form.
///
/// Carries the ticket number, because that is the thing somebody quotes back
/// when they chase it, and a way through to the thread it started.
class _Sent extends StatelessWidget {
  const _Sent({
    required this.ticket,
    required this.onView,
    required this.onAnother,
  });

  final SupportTicket ticket;
  final VoidCallback onView;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 44,
              color: AppColors.successInk,
            ),
            const SizedBox(height: 12),
            Text(
              'Ticket submitted',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ticket.ticketNumber.isEmpty
                  ? "Support has your message and will reply within 2-4 hours."
                  : 'Ticket ${ticket.ticketNumber}. Support will reply within '
                        '2-4 hours.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onView,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('View ticket'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onAnother,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Submit another'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

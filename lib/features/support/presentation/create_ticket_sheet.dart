import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_store.dart';
import '../data/support_repository.dart';

/// Starts a conversation.
///
/// Three fields, not the web form's six: the category, what it is about, and
/// what is wrong. The email and name come from the session rather than being
/// asked for again -- the server requires an email, and asking a signed-in
/// shopper to type the address they signed in with is a question with a known
/// answer.
class CreateTicketSheet extends StatefulWidget {
  const CreateTicketSheet({
    super.key,
    this.initialSubject = '',
    this.initialBody = '',
    this.category = 'general',
  });

  /// Filled in when the sheet is opened from somewhere that already knows what
  /// the message is about -- a question typed on a product page, say. Empty
  /// everywhere else, which is the sheet exactly as it was.
  final String initialSubject;
  final String initialBody;

  /// Which queue it opens on.
  final String category;

  /// Returns the ticket that was opened, or null if the sheet was dismissed.
  static Future<SupportTicket?> show(
    BuildContext context, {
    String initialSubject = '',
    String initialBody = '',
    String category = 'general',
  }) {
    return showModalBottomSheet<SupportTicket>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CreateTicketSheet(
        initialSubject: initialSubject,
        initialBody: initialBody,
        category: category,
      ),
    );
  }

  @override
  State<CreateTicketSheet> createState() => _CreateTicketSheetState();
}

class _CreateTicketSheetState extends State<CreateTicketSheet> {
  late final _subject = TextEditingController(text: widget.initialSubject);
  late final _body = TextEditingController(text: widget.initialBody);

  late String _category = widget.category;
  bool _sending = false;
  String? _problem;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    final email = AuthStore.instance.account?.email ?? '';

    if (subject.isEmpty || body.isEmpty) {
      setState(() => _problem = 'Add a subject and a message.');
      return;
    }
    if (email.isEmpty) {
      // Should be unreachable -- the chat icon sends a guest to sign in first
      // -- but the server rejects a ticket with no email, and failing here with
      // a clear sentence beats failing there with a 400.
      setState(() => _problem = 'Sign in first so support can reply to you.');
      return;
    }

    setState(() {
      _sending = true;
      _problem = null;
    });

    try {
      final ticket = await SupportRepository.instance.create(
        email: email,
        subject: subject,
        description: body,
        category: _category,
        name: AuthStore.instance.account?.firstName,
      );
      if (!mounted) return;
      Navigator.of(context).pop(ticket);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _problem = e.isNetwork
            ? 'No connection. Your message was not sent.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the very
      // field being typed into.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'New message',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'What is it about',
                ),
                items: [
                  for (final entry in supportTicketCategories.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: _sending
                    ? null
                    : (value) => setState(() => _category = value ?? 'general'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subject,
                enabled: !_sending,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Order GT-1001 arrived damaged',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                enabled: !_sending,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'Tell support what happened',
                  alignLabelWithHint: true,
                ),
              ),
              if (_problem != null) ...[
                const SizedBox(height: 12),
                Text(
                  _problem!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

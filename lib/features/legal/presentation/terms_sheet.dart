import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../data/legal_page_repository.dart';

/// The shop's written terms, fetched and shown in full.
///
/// The text is the server's, so what a shopper agrees to at checkout is the
/// same text the shop is currently publishing -- not a copy pasted into the app
/// at some point in the past.
class TermsSheet extends StatefulWidget {
  const TermsSheet({super.key, this.slug = 'terms'});

  final String slug;

  static Future<void> show(BuildContext context, {String slug = 'terms'}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => TermsSheet(slug: slug),
    );
  }

  @override
  State<TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<TermsSheet> {
  LegalPage? _page;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await LegalPageRepository.instance.bySlug(widget.slug);
      if (mounted) setState(() => _page = page);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _page;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                page?.title.isNotEmpty == true
                    ? page!.title
                    : 'Terms and Conditions',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _error != null
                    ? _Failed(message: _error!.message, onRetry: _load)
                    : page == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          page.body,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // The server's own sentence. A shopper being asked to agree to
            // something has a right to know the text could not be loaded,
            // rather than being shown an empty page.
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// The checkbox that gates placing an order.
///
/// `CheckoutOrderInput.termsAccepted` has been sent to the server since
/// checkout was written -- hardcoded to `true`. The app was telling the backend
/// the customer had accepted terms it had never shown them and never asked
/// about. This is the control that makes that field mean what it says.
class TermsAcceptance extends StatelessWidget {
  const TermsAcceptance({
    super.key,
    required this.accepted,
    required this.onChanged,
    this.enabled = true,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: accepted,
          onChanged: enabled ? (value) => onChanged(value ?? false) : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'I have read and agree to the '),
                  TextSpan(
                    text: 'Terms and Conditions',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.primary,
                    ),
                    // Tapping the words opens them, which is the only way the
                    // sentence above is true.
                    recognizer: (TapGestureRecognizer()
                      ..onTap = () => TermsSheet.show(context)),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

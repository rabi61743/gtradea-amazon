import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../auth/data/auth_store.dart';
import '../../quotes/data/quote_repository.dart';
import '../../support/data/support_attachment.dart';
import '../../support/presentation/attachment_picker.dart';

import '../data/product_detail_content.dart';

/// "Request a quote", as the sibling storefront asks it.
///
/// Four things and no more: what this is, which product, one box for whatever
/// the shopper wants to say, and a button. The quantity stepper, the product
/// card and the price estimate that stood here before are gone --
/// `/product-requests` carries no quantity field, so a stepper was collecting a
/// number the server never received, and the rest was chrome around a single
/// text box.
///
/// The chosen option travels with it where there is one: a seller quoting a
/// wine-red medium needs to know that is what was asked about.
class ProductQuoteSheet extends StatefulWidget {
  const ProductQuoteSheet({
    super.key,
    required this.product,
    this.variantLabel,
  });

  final ProductDetail product;

  /// The option the page is sitting on, in the seller's own words.
  final String? variantLabel;

  static Future<bool?> show(
    BuildContext context, {
    required ProductDetail product,
    String? variantLabel,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          ProductQuoteSheet(product: product, variantLabel: variantLabel),
    );
  }

  @override
  State<ProductQuoteSheet> createState() => _ProductQuoteSheetState();
}

class _ProductQuoteSheetState extends State<ProductQuoteSheet> {
  final _message = TextEditingController();

  bool _busy = false;
  String? _problem;

  /// Files chosen but not yet sent.
  final List<PickedAttachment> _files = [];

  /// Why the last pick was refused. Kept beside the control it is about.
  String? _fileProblem;

  int _uploaded = 0;
  bool _uploading = false;

  /// A request that was raised while its files were not.
  ///
  /// The request is real and the seller has it; only the upload failed.
  /// Holding its id is what lets Retry send the files against that same
  /// request rather than raising a second one for the same product.
  String? _awaitingFiles;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// Chooses files, and says so when one cannot be sent.
  ///
  /// A refusal is reported one at a time and the good files are kept: picking
  /// three photographs and one oversized video should attach the three.
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
    setState(() {
      _busy = true;
      _problem = null;
    });

    final String requestId;
    try {
      requestId = await QuoteRepository.instance.submit(
        sourceId: widget.product.numIid,
        title: widget.product.title,
        imageUrl: widget.product.images.isEmpty
            ? null
            : widget.product.images.first,
        price: formatRupees(widget.product.price),
        message: [
          // The option first, because it is the part the seller cannot infer
          // and the part a shopper assumes was sent.
          if (widget.variantLabel != null) 'Option: ${widget.variantLabel}',
          _message.text.trim(),
        ].where((line) => line.isNotEmpty).join('\n'),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = e.isNetwork
            ? 'No connection. Your request was not sent.'
            : e.message;
      });
      return;
    }

    if (!mounted) return;
    // The request exists from here on. Whatever happens to the files, it must
    // not be raised a second time.
    if (_files.isNotEmpty && !await _sendFiles(requestId)) return;
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Uploads the chosen files and posts them onto [requestId].
  ///
  /// Returns whether it got there. On failure the request is held so Retry can
  /// send the files against it -- reporting plain failure would invite a
  /// second request for the same product, and reporting success would tell
  /// somebody their photograph is with the seller when it is nowhere.
  Future<bool> _sendFiles(String requestId) async {
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
      await QuoteRepository.instance.sendMessage(
        requestId,
        'Attached: ${_files.map((f) => f.name).join(', ')}',
        attachments: keys,
      );
      if (mounted) setState(() => _uploading = false);
      return true;
    } on ApiError catch (e) {
      if (!mounted) return false;
      setState(() {
        _uploading = false;
        _busy = false;
        _awaitingFiles = requestId;
        _problem = e.isNetwork
            ? 'Your request was sent, but there was no connection to upload '
                  'your files. You can try again.'
            : 'Your request was sent, but the files could not be uploaded: '
                  '${e.message}';
      });
      return false;
    }
  }

  /// Sends the files again, against the request already raised.
  Future<void> _retryFiles() async {
    final requestId = _awaitingFiles;
    if (requestId == null) return;
    setState(() {
      _problem = null;
      _busy = true;
    });
    if (!await _sendFiles(requestId)) return;
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the very
      // field being typed into.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        // Scrolls rather than overflows. The sheet's content grew by the
        // attachment row and the file chips under it, and on a short screen --
        // or a tall one with the keyboard up -- a fixed column would run off
        // the bottom. Nothing about the layout changes; it can just be
        // reached now.
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Request a quote',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.variantLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.variantLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _message,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    // The quantity lives here rather than in a stepper, because
                    // this is the field the server actually carries.
                    labelText: 'Quantity, specs, or questions (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                // The same control the Contact Support form uses, against the
                // same bucket and the same rules.
                AttachmentPicker(
                  files: _files,
                  problem: _fileProblem,
                  uploading: _uploading,
                  uploaded: _uploaded,
                  canAttach: AuthStore.instance.account != null,
                  onAttach: _attach,
                  onRemove: _removeFile,
                  enabled: !_busy,
                ),

                if (_problem != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _problem!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],

                if (_awaitingFiles != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _retryFiles,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry upload'),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    // Disabled while a request is in flight, so Send cannot be
                    // pressed twice into two requests for one product.
                    onPressed: _busy || _awaitingFiles != null ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _uploading
                                ? 'Uploading ${_uploaded + 1} of ${_files.length}...'
                                : 'Send request',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

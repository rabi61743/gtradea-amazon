import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/orders_repository.dart';

/// What the shopper filled in on one of the sheets below.
typedef RequestDraft = ({
  String reason,
  String? details,
  List<({String orderItemId, int quantity})> items,
});

/// "Why are you cancelling?" -- the shop's own reasons, and room for more.
///
/// A sheet rather than a dialog: the reason list and the notes box do not fit
/// an alert, and this is a form, not a yes/no.
class CancelOrderSheet extends StatefulWidget {
  const CancelOrderSheet({super.key});

  /// Returns what to send, or null if the shopper backed out.
  static Future<RequestDraft?> show(BuildContext context) {
    return showModalBottomSheet<RequestDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const CancelOrderSheet(),
    );
  }

  @override
  State<CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends State<CancelOrderSheet> {
  final _details = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  /// "Other reason" is only a reason once it has been written down.
  bool get _ready =>
      _reason != null &&
      (_reason != 'other' || _details.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Cancel this order',
      subtitle:
          'It has not been dispatched yet, so it can still be stopped. Our '
          'team reviews every request.',
      action: 'Request cancellation',
      enabled: _ready,
      onSubmit: () => Navigator.of(context).pop((
        reason: _reason!,
        details: _details.text.trim().isEmpty ? null : _details.text.trim(),
        items: const <({String orderItemId, int quantity})>[],
      )),
      children: [
        RadioGroup<String>(
          groupValue: _reason,
          onChanged: (value) => setState(() => _reason = value),
          child: Column(
            children: [
              for (final reason in CancellationReason.all)
                RadioListTile<String>(
                  value: reason.value,
                  title: Text(reason.label),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _details,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _reason == 'other'
                ? 'Tell us what happened'
                : 'Anything else we should know? (optional)',
          ),
        ),
      ],
    );
  }
}

/// "What is coming back, and why?"
///
/// Items first, because a return is about the things rather than the order:
/// the shop's return record is per order item, and sending the whole order
/// when one thing is faulty is what makes a refund wrong.
class ReturnRequestSheet extends StatefulWidget {
  const ReturnRequestSheet({super.key, required this.items});

  /// The order's lines: what can be sent back, and how many of each.
  final List<({String id, String title, int quantity})> items;

  static Future<RequestDraft?> show(
    BuildContext context, {
    required List<({String id, String title, int quantity})> items,
  }) {
    return showModalBottomSheet<RequestDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReturnRequestSheet(items: items),
    );
  }

  @override
  State<ReturnRequestSheet> createState() => _ReturnRequestSheetState();
}

class _ReturnRequestSheetState extends State<ReturnRequestSheet> {
  final _details = TextEditingController();
  final Set<String> _picked = {};
  String? _reason;

  @override
  void initState() {
    super.initState();
    // A one-line order has nothing to choose: the line is the return.
    if (widget.items.length == 1) _picked.add(widget.items.first.id);
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _ready =>
      _picked.isNotEmpty &&
      _reason != null &&
      (_reason != 'other' || _details.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SheetFrame(
      title: 'Request a return',
      subtitle:
          'Pick what is going back and tell us why. A refund is issued once '
          'the shop has the item.',
      action: 'Request return',
      enabled: _ready,
      onSubmit: () => Navigator.of(context).pop((
        reason: _reason!,
        details: _details.text.trim().isEmpty ? null : _details.text.trim(),
        items: [
          for (final item in widget.items)
            if (_picked.contains(item.id))
              (orderItemId: item.id, quantity: item.quantity),
        ],
      )),
      children: [
        Text(
          'What is coming back',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        for (final item in widget.items)
          CheckboxListTile(
            value: _picked.contains(item.id),
            onChanged: (checked) => setState(() {
              if (checked ?? false) {
                _picked.add(item.id);
              } else {
                _picked.remove(item.id);
              }
            }),
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: item.quantity > 1 ? Text('Qty ${item.quantity}') : null,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
        const SizedBox(height: 12),
        Text(
          'Why',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        RadioGroup<String>(
          groupValue: _reason,
          onChanged: (value) => setState(() => _reason = value),
          child: Column(
            children: [
              for (final reason in ReturnReason.all)
                RadioListTile<String>(
                  value: reason.value,
                  title: Text(reason.label),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _details,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _reason == 'other'
                ? 'Tell us what happened'
                : 'Anything that helps us sort it out (optional)',
          ),
        ),
      ],
    );
  }
}

/// The shape both sheets share: a heading, the form, and one button.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.enabled,
    required this.onSubmit,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String action;
  final bool enabled;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        // Above the keyboard, since both sheets end in a text field.
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + insets),
        child: ConstrainedBox(
          // A form, not a banner, on a tablet or a desktop window.
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                // Off until the form says something the server can act on.
                onPressed: enabled ? onSubmit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A raised cancellation or return, as the shop currently has it.
///
/// Everything on it is the server's: the status, the date, the reason and the
/// refund. Nothing is inferred -- least of all the refund, which is only
/// called done when the shop says it is done.
class OrderRequestCard extends StatelessWidget {
  const OrderRequestCard({
    super.key,
    required this.request,
    this.onWithdraw,
    this.busy = false,
  });

  final OrderRequest request;

  /// Offered only for a pending cancellation, which is the one the shop lets
  /// a shopper take back.
  final Future<void> Function()? onWithdraw;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _tone(theme);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 18, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.isReturn ? 'Return request' : 'Cancellation request',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in _lines(context))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
          if (onWithdraw case final withdraw?) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: busy ? null : () => withdraw(),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Withdraw request'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The server's word, in sentence case. Unknown states print as they came
  /// rather than being mapped to something this app made up.
  String get statusLabel => switch (request.status) {
    'pending' => 'Under review',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'received' => 'Received',
    'refunded' => 'Refunded',
    'cancelled' || 'withdrawn' => 'Withdrawn',
    final other =>
      other.isEmpty
          ? 'Requested'
          : other[0].toUpperCase() + other.substring(1).replaceAll('_', ' '),
  };

  IconData get _icon => switch (request.status) {
    'refunded' => Icons.check_circle_outline,
    'rejected' => Icons.cancel_outlined,
    'approved' || 'received' => Icons.local_shipping_outlined,
    _ => Icons.schedule_outlined,
  };

  Color _tone(ThemeData theme) => switch (request.status) {
    'rejected' => theme.colorScheme.error,
    'refunded' => theme.colorScheme.primary,
    _ => theme.colorScheme.onSurfaceVariant,
  };

  List<String> _lines(BuildContext context) {
    final at = request.createdAt;
    return [
      if (request.number.isNotEmpty) 'Request ${request.number}',
      if (at != null) 'Raised on ${_date(at)}',
      if (request.reason.isNotEmpty)
        'Reason: ${request.reason.replaceAll('_', ' ')}',
      if (request.details case final details? when details.isNotEmpty) details,
      // The refund line, and only what the shop has actually said about it.
      if (request.isRefunded)
        'Refunded${_amount()}'
      else if (request.status == 'approved' || request.status == 'received')
        'Refund is being processed'
      else if (request.status == 'pending')
        'Refund decided once the request is reviewed',
    ];
  }

  String _amount() {
    final amount = request.refundAmount;
    return amount == null ? '' : ': Rs. ${amount.round()}';
  }

  static String _date(DateTime at) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${at.day} ${months[at.month - 1]} ${at.year}';
  }
}

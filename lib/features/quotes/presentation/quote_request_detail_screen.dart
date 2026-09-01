import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/quote_repository.dart';

/// One quote request, opened from the list.
///
/// The row it came from is painted immediately and the full record is fetched
/// behind it by its own id, so the screen is never blank and never shows a
/// different request than the one that was tapped.
class QuoteRequestDetailScreen extends StatefulWidget {
  const QuoteRequestDetailScreen({super.key, required this.request});

  final QuoteRequest request;

  @override
  State<QuoteRequestDetailScreen> createState() =>
      _QuoteRequestDetailScreenState();
}

class _QuoteRequestDetailScreenState extends State<QuoteRequestDetailScreen> {
  late QuoteRequest _request = widget.request;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Best effort: the list already handed over everything the card showed, so
  /// a failure here costs the extra detail and not the screen.
  Future<void> _load() async {
    try {
      final full = await QuoteRepository.instance.byId(widget.request.id);
      if (!mounted) return;
      setState(() {
        // The id is the one that was asked for; a body without it is not an
        // answer about this request.
        if (full.id == widget.request.id) _request = full;
        _loading = false;
      });
    } on ApiError {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = _request;
    final quoted = request.quotedPrice;

    return Scaffold(
      appBar: AppBar(title: const Text('Quote request')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: ArtworkPanel(
                  icon: Icons.request_quote_outlined,
                  tint: theme.colorScheme.primary,
                  imageUrl: request.imageUrl,
                  iconScale: 0.4,
                  knownWidth: 72,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  request.title.isEmpty ? 'Quote request' : request.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          _Row(
            label: 'Status',
            child: Text(
              request.statusLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: request.status.isAnswered
                    ? AppColors.successInk
                    : request.status.isDeclined
                    ? theme.colorScheme.error
                    : AppColors.commerceOrange,
              ),
            ),
          ),
          if (quoted != null)
            _Row(
              label: 'Quoted price',
              child: Text(
                formatRupees(quoted),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (request.askedPrice != null && request.askedPrice!.isNotEmpty)
            _Row(label: 'Listed price', child: Text(request.askedPrice!)),
          if (request.quantity != null)
            _Row(label: 'Quantity', child: Text('${request.quantity}')),
          if (request.seller != null && request.seller!.isNotEmpty)
            _Row(label: 'Seller', child: Text(request.seller!)),
          if (request.createdAt != null)
            _Row(
              label: 'Requested',
              child: Text(formatDay(request.createdAt!)),
            ),
          _Row(
            label: 'Reference',
            child: Text(
              request.id,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          if (request.lastMessage != null &&
              request.lastMessage!.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Latest message',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(request.lastMessage!),
              ),
            ),
          ],

          if (_loading) ...[
            const SizedBox(height: 20),
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled line of the record.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/support_repository.dart';
import 'create_ticket_sheet.dart';
import 'ticket_detail_screen.dart';

/// Every conversation this shopper has with support.
///
/// A list of threads rather than a single chat window, because that is what the
/// backend models: each ticket is its own conversation with its own subject and
/// status, and collapsing them into one stream would lose which reply belongs
/// to which problem.
class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  List<SupportTicket> _tickets = const [];
  bool _loading = true;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tickets = await SupportRepository.instance.listMine();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _startNew() async {
    final created = await CreateTicketSheet.show(context);
    if (created == null || !mounted) return;
    // Straight into the new thread: somebody who has just written a message
    // wants to see it sent, not a list with one more row on it.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TicketDetailScreen(ticket: created)),
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNew,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New message'),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
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
      return ListView(
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.all(24),
            child: LoadFailed(
              message: error.isNetwork
                  ? 'No connection. Check your network and try again.'
                  : error.message,
              onRetry: _load,
            ),
          ),
        ],
      );
    }

    if (_tickets.isEmpty) {
      return ListView(children: const [SizedBox(height: 100), _NoTickets()]);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: _tickets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _TicketCard(
        ticket: _tickets[i],
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TicketDetailScreen(ticket: _tickets[i]),
            ),
          );
          if (mounted) unawaited(_load());
        },
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});

  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updated = ticket.updatedAt ?? ticket.createdAt;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.subject.isEmpty
                          ? 'Support request'
                          : ticket.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(ticket: ticket),
                ],
              ),
              if (ticket.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  ticket.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  // Expanded, not fixed: "Shipping & delivery" beside a
                  // timestamp overflows a 360pt phone by 28 points, and the
                  // category is the half worth truncating -- the time is
                  // short, and it is what says whether anyone has replied.
                  Expanded(
                    child: Text(
                      ticket.categoryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (updated != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      formatRelative(updated),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the ticket has got to, in the shopper's own terms.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Waiting on the shopper is the one status worth colouring, because it is
    // the only one that asks them to do something.
    final needsYou = ticket.status == 'waiting_customer';
    final colour = needsYou
        ? AppColors.accent
        : ticket.isOpen
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

class _NoTickets extends StatelessWidget {
  const _NoTickets();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(
            Icons.forum_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No messages yet',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ask about an order, a refund, or anything else '
            'and support will reply here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

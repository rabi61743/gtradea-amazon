import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../notifications/data/notification_store.dart';
import '../data/support_repository.dart';
import '../data/thread_reads.dart';
import '../data/ticket_status_config.dart';
import 'create_ticket_sheet.dart';
import 'ticket_detail_screen.dart';

/// Every conversation this shopper has with support.
///
/// A list of threads rather than a single chat window, because that is what the
/// backend models: each ticket is its own conversation with its own subject and
/// status, and collapsing them into one stream would lose which reply belongs
/// to which problem.
///
/// Drawn as an inbox: one row per conversation, separated by a hairline rather
/// than boxed in a card. The card treatment cost 14 points of padding and a 10
/// point gap on every row -- roughly a third of the list's height spent on
/// borders around threads that are already obviously separate.
class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  List<SupportTicket> _tickets = const [];
  bool _loading = true;
  ApiError? _error;

  final _search = TextEditingController();
  String _query = '';

  /// The status the filter row is on, or null for all of them.
  ///
  /// Held as the server's own token rather than as an enum: the set of states
  /// is the shop's to change, and an enum here would be this app deciding
  /// which of them are allowed to exist.
  String? _status;

  /// When this device last opened each thread. See [ThreadReads]: the server
  /// keeps no read state, so this is where "unread" comes from.
  Map<String, DateTime> _reads = const {};

  /// The last line of each conversation, once it has been read off the server.
  final Map<String, _Preview> _previews = {};

  /// Threads whose messages are in flight, so a rebuild does not ask twice.
  final Set<String> _fetching = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // A support reply is raised by the shop, lands in the notification feed,
    // and that feed is already refreshed by the live socket in `home_screen`.
    // Listening to it is how this list learns that a thread has moved without
    // the shopper pulling to refresh -- and without opening a second socket or
    // inventing an event this server has never been shown to send.
    NotificationStore.instance.addListener(_onNotifications);
  }

  @override
  void dispose() {
    NotificationStore.instance.removeListener(_onNotifications);
    _search.dispose();
    super.dispose();
  }

  /// The newest support notification this list has already reacted to.
  ///
  /// Without it every unrelated change to the feed -- an order notification,
  /// a read being marked -- would re-fetch the whole ticket list.
  String? _lastSupportNotification;

  void _onNotifications() {
    if (!mounted) return;
    final latest = NotificationStore.instance.items
        .where((item) => item.category == NotificationCategory.support)
        .firstOrNull;
    if (latest == null || latest.id == _lastSupportNotification) return;
    _lastSupportNotification = latest.id;
    // Statuses, unread counts and timestamps all come from the same re-read,
    // so they cannot disagree with each other afterwards.
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The shop's status configuration, where it has one. Loaded once per
      // run and never fatal: [TicketStatusConfig.load] swallows its own
      // failures, so a list that cannot read it still opens.
      await TicketStatusConfig.instance.load();
      final tickets = await SupportRepository.instance.listMine();
      final reads = await ThreadReads.all();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _reads = reads;
        _loading = false;
        // Dropped rather than kept: a refresh is exactly when a thread has a
        // new last line, and showing yesterday's under a fresh list would be
        // the stalest thing on the screen.
        _previews.clear();
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Reads one thread's messages, for its preview and unread count.
  ///
  /// Only for rows that actually build, and once each: the list endpoint
  /// carries no last message, so the real one has to be fetched per thread, and
  /// fetching every thread on open would be a request per conversation for
  /// lines mostly below the fold.
  void _ensurePreview(SupportTicket ticket) {
    if (_previews.containsKey(ticket.id) || _fetching.contains(ticket.id)) {
      return;
    }
    _fetching.add(ticket.id);
    unawaited(() async {
      try {
        final messages = await SupportRepository.instance.messages(ticket.id);
        if (!mounted) return;
        setState(() {
          _previews[ticket.id] = _Preview.from(
            messages,
            readAt: _reads[ticket.id],
          );
        });
      } on ApiError {
        // A preview that cannot be read leaves the row showing the ticket's
        // own opening line. The conversation still opens.
      } finally {
        _fetching.remove(ticket.id);
      }
    }());
  }

  Future<void> _open(SupportTicket ticket) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TicketDetailScreen(ticket: ticket)),
    );
    // Stamped on the way out rather than on the way in, so a reply that lands
    // while the thread is open is not marked read before it has been seen.
    await ThreadReads.markOpened(ticket.id);
    if (mounted) unawaited(_load());
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

  /// The conversations the search leaves, in the order the server sent them.
  ///
  /// Filtered here rather than asked for: `/support/tickets` returns this
  /// account's threads in one unpaged response and takes no query parameter,
  /// so there is nothing to ask. Sending a `q` the server ignored would draw
  /// every thread under a search box that claimed to have filtered them.
  List<SupportTicket> get _visible {
    final query = _query.trim().toLowerCase();
    final status = _status;
    return _tickets.where((ticket) {
      if (status != null && ticket.status.toLowerCase() != status) return false;
      if (query.isEmpty) return true;
      return _matches(ticket, query);
    }).toList();
  }

  /// The states this account's conversations are actually in.
  ///
  /// Derived from the tickets in hand rather than from a list of what might
  /// exist, so there is never a tab that matches nothing and never a state
  /// without one.
  List<TicketStatusStyle> get _statusFilters =>
      TicketStatusConfig.instance.filtersFor(_tickets.map((t) => t.status));

  /// Everything about a conversation that is worth searching: what it is
  /// called, what was asked, its reference, what it is filed under, where it
  /// has got to -- and its last line, for threads that have one loaded.
  bool _matches(SupportTicket ticket, String query) => [
    ticket.subject,
    ticket.description,
    ticket.ticketNumber,
    ticket.categoryLabel,
    ticket.statusLabel,
    _previews[ticket.id]?.text ?? '',
  ].any((field) => field.toLowerCase().contains(query));

  @override
  Widget build(BuildContext context) {
    // The box is worth showing whenever there is a list to narrow, and while a
    // query is in it even if that query currently matches nothing -- a search
    // field that vanishes with its own results cannot be corrected or cleared.
    final searchable =
        !_loading &&
        _error == null &&
        (_tickets.isNotEmpty || _query.isNotEmpty || _status != null);

    // Only worth a row of its own once there is more than one state to choose
    // between: a single chip beside "All" is two ways of saying the same list.
    final filters = searchable ? _statusFilters : const <TicketStatusStyle>[];
    final showFilters = filters.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        bottom: searchable
            ? PreferredSize(
                preferredSize: Size.fromHeight(showFilters ? 96 : 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SearchBox(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    if (showFilters)
                      _StatusFilters(
                        filters: filters,
                        selected: _status,
                        onSelected: (token) =>
                            setState(() => _status = token),
                      ),
                  ],
                ),
              )
            : null,
      ),
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

    final visible = _visible;
    if (visible.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          _NoMatches(
            query: _query,
            status: _status == null
                ? null
                : TicketStatusConfig.instance.styleFor(_status!).label,
          ),
        ],
      );
    }

    return ListView.separated(
      // No top padding and none at the sides: the rows run edge to edge like
      // an inbox, and their own padding is what keeps the type off the frame.
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        thickness: 1,
        // Indented past the avatar, so the line separates the text and reads
        // as one list rather than as a stack of boxes.
        indent: 60,
      ),
      itemBuilder: (context, i) {
        final ticket = visible[i];
        _ensurePreview(ticket);
        return _ConversationRow(
          ticket: ticket,
          preview: _previews[ticket.id],
          onTap: () => unawaited(_open(ticket)),
        );
      },
    );
  }
}

/// One conversation's last line, worked out from its real messages.
class _Preview {
  const _Preview({required this.text, required this.mine, this.at, this.unread = 0});

  /// What was last said, without the "You: " the row adds.
  final String text;

  /// Whether the shopper said it. The row prefixes their own lines, the way a
  /// chat inbox does, so it is plain whether they are waiting or support is.
  final bool mine;

  final DateTime? at;

  /// Support replies stamped later than the last time this device opened the
  /// thread. See [ThreadReads] for why this is worked out rather than received.
  final int unread;

  factory _Preview.from(List<SupportMessage> messages, {DateTime? readAt}) {
    final last = messages.lastOrNull;
    if (last == null) {
      return const _Preview(text: '', mine: false);
    }
    // Anything stamped before the marker has been seen; with no marker there
    // is no evidence any of it has been, so all of it counts.
    final since = readAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final unread = messages
        .where((m) => !m.isMine)
        .where((m) => (m.createdAt ?? since).isAfter(since))
        .length;

    return _Preview(
      // The same one-line summary a quoted message gets, so a thread whose
      // last message is a photo reads as "Photo" rather than "(attachment)".
      text: quotedSummary(last),
      mine: last.isMine,
      at: last.createdAt,
      unread: unread,
    );
  }
}

/// A conversation, as one compact row.
///
/// Two lines and an avatar: the subject and when it last moved, then who said
/// what last and how much of it is unread. Everything else the shopper needs at
/// a glance rides in the avatar's icon -- what the thread is about -- so naming
/// the category costs no vertical space at all.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.ticket,
    required this.preview,
    required this.onTap,
  });

  final SupportTicket ticket;
  final _Preview? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = preview?.unread ?? 0;
    final status = TicketStatusConfig.instance.styleFor(ticket.status);
    // The dot on the avatar marks a thread the shopper is being waited on for.
    // Read from the status's own colour rather than from its name: the shop
    // decides which states are urgent, and the accent is what it uses to say so.
    final needsYou = status.colourOn(theme) == AppColors.accent;

    // The thread's own last message where it has been read, the opening line
    // until then -- which is what the server puts on the ticket itself, and is
    // genuinely the first thing said in the conversation.
    final line = preview?.text.isNotEmpty == true
        ? (preview!.mine ? 'You: ${preview!.text}' : preview!.text)
        : ticket.description;

    final at = preview?.at ?? ticket.updatedAt ?? ticket.createdAt;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CategoryAvatar(ticket: ticket, needsYou: needsYou),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          ticket.subject.isEmpty
                              ? 'Support request'
                              : ticket.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            // Heavier while something is waiting to be read,
                            // the way an inbox marks a thread rather than by
                            // adding a second badge to the row.
                            fontWeight: unread > 0
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (at != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatRelative(at),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: unread > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      // Whatever state the server says this conversation is
                      // in, named and coloured by the shop's configuration
                      // where it has one. On the line the preview was already
                      // using, as words rather than a filled pill, so it costs
                      // the row no height and adds no container.
                      if (status.label.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            status.label,
                            // Keyed because the filter row above can carry a
                            // chip with exactly these words, and "the tag on
                            // this conversation" and "the chip for that state"
                            // are different claims about the screen.
                            key: const ValueKey('status-tag'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: status.colourOn(theme),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '  ·  ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          line.isEmpty ? ticket.categoryLabel : line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unread > 0
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: unread > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadBadge(count: unread),
                      ],
                    ],
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

/// What the conversation is about, as an icon.
///
/// The category is the only product-or-order context the ticket record
/// actually carries, and drawn here it costs no line of its own. A closed
/// thread is drawn back, so a finished conversation reads as finished without
/// a label saying so.
class _CategoryAvatar extends StatelessWidget {
  const _CategoryAvatar({required this.ticket, required this.needsYou});

  final SupportTicket ticket;
  final bool needsYou;

  static IconData iconFor(String category) => switch (category) {
    'order' => Icons.receipt_long_outlined,
    'shipping' => Icons.local_shipping_outlined,
    'returns' => Icons.assignment_return_outlined,
    'payment' => Icons.payments_outlined,
    'product' => Icons.inventory_2_outlined,
    'account' => Icons.person_outline,
    'technical' => Icons.build_outlined,
    _ => Icons.forum_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = ticket.isOpen;
    final ink = live
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconFor(ticket.category),
              size: 19,
              color: ink,
              semanticLabel: ticket.categoryLabel,
            ),
          ),
          if (needsYou)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How many replies are waiting.
///
/// Trust Blue rather than the accent: the brand reserves Commerce Orange for
/// the one thing on a screen meant to be pressed, and a badge on every unread
/// row is not that.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        // A thread with a great many unread replies is still just "lots".
        count > 99 ? '99+' : '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// The search box, under the title.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            hintText: 'Search messages',
            prefixIcon: const Icon(Icons.search, size: 18),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Clear search',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// A search that matched none of this account's conversations.
/// The filter row: every state this account's conversations are in.
///
/// Built from the tickets in hand, in the shop's own order where it configures
/// one. Chips rather than tabs, and scrolled horizontally, because the number
/// of states is the backend's to decide and a fixed tab bar would have to
/// assume it.
class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  final List<TicketStatusStyle> filters;

  /// The chosen status token, or null for all.
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      // Every chip built, not just the ones that fit.
      //
      // A lazy `ListView` builds what the viewport asks for, which on a narrow
      // phone quietly dropped the last state off the end: with a long label
      // like "Awaiting your reply" in the row, "Closed" was never built at all.
      // A filter row missing a state the shopper actually has is worse than one
      // they have to scroll -- they cannot reach what is not there.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            _chip(context, label: 'All', token: null),
            for (final status in filters)
              _chip(context, label: status.label, token: status.token),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required String? token,
  }) {
    final isSelected =
        token == null ? selected == null : selected == token.toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // Tapping the chosen one again clears it, so "All" is never the only
        // way back to the whole list.
        onSelected: (_) =>
            onSelected(isSelected ? null : token?.toLowerCase()),
      ),
    );
  }
}

/// Nothing left after the search, the status filter, or the two together.
class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, this.status});

  final String query;

  /// The status being filtered on, named the way the row names it.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = query.trim();
    final title = switch ((trimmed.isEmpty, status)) {
      (true, final state?) => 'Nothing is $state',
      (false, final state?) => 'No $state message matches "$trimmed"',
      _ => 'No messages match "$trimmed"',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status == null
                ? 'Try a different word, or part of a ticket number.'
                : 'Try another status, or All.',
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../catalog/presentation/browse_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/quote_repository.dart';
import 'inquiry_filter.dart';
import 'quote_request_detail_screen.dart';

/// Every product inquiry this shopper has raised with a seller.
///
/// Read from `/product-requests`, which is the same list the storefront shows
/// and is scoped by the server to the caller's own session. There is no id in
/// the request, so there is no route from this screen to anybody else's.
class QuoteRequestsScreen extends StatefulWidget {
  const QuoteRequestsScreen({super.key});

  /// The page is laid out for a phone. On a tablet or a desktop window it
  /// keeps that measure and centres, rather than stretching a 56pt thumbnail
  /// across a metre of glass.
  static const maxContentWidth = 640.0;

  @override
  State<QuoteRequestsScreen> createState() => _QuoteRequestsScreenState();
}

class _QuoteRequestsScreenState extends State<QuoteRequestsScreen> {
  List<QuoteRequest> _requests = const [];
  bool _loading = true;
  ApiError? _error;

  InquiryFilter _filter = InquiryFilter.all;

  final _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AuthStore.instance.isSignedIn) {
      setState(() {
        _requests = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await QuoteRepository.instance.listMine();
      if (!mounted) return;
      setState(() {
        _requests = requests;
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

  Future<void> _signIn() async {
    final signedIn = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const AuthScreen()));
    if (signedIn == true && mounted) await _load();
  }

  void _open(QuoteRequest request) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuoteRequestDetailScreen(request: request),
      ),
    );
  }

  /// Where "New Inquiry" goes.
  ///
  /// An inquiry is always about a listing -- `/product-requests` will not take
  /// one without a product id -- so the only honest thing this button can do
  /// is help the shopper find the product and ask from its page, which is the
  /// flow that already exists. It does not open a form the server would refuse.
  void _newInquiry() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BrowseScreen()));
  }

  /// What the search box leaves, before the tab narrows it further.
  ///
  /// Over the list already in hand: the endpoint takes no query, and a search
  /// that went to the server would be a second, slower list that could
  /// disagree with the counts on the tabs.
  List<QuoteRequest> get _found {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _requests;
    return [
      for (final request in _requests)
        if (request.title.toLowerCase().contains(query) ||
            request.id.toLowerCase().contains(query) ||
            (request.lastMessage ?? '').toLowerCase().contains(query))
          request,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                textAlignVertical: TextAlignVertical.center,
                decoration: const InputDecoration(
                  hintText: 'Search inquiries',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : Text(
                'Product Inquiry',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search.clear();
                _query = '';
              }
            }),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: QuoteRequestsScreen.maxContentWidth,
            ),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (!AuthStore.instance.isSignedIn) {
      return _Message(
        icon: Icons.lock_outline,
        text: 'Log in to see your product inquiries and replies.',
        actionLabel: 'Sign in',
        onAction: _signIn,
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    final error = _error;
    if (error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: error.isNetwork
            ? 'No connection, so your inquiries could not be loaded.'
            : error.message,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    final found = _found;
    final shown = [
      for (final request in found)
        if (_filter.covers(request.status)) request,
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        // At the top of the page, above the tabs and the list: it is the way
        // in for somebody whose product is not in the catalogue at all, and
        // that is a thing to offer before the list of what they already asked.
        _SourcingBanner(onNewInquiry: _newInquiry),
        if (_requests.isNotEmpty)
          _FilterStrip(
            selected: _filter,
            counts: {
              for (final filter in InquiryFilter.values)
                filter: filter.count(found),
            },
            onSelected: (filter) => setState(() => _filter = filter),
          ),
        if (shown.isEmpty)
          _EmptyNote(
            text: _requests.isEmpty
                ? "You haven't raised any product inquiries yet."
                : 'No inquiries here.',
          )
        else
          for (final request in shown)
            _InquiryCard(request: request, onTap: () => _open(request)),
      ],
    );
  }
}

/// The status tabs, with what each one holds.
class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final InquiryFilter selected;
  final Map<InquiryFilter, int> counts;
  final ValueChanged<InquiryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          for (final filter in InquiryFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _FilterChip(
                label: '${filter.label} (${counts[filter] ?? 0})',
                selected: filter == selected,
                onTap: () => onSelected(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? AppColors.commerceOrange.withValues(alpha: 0.12)
          : AppColors.mountainGrey.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? AppColors.commerceOrange
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The sourcing banner, as the shop's own artwork draws it.
///
/// One supplied image rather than a rebuild of it: the headline, the mascot,
/// the handwriting and the glyph tiles are one composition, and a version of
/// it assembled from text and a logo would be a lookalike that drifts from
/// the file every time either changes.
///
/// The whole banner is the button. "New Inquiry" is painted into the artwork,
/// so a tap anywhere on it does what that painted button says -- there is no
/// live control here to miss, and none to disagree with the picture.
class _SourcingBanner extends StatelessWidget {
  const _SourcingBanner({required this.onNewInquiry});

  final VoidCallback onNewInquiry;

  /// The artwork, and the shape it was drawn at (1600 x 561).
  static const art = 'assets/images/inquiry_banner.jpg';
  static const ratio = 1600 / 561;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // What the banner says, for somebody who cannot see it: the words are
      // painted into the image and are not text this app can read out.
      label:
          "Can't find what you're looking for? Send us an inquiry and we'll "
          'source it for you. New inquiry.',
      excludeSemantics: true,
      child: Material(
        color: AppColors.premiumIvory,
        child: InkWell(
          onTap: onNewInquiry,
          child: SizedBox(
            width: double.infinity,
            child: AspectRatio(
              // Its own proportions, so the artwork is never stretched: the
              // banner is as tall as the page is wide, whatever the device.
              aspectRatio: ratio,
              child: Image.asset(
                art,
                // Fills the width and keeps its shape, which is what the
                // aspect ratio above has already reserved.
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                // A banner that could not be decoded is a banner that is not
                // there; the tabs and the list below it are the page.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One inquiry: its picture, what was asked about, when, and where it stands.
class _InquiryCard extends StatelessWidget {
  const _InquiryCard({required this.request, required this.onTap});

  final QuoteRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quoted = request.quotedPrice;
    final raised = request.createdAt;
    final message = request.lastMessage;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // 97% of whatever it is given, centred: the margin is a share of the
      // page rather than a fixed inset, so the same card sits right on a
      // phone, a tablet and a desktop window.
      child: FractionallySizedBox(
        widthFactor: 0.97,
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: ArtworkPanel(
                          icon: Icons.request_quote_outlined,
                          tint: theme.colorScheme.primary,
                          imageUrl: request.imageUrl,
                          iconScale: 0.4,
                          knownWidth: 56,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    request.title.isEmpty
                                        ? 'Product inquiry'
                                        : request.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _StatusChip(request: request),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (raised != null)
                                  'Inquired on ${formatCalendarDate(raised)}'
                                else
                                  'Inquiry raised',
                                if (request.quantity != null)
                                  'Qty ${request.quantity}',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (quoted != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Quoted ${formatRupees(quoted)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                            if (message != null && message.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.mountainGrey.withValues(
                                    alpha: 0.45,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  message,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  // No rule above this row: the card's own border already
                  // closes the block, and the line only cut it in half.
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        // The server's own reference for this inquiry, as it
                        // wrote it. A prettier number invented here is not one
                        // anybody could quote back to the shop.
                        child: Text(
                          '#${request.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'View Details',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.commerceOrange,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: AppColors.commerceOrange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the inquiry stands, in the shop's own words.
///
/// The words are the server's status, not the tab's: a request the queue calls
/// "Approved" is not made clearer by printing "Quoted" over it. The colour is
/// the tab's, so a scan down the list groups the way the tabs do.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.request});

  final QuoteRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = request.status;
    final colour = status.isAnswered
        ? AppColors.successInk
        : status.isDeclined
        ? theme.colorScheme.onSurfaceVariant
        : AppColors.trustBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        request.statusLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 11,
          color: colour,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Nothing in this tab, or nothing at all -- said inside the list, so the
/// banner above it stays put and the filter can be changed back.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
      child: Column(
        children: [
          Icon(
            Icons.request_quote_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The signed-out and failed states, which differ only in what they say.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      // A list, so the pull-to-refresh above still works on an empty screen.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Icon(icon, size: 46, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}

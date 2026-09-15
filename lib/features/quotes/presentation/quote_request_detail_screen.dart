import 'dart:async';

import 'package:flutter/material.dart';

import '../../product/presentation/product_detail_screen.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/browse_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../home/widgets/product_carousel.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../search/presentation/search_results_screen.dart';
import '../../support/data/support_attachment.dart';
import '../../support/presentation/message_attachment.dart';
import '../data/quote_repository.dart';
import 'inquiry_stage.dart';

/// One inquiry, opened from the list.
///
/// The row it came from is painted immediately and the full record is fetched
/// behind it by its own id, so the screen is never blank and never shows a
/// different inquiry than the one that was tapped. The thread and its files
/// come from `/product-requests/{id}/messages`, which is where the shop keeps
/// them; nothing on this page is held anywhere else.
class QuoteRequestDetailScreen extends StatefulWidget {
  const QuoteRequestDetailScreen({super.key, required this.request});

  final QuoteRequest request;

  /// Phone measure, centred on anything wider.
  static const maxContentWidth = 640.0;

  @override
  State<QuoteRequestDetailScreen> createState() =>
      _QuoteRequestDetailScreenState();
}

class _QuoteRequestDetailScreenState extends State<QuoteRequestDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  late QuoteRequest _request = widget.request;
  bool _loading = true;

  List<QuoteMessage> _messages = const [];
  bool _loadingMessages = true;

  List<Product> _recommended = const [];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    unawaited(_load());
    unawaited(_loadMessages());
    unawaited(_loadRecommended());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Best effort: the list already handed over everything the card showed, so
  /// a failure here costs the extra detail and not the screen.
  Future<void> _load() async {
    try {
      final full = await QuoteRepository.instance.byId(widget.request.id);
      if (!mounted) return;
      setState(() {
        // The id is the one that was asked for; a body without it is not an
        // answer about this inquiry.
        if (full.id == widget.request.id) _request = full;
        _loading = false;
      });
    } on ApiError {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMessages() async {
    try {
      final rows = await QuoteRepository.instance.messages(widget.request.id);
      if (!mounted) return;
      setState(() {
        _messages = rows;
        _loadingMessages = false;
      });
    } on ApiError {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  /// Products like the one that was asked about.
  ///
  /// The catalogue's own search, on the inquiry's title. A shelf of whatever
  /// happened to be popular would not be a recommendation about this inquiry.
  Future<void> _loadRecommended() async {
    final words = _request.title.split(RegExp(r'\s+')).take(6).join(' ').trim();
    if (words.isEmpty) return;
    try {
      final products = await CatalogRepository.instance.search(
        query: words,
        pageSize: 12,
      );
      if (!mounted || products.isEmpty) return;
      setState(() => _recommended = products.take(8).toList(growable: false));
    } on ApiError {
      // A shelf that did not load is a shelf that is not shown.
    }
  }

  /// Everything attached anywhere on the thread, newest message last.
  List<String> get _attachments => [
    for (final message in _messages) ...message.attachments,
  ];

  /// How many quotes there are: the one the seller sent, or none yet.
  int get _quoteCount => _request.quotedPrice == null ? 0 : 1;

  void _copyReference() {
    Clipboard.setData(ClipboardData(text: _request.id));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Inquiry reference copied')));
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadingMessages = true;
    });
    await Future.wait([_load(), _loadMessages()]);
  }

  void _browse() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BrowseScreen()));
  }

  void _addToCart(Product product) {
    CartStore.instance.add(
      CartLine(
        productId: product.numIid,
        title: product.title,
        unitPrice: product.displayPrice ?? 0,
        imageUrl: product.imageUrl,
        category: product.categoryName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Inquiry Details',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // Back to the product itself -- the way to buy it once the shop says
          // it can be ordered. Only where the server says which product this
          // is; a guess by title could open the wrong one.
          if (_request.sourceId != null)
            IconButton(
              icon: const Icon(Icons.storefront_outlined),
              tooltip: 'View product',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailScreen(
                    product: productStub(
                      numIid: _request.sourceId!,
                      title: _request.title,
                      imageUrl: _request.imageUrl,
                    ),
                  ),
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'copy') _copyReference();
              if (value == 'refresh') unawaited(_refresh());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy reference')),
              PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            ],
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: QuoteRequestDetailScreen.maxContentWidth,
          ),
          child: Column(
            children: [
              _HeaderCard(request: _request, onCopy: _copyReference),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.commerceOrange,
                indicatorColor: AppColors.commerceOrange,
                indicatorWeight: 2.5,
                dividerColor: theme.colorScheme.outlineVariant,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                labelStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  const Tab(text: 'Overview'),
                  const Tab(text: 'Messages'),
                  Tab(text: 'Quotes ($_quoteCount)'),
                  Tab(text: 'Attachments (${_attachments.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [_overview(), _thread(), _quotes(), _files()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overview() {
    final request = _request;
    final attachments = _attachments;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          _StatusTimelineCard(request: request),
          const SizedBox(height: 12),
          _DetailsCard(request: request, message: _openingMessage),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            _AttachmentsCard(
              keys: attachments,
              onViewAll: () => _tabs.animateTo(3),
            ),
          ],
          if (_recommended.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.recommend_outlined,
              title: 'Recommended for You',
              padded: false,
              action: 'See More',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchResultsScreen(query: request.title),
                ),
              ),
              child: SizedBox(
                height: ProductCarousel.heightFor(context),
                child: ProductCarousel(
                  title: '',
                  products: _recommended,
                  onAddToCart: _addToCart,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Measure(
            child: OutlinedButton.icon(
              onPressed: _browse,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.commerceOrange,
                side: const BorderSide(color: AppColors.commerceOrange),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text(
                'Submit Another Inquiry',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Measure(
            child: FilledButton.icon(
              onPressed: () => _tabs.animateTo(1),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.commerceOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text(
                'Chat with Our Sourcing Team',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'We typically respond within 24 hours.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
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

  /// What the shopper asked for, in their own words.
  ///
  /// The first thing they said on the thread, falling back to the summary the
  /// list carries when the thread has not loaded.
  String? get _openingMessage {
    for (final message in _messages) {
      if (message.fromShopper && message.message.isNotEmpty) {
        return message.message;
      }
    }
    return _request.lastMessage;
  }

  Widget _thread() => _MessagesTab(
    requestId: _request.id,
    messages: _messages,
    loading: _loadingMessages,
    onSent: _loadMessages,
  );

  Widget _quotes() {
    final theme = Theme.of(context);
    final quoted = _request.quotedPrice;

    if (quoted == null) {
      return _Note(
        icon: Icons.request_quote_outlined,
        text: 'No quote yet. We will let you know as soon as one arrives.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        _SectionCard(
          icon: Icons.request_quote_outlined,
          title: 'Quotation',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatRupees(quoted),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _request.quantity == null
                    ? 'Quoted by our sourcing team.'
                    : 'Quoted for ${_request.quantity} units.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _files() {
    final keys = _attachments;
    if (_loadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }
    if (keys.isEmpty) {
      return const _Note(
        icon: Icons.attach_file,
        text: 'Nothing has been attached to this inquiry yet.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Measure(
              child: MessageAttachment(storageKey: key, onDark: false),
            ),
          ),
      ],
    );
  }
}

/// The width every block on this page is drawn to.
///
/// 97% of whatever the page gives it, centred, so the air either side is a
/// share of the screen rather than a fixed inset -- the same card sits right
/// on a phone, a tablet and a desktop window.
class _Measure extends StatelessWidget {
  const _Measure({required this.child});

  final Widget child;

  static const widthFactor = 0.97;

  @override
  Widget build(BuildContext context) =>
      FractionallySizedBox(widthFactor: widthFactor, child: child);
}

/// The inquiry itself: its picture, what it is about, and its reference.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.request, required this.onCopy});

  final QuoteRequest request;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raised = request.createdAt;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: _Measure(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      request.title.isEmpty ? 'Product inquiry' : request.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '#${request.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: onCopy,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.copy_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            // The reference's copy control, and it copies the
                            // reference the shop actually issued.
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _StatusChip(request: request),
                    if (raised != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Inquired on ${formatCalendarDate(raised)}, '
                        '${formatTime(raised)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the inquiry stands, in the shop's own words.
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

/// A titled white card, which is what every block on this page is.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.action,
    this.onAction,
    this.padded = true,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;

  /// False where the child runs to the card's edges, as a rail does.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Measure(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.commerceOrange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: AppColors.commerceOrange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (action != null && onAction != null)
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.commerceOrange,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        action!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.commerceOrange,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: padded
                  ? const EdgeInsets.fromLTRB(14, 12, 14, 14)
                  : const EdgeInsets.only(top: 12, bottom: 14),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// The four steps, and how far this inquiry has got.
class _StatusTimelineCard extends StatelessWidget {
  const _StatusTimelineCard({required this.request});

  final QuoteRequest request;

  @override
  Widget build(BuildContext context) {
    final current = InquiryStage.of(request.status);

    return _SectionCard(
      icon: Icons.timeline,
      title: 'Inquiry Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final stage in InquiryStage.values)
            _StageRow(
              stage: stage,
              current: current,
              last: stage == InquiryStage.values.last,
              // Only the first step has a time the server actually recorded.
              at: stage == InquiryStage.submitted ? request.createdAt : null,
              detail:
                  stage == InquiryStage.quotation && request.quotedPrice != null
                  ? 'Quoted ${formatRupees(request.quotedPrice!)}.'
                  : stage.detail,
            ),
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.current,
    required this.last,
    required this.detail,
    this.at,
  });

  final InquiryStage stage;
  final InquiryStage current;
  final bool last;
  final String detail;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNow = stage == current;
    final done = stage.isBefore(current);
    final reached = isNow || done;

    final mark = reached ? AppColors.commerceOrange : AppColors.mountainGrey;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isNow ? Colors.transparent : mark,
                  border: Border.all(color: mark, width: isNow ? 3.5 : 0),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: done ? AppColors.commerceOrange : mark,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: reached
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (at != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${formatCalendarDate(at!)}, ${formatTime(at!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.35,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What was asked for, as the record holds it.
///
/// Only the fields the shop actually keeps against an inquiry. The reference
/// also shows a category, a target price, a required-by date and a delivery
/// address; `/product-requests` stores none of those, and a row printed here
/// with nothing behind it would be a form the shopper never filled in.
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.request, this.message});

  final QuoteRequest request;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quoted = request.quotedPrice;
    final asked = request.askedPrice;
    final seller = request.seller;
    final raised = request.createdAt;

    return _SectionCard(
      icon: Icons.description_outlined,
      title: 'Your Inquiry Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(label: 'Product Name', value: request.title),
          if (request.quantity != null)
            _Field(label: 'Quantity', value: '${request.quantity} units'),
          if (asked != null && asked.isNotEmpty)
            _Field(label: 'Listed Price', value: asked),
          if (quoted != null)
            _Field(label: 'Quoted Price', value: formatRupees(quoted)),
          if (seller != null && seller.isNotEmpty)
            _Field(label: 'Supplier', value: seller),
          if (raised != null)
            _Field(
              label: 'Inquired On',
              value: '${formatCalendarDate(raised)}, ${formatTime(raised)}',
            ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 104,
                  child: Text(
                    'Message',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.mountainGrey.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.4,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The files on the thread, as tiles.
class _AttachmentsCard extends StatelessWidget {
  const _AttachmentsCard({required this.keys, required this.onViewAll});

  final List<String> keys;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = keys.length <= 4 ? keys : keys.sublist(0, 4);

    return _SectionCard(
      icon: Icons.attach_file,
      title: 'Attachments (${keys.length})',
      action: keys.length > shown.length ? 'View All' : null,
      onAction: keys.length > shown.length ? onViewAll : null,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final key in shown)
            SizedBox(
              width: 132,
              child: InkWell(
                onTap: onViewAll,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 72,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.mountainGrey.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        SupportAttachmentRepository.isImageKey(key)
                            ? Icons.image_outlined
                            : Icons.description_outlined,
                        color: AppColors.commerceOrange,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      SupportAttachmentRepository.fileNameFor(key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The thread, and the box to add to it.
class _MessagesTab extends StatefulWidget {
  const _MessagesTab({
    required this.requestId,
    required this.messages,
    required this.loading,
    required this.onSent,
  });

  final String requestId;
  final List<QuoteMessage> messages;
  final bool loading;
  final Future<void> Function() onSent;

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      await QuoteRepository.instance.sendMessage(widget.requestId, text);
      _text.clear();
      await widget.onSent();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = e.isNetwork
            ? 'No connection. Your message was not sent.'
            : e.message;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator())
              : widget.messages.isEmpty
              ? const _Note(
                  icon: Icons.forum_outlined,
                  text:
                      'No messages yet. Our team will reply with pricing '
                      'and availability.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    for (final message in widget.messages)
                      _Bubble(message: message),
                  ],
                ),
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              _problem!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.commerceOrange,
                    foregroundColor: Colors.white,
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One message on the thread, on the side that said it.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final QuoteMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.fromShopper;
    final at = message.sentAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: mine
                  ? AppColors.commerceOrange
                  : AppColors.mountainGrey.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mine ? 'You' : 'GtradeA',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: mine
                        ? Colors.white.withValues(alpha: 0.85)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.35,
                    color: mine ? Colors.white : theme.colorScheme.onSurface,
                  ),
                ),
                for (final key in message.attachments) ...[
                  const SizedBox(height: 8),
                  MessageAttachment(storageKey: key, onDark: mine),
                ],
                if (at != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    formatRelative(at),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      color: mine
                          ? Colors.white.withValues(alpha: 0.7)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An empty tab, said plainly.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
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
      ),
    );
  }
}

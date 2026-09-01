import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/quote_repository.dart';
import 'quote_request_detail_screen.dart';

/// Every quote this shopper has asked a seller for.
///
/// Read from `/product-requests`, which is the same list the storefront shows
/// and is scoped by the server to the caller's own session. There is no id in
/// the request, so there is no route from this screen to anybody else's.
class QuoteRequestsScreen extends StatefulWidget {
  const QuoteRequestsScreen({super.key});

  @override
  State<QuoteRequestsScreen> createState() => _QuoteRequestsScreenState();
}

class _QuoteRequestsScreenState extends State<QuoteRequestsScreen> {
  List<QuoteRequest> _requests = const [];
  bool _loading = true;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Quote Requests')),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (!AuthStore.instance.isSignedIn) {
      return _Message(
        icon: Icons.lock_outline,
        text: 'Log in to see your quote requests and replies.',
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
            ? 'No connection, so your quote requests could not be loaded.'
            : error.message,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_requests.isEmpty) {
      return _Message(
        icon: Icons.request_quote_outlined,
        text: "You haven't requested any quotes yet.",
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      itemCount: _requests.length,
      itemBuilder: (context, i) =>
          _RequestCard(request: _requests[i], onTap: () => _open(_requests[i])),
    );
  }
}

/// One request: its picture, what was asked about, when, and where it stands.
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onTap});

  final QuoteRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quoted = request.quotedPrice;
    final when = request.updatedAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
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
                    Text(
                      request.title.isEmpty ? 'Quote request' : request.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (request.lastMessage != null &&
                        request.lastMessage!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        request.lastMessage!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusChip(request: request),
                        if (quoted != null)
                          Text(
                            formatRupees(quoted),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        if (request.quantity != null)
                          _Muted('Qty ${request.quantity}'),
                        if (when != null) _Muted(formatDay(when)),
                      ],
                    ),
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

/// Where the request stands, in the shop's own words.
///
/// Three tones and no more: answered, declined, and everything still in
/// progress. A colour per status would make a queue of pending requests look
/// like a warning light.
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
        ? theme.colorScheme.error
        : AppColors.commerceOrange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        request.statusLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colour,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The empty, signed-out and failed states, which differ only in what they say.
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

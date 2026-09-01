import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../checkout/presentation/payment_methods_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../support/presentation/create_ticket_sheet.dart';
import '../../support/presentation/support_tickets_screen.dart';
import 'contact_support_screen.dart';
import '../data/help_content.dart';
import '../data/help_repository.dart';

/// The Help Center: search, quick actions, the published topics, and a way to
/// reach a human.
///
/// Every word of content here comes from the gateway -- the topics from
/// `/help/categories`, the results from `/help/articles`, the address from
/// `site-settings/support_email` -- so a shop that publishes an article sees it
/// without an app release. The quick actions go to screens this app already
/// has, rather than to the website routes the reference links to.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _search = TextEditingController();

  /// The shelf this app reads.
  ///
  /// Fixed rather than chosen: the toggle that picked between the shopper and
  /// developer shelves is gone, and this is a shopping app. The filter itself
  /// stays on the query, so the developer material the gateway holds does not
  /// leak into a shopper's results.
  static const _audience = HelpAudience.user;

  List<HelpCategory> _categories = const [];
  bool _loadingTopics = true;
  ApiError? _topicsError;

  String? _email;

  /// Null until something has been looked up, so an empty list is only ever
  /// shown for a search somebody actually made.
  List<HelpArticle>? _results;
  bool _searching = false;
  String _searched = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadTopics());
    unawaited(_loadEmail());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _loadingTopics = true;
      _topicsError = null;
    });
    try {
      final categories = await HelpRepository.instance.categories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loadingTopics = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _topicsError = e;
        _loadingTopics = false;
      });
    }
  }

  /// Best effort. A missing address costs the email button, not the page.
  Future<void> _loadEmail() async {
    try {
      final email = await HelpRepository.instance.supportEmail();
      if (mounted) setState(() => _email = email);
    } on ApiError {
      // Deliberately swallowed. See above.
    }
  }

  Future<void> _lookUp(Future<List<HelpArticle>> Function() fetch) async {
    setState(() => _searching = true);
    try {
      final found = await fetch();
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
      _say(e.message);
    }
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    _searched = query;
    await _lookUp(
      () => HelpRepository.instance.articles(
        search: query,
        audience: _audience,
        limit: 20,
      ),
    );
  }

  /// Shows what is filed under a topic, in the list the search already uses.
  Future<void> _openTopic(HelpCategory category) async {
    _searched = category.name;
    await _lookUp(
      () => HelpRepository.instance.articles(
        categorySlug: category.slug,
        audience: _audience,
        limit: 50,
      ),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// Opens a ticket on the existing support system, prefilled with what the
  /// shopper was asking about.
  ///
  /// The quick sheet where there is already a subject to carry -- an
  /// unanswered search, a return -- and the full Contact Support form where
  /// there is not, because that is the page that asks for the rest.
  Future<void> _submitTicket({String subject = ''}) async {
    if (subject.isEmpty) {
      _push(const ContactSupportScreen());
      return;
    }
    final created = await CreateTicketSheet.show(
      context,
      initialSubject: subject,
    );
    if (created != null && mounted) _push(const SupportTicketsScreen());
  }

  /// Puts the support address on the clipboard.
  ///
  /// Not a `mailto:` link: opening one needs a launcher package this app does
  /// not carry, and adding a dependency and its platform wiring for one button
  /// is a bigger change than the button is worth. Copying works on every
  /// device, cannot fail for want of a mail app, and leaves the shopper able to
  /// paste the address wherever they actually write from.
  Future<void> _copyEmail(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    _say('Support email copied');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Help Center')),
      body: RefreshIndicator(
        onRefresh: _loadTopics,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _Hero(
              controller: _search,
              searching: _searching,
              onSearch: _runSearch,
            ),
            const SizedBox(height: 24),
            if (_results != null) ...[
              _Results(
                query: _searched,
                articles: _results!,
                onClear: () => setState(() => _results = null),
                onAsk: () => _submitTicket(subject: _searched),
              ),
              const SizedBox(height: 24),
            ],
            _SectionTitle('Quick Actions'),
            const SizedBox(height: 12),
            _QuickActions(
              onTrackOrder: () => _push(const OrdersScreen()),
              onReturn: () => _submitTicket(subject: 'Return an item'),
              onPayment: () => _push(const PaymentMethodsScreen()),
              onContact: () => _push(const ContactSupportScreen()),
            ),
            const SizedBox(height: 26),
            _SectionTitle('Browse by Topic'),
            const SizedBox(height: 12),
            _Topics(
              loading: _loadingTopics,
              error: _topicsError,
              categories: categoriesFor(_categories, _audience),
              onRetry: _loadTopics,
              onOpen: _openTopic,
            ),
            const SizedBox(height: 26),
            _StillNeedHelp(
              email: _email,
              onTicket: () => _submitTicket(),
              onEmail: _copyEmail,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Average response time: 2-4 hours',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700),
  );
}

/// The banner: what this page is for, and the way into it.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.controller,
    required this.searching,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool searching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          'How can we help you?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Search our knowledge base or browse categories below',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          decoration: InputDecoration(
            hintText: 'Search for articles...',
            prefixIcon: const Icon(Icons.search),
            // Inside the field, as the reference has it.
            suffixIcon: Padding(
              padding: const EdgeInsets.all(6),
              child: FilledButton(
                onPressed: searching ? null : onSearch,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Search'),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 92),
          ),
        ),
      ],
    );
  }
}

/// The four things people come here to do.
///
/// Each goes to a screen this app already has. The reference points them at
/// website routes -- `/track-order`, `/contact` -- which would be dead ends in
/// an app that has its own orders list and its own support threads.
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onTrackOrder,
    required this.onReturn,
    required this.onPayment,
    required this.onContact,
  });

  final VoidCallback onTrackOrder;
  final VoidCallback onReturn;
  final VoidCallback onPayment;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    // The reference's four hues, read off this app's palette instead of
    // invented: its blue, its orange, its green, and -- where the reference
    // uses a purple this app does not have -- its deeper teal.
    final actions = <_Action>[
      _Action(
        icon: Icons.inventory_2_outlined,
        label: 'Track my order',
        color: AppColors.trustBlue,
        onTap: onTrackOrder,
      ),
      _Action(
        icon: Icons.replay_outlined,
        label: 'Return an item',
        color: AppColors.commerceOrange,
        onTap: onReturn,
      ),
      _Action(
        icon: Icons.credit_card_outlined,
        label: 'Payment issues',
        color: AppColors.successGreen,
        onTap: onPayment,
      ),
      _Action(
        icon: Icons.chat_bubble_outline,
        label: 'Contact support',
        color: AppColors.trustBlueDeep,
        onTap: onContact,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [for (final action in actions) _ActionTile(action)],
    );
  }
}

class _Action {
  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.action);

  final _Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: action.color,
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The published topics.
///
/// An empty knowledge base is a normal state -- this shop has not written one
/// yet -- and it is said in words rather than left as a gap under a heading.
class _Topics extends StatelessWidget {
  const _Topics({
    required this.loading,
    required this.error,
    required this.categories,
    required this.onRetry,
    required this.onOpen,
  });

  final bool loading;
  final ApiError? error;
  final List<HelpCategory> categories;
  final VoidCallback onRetry;
  final ValueChanged<HelpCategory> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(error!.message, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (categories.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No help topics have been published yet. Support can still be '
            'reached below.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final category in categories)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
                child: Icon(
                  _glyph(category.icon),
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              title: Text(
                category.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: category.description.isEmpty
                  ? null
                  : Text(
                      category.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(category),
            ),
          ),
      ],
    );
  }

  /// The server's icon name as a Material glyph.
  ///
  /// The names are the website's icon set. Anything unrecognised falls back to
  /// the generic help glyph rather than drawing an empty square.
  static IconData _glyph(String? name) => switch (name) {
    'Package' => Icons.inventory_2_outlined,
    'ShoppingBag' => Icons.shopping_bag_outlined,
    'CreditCard' => Icons.credit_card_outlined,
    'Truck' => Icons.local_shipping_outlined,
    'RotateCcw' => Icons.replay_outlined,
    'Shield' => Icons.verified_user_outlined,
    'Code' => Icons.code,
    'Rocket' => Icons.rocket_launch_outlined,
    _ => Icons.help_outline,
  };
}

/// What a search or a topic turned up.
class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.articles,
    required this.onClear,
    required this.onAsk,
  });

  final String query;
  final List<HelpArticle> articles;
  final VoidCallback onClear;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                articles.isEmpty
                    ? 'Nothing found for "$query"'
                    : '${articles.length} '
                          '${articles.length == 1 ? 'result' : 'results'} '
                          'for "$query"',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
        const SizedBox(height: 8),
        if (articles.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No article covers this yet. Support can answer it '
                    'directly.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onAsk,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Ask support'),
                  ),
                ],
              ),
            ),
          )
        else
          for (final article in articles)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(
                  article.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: article.summary.isEmpty
                    ? null
                    : Text(
                        article.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: article.featured
                    ? const Icon(Icons.star, size: 18)
                    : null,
              ),
            ),
      ],
    );
  }
}

/// The way to a human, when the knowledge base has not answered it.
class _StillNeedHelp extends StatelessWidget {
  const _StillNeedHelp({
    required this.email,
    required this.onTicket,
    required this.onEmail,
  });

  /// Null while it is being read, or when the shop has not set one. The button
  /// is then absent rather than offering an address that does not exist.
  final String? email;

  final VoidCallback onTicket;
  final ValueChanged<String> onEmail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = email;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          children: [
            Text(
              'Still need help?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Can't find what you're looking for? Our support team is here "
              'to help.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onTicket,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Submit a Ticket'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            if (address != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onEmail(address),
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: Text(address),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

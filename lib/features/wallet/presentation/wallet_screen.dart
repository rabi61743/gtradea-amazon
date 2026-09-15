import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../home/widgets/product_rail.dart' show formatGrouped;
import '../data/coin_balance_store.dart';
import '../data/wallet_repository.dart';

/// The Coins page: what this account holds, and every movement behind it.
///
/// Where the header's coin chip goes. Both read the same [CoinBalanceStore], so
/// the figure in the chip and the figure on this page cannot disagree -- they
/// did before, the chip showing the stand-in and this page a hard zero.
///
/// **Only what the server actually answers is on this page.** `GET /wallet` and
/// `GET /wallet/transactions` are real -- they answer 401 without a session
/// rather than 404 -- and they are the balance and the activity below it.
/// Earning actions, a rewards catalogue, redeemed rewards, expiry and the terms
/// behind them have no endpoint at all: `/coins`, `/rewards`, `/loyalty`,
/// `/points` and `/offers` every one answers 404. Sections for those would be
/// furniture with nothing behind them, so they are not here. Adding them is a
/// backend change first, and this page second.
///
/// Coins are counted, not priced. The figure is drawn with [formatGrouped]
/// rather than the app's rupee formatter, which is what this page used to do --
/// a thousand coins read "Rs. 1,000", which is a different claim about a
/// different thing.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  CoinBalanceStore get _coins => CoinBalanceStore.instance;

  List<WalletEntry> _entries = const [];
  bool _loadingEntries = true;
  ApiError? _entriesError;

  /// How many movements are on screen.
  ///
  /// The history is revealed a page at a time rather than all at once. It is
  /// done here rather than by asking the server for a page because the endpoint
  /// publishes no paging contract this app can see: guessing `?page=` would
  /// either be ignored -- and then "load more" would fetch the same rows again
  /// and show each twice -- or honoured in some shape nobody here knows. When
  /// the contract is published this is the one place that changes.
  int _shown = _pageSize;
  static const _pageSize = 10;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!AuthStore.instance.isSignedIn) {
      if (mounted) setState(() => _loadingEntries = false);
      return;
    }
    setState(() {
      _loadingEntries = true;
      _entriesError = null;
      _shown = _pageSize;
    });
    // Side by side: the balance is the headline and the history is the detail,
    // and holding the first behind the second would leave the number a shopper
    // came for waiting on a list they did not.
    await Future.wait([_coins.load(), _loadEntries()]);
  }

  Future<void> _loadEntries() async {
    try {
      final entries = await WalletRepository.instance.transactions();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loadingEntries = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      // Reported rather than swallowed. This used to fall back to an empty list
      // on any failure, so a history that could not be read was indistinguishable
      // from an account that had never earned anything.
      setState(() {
        _entriesError = e;
        _loadingEntries = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coins')),
      body: AuthStore.instance.isSignedIn ? _signedIn() : _guest(),
    );
  }

  Widget _guest() {
    // No balance and no history for someone the server has no account for. The
    // stand-in figure belongs in the header chip, where it stands for "not
    // known yet"; on the page about the balance it would be a claim.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sign in to see the coins you have earned.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
                if (mounted) unawaited(_load());
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signedIn() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListenableBuilder(
        listenable: _coins,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Centred and capped rather than stretched: on a tablet or a
            // desktop window a balance card the width of the screen reads as a
            // banner, and a one-line transaction spread over 1200 points has
            // its amount a hand's width from its reason.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _balanceCard(),
                    const SizedBox(height: 20),
                    ..._activity(),
                    const SizedBox(height: 24),
                    ..._earn(),
                    const SizedBox(height: 24),
                    ..._rewards(),
                    const SizedBox(height: 24),
                    ..._howItWorks(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PLACEHOLDER CONTENT -- hardcoded, by request, so the page can be seen whole.
  //
  // Nothing below this line comes from the server, because there is no server
  // behind it: `/rewards`, `/coins`, `/loyalty`, `/points` and `/offers` all
  // answer 404. These figures are illustrative furniture, not this account's.
  //
  // The one thing they deliberately do NOT do is pretend to move coins. Redeem
  // says it is not available yet rather than showing a success and a lower
  // balance, because a fake redemption is the piece that would mislead somebody
  // being shown this page.
  //
  // When the endpoints exist, these three lists and their two builders are what
  // gets deleted -- the balance and the activity above are already real.
  // ---------------------------------------------------------------------------

  /// Ways to earn, as the design shows them. Illustrative.
  static const _earnRules = <({IconData icon, String title, String detail})>[
    (
      icon: Icons.shopping_bag_outlined,
      title: 'Place an order',
      detail: 'Earn coins on every delivered order',
    ),
    (
      icon: Icons.rate_review_outlined,
      title: 'Review a product',
      detail: 'Write a review once your order arrives',
    ),
    (
      icon: Icons.group_add_outlined,
      title: 'Invite a friend',
      detail: 'They shop, you both collect',
    ),
  ];

  /// Rewards, as the design shows them. Illustrative.
  static const _rewardList = <({String name, String detail, int cost})>[
    (name: 'Rs. 100 off', detail: 'On orders over Rs. 1,500', cost: 500),
    (name: 'Free delivery', detail: 'On your next order', cost: 750),
    (name: 'Rs. 250 off', detail: 'On orders over Rs. 3,000', cost: 1200),
  ];

  List<Widget> _earn() => [
    _sectionTitle('Earn coins'),
    const SizedBox(height: 8),
    for (final rule in _earnRules)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(rule.icon, color: Theme.of(context).colorScheme.primary),
        title: Text(rule.title),
        subtitle: Text(rule.detail),
      ),
  ];

  List<Widget> _rewards() {
    final theme = Theme.of(context);

    return [
      _sectionTitle('Rewards'),
      const SizedBox(height: 8),
      for (final reward in _rewardList)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            // A border rather than a shadow, like the rest of this app.
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          // Stacked, rather than the text beside the button.
          //
          // Side by side, the button took its full natural width first and left
          // the text column 115 points on a 320pt phone -- which the cost row
          // then overflowed by forty. An Expanded bounds its child, but a
          // mainAxisSize.min Row *inside* it overruns that bound rather than
          // shrinking to it, so the cap never reached the thing that needed it.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reward.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                reward.detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.monetization_on, size: 16, color: _coinInk),
                  const SizedBox(width: 4),
                  // The glyph beside it already says what it counts, so the
                  // word comes off -- the same reasoning that drops "Rs." from
                  // the header chip. The room it frees is what lets the cost
                  // and the button share a line on a small phone.
                  Text(
                    formatGrouped(reward.cost),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _redeemNotYet,
                    child: const Text('Redeem'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _howItWorks() {
    final theme = Theme.of(context);
    const lines = [
      'Coins are added once an order is delivered.',
      'Spend them against an order at checkout.',
      'Coins do not expire while your account is active.',
    ];

    return [
      _sectionTitle('How coins work'),
      const SizedBox(height: 8),
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Icon(
                  Icons.circle,
                  size: 5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700),
  );

  /// Deliberately not a redemption.
  ///
  /// Spending coins is a server operation -- it has to check the balance, the
  /// reward and the eligibility, and deduct server-side. None of that exists
  /// yet, so this says so instead of showing a success it cannot back up.
  void _redeemNotYet() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Redeeming coins is not available yet.')),
    );
  }

  Widget _balanceCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.monetization_on, size: 40, color: _coinInk),
          const SizedBox(height: 10),
          Text(
            // Counted, not priced. See the class doc.
            formatGrouped(_coins.balance),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Coins',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Said plainly when the figure above is the stand-in rather than this
          // account's own. The number stays on screen either way -- blanking it
          // was tried and it took the balance off the one device it had to be
          // visible on -- but a page about the balance has room to say which
          // one a shopper is looking at.
          if (_coins.readFailed) ...[
            const SizedBox(height: 12),
            Text(
              'Your balance could not be read just now, so this is the '
              'standard starting figure.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _activity() {
    final theme = Theme.of(context);

    if (_loadingEntries) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      ];
    }

    if (_entriesError case final failure?) {
      return [
        LoadFailed(
          message: failure.isNetwork
              ? 'No connection, so your coin activity could not be loaded.'
              : failure.message,
          onRetry: _load,
        ),
      ];
    }

    if (_entries.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Nothing has moved in or out yet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }

    final shown = _entries.take(_shown).toList();
    final remaining = _entries.length - shown.length;

    return [
      Text(
        'Activity',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      for (final entry in shown) _EntryRow(entry: entry),
      if (remaining > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton(
            onPressed: () => setState(
              () => _shown = (_shown + _pageSize).clamp(0, _entries.length),
            ),
            child: Text('Show more ($remaining)'),
          ),
        ),
    ];
  }

  static const _coinInk = Color(0xFFD98A1E);
}

/// One movement, with whatever the server said about it and nothing more.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final WalletEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Built from what is present rather than from a fixed template: a movement
    // with no date, no status and no order prints its reason alone instead of
    // three empty captions.
    final caption = [
      if (entry.at != null) formatWhen(entry.at!),
      if (entry.orderNumber.isNotEmpty) 'Order ${entry.orderNumber}',
      if (entry.status.isNotEmpty) entry.status,
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.isCredit ? Icons.add_circle_outline : Icons.remove,
        color: entry.isCredit
            ? AppColors.successInk
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(entry.note.isEmpty ? 'Adjustment' : entry.note),
      subtitle: caption.isEmpty ? null : Text(caption),
      trailing: Text(
        '${entry.isCredit ? '+' : ''}${formatGrouped(entry.amount)}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: entry.isCredit ? AppColors.successInk : null,
        ),
      ),
    );
  }
}

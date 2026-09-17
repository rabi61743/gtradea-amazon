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
      appBar: AppBar(title: const Text('My Coins')),
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
                    const SizedBox(height: 14),
                    _infoCard(),
                    const SizedBox(height: 24),
                    ..._redeem(),
                    const SizedBox(height: 16),
                    _bottomBanner(),
                    const SizedBox(height: 24),
                    ..._activity(),
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
  // The two banner pictures are stand-ins too, until the real artwork is
  // supplied: each is one path below.
  // ---------------------------------------------------------------------------

  /// Stand-in picture on the right of the balance card.
  static const heroBannerAsset = 'assets/images/gift_banner.jpg';

  /// Stand-in banner under the rewards.
  static const bottomBannerAsset = 'assets/images/promo_banner.jpg';

  /// Rupees per coin, for the "≈ NPR" chip. Placeholder: the rate the design
  /// shows (1,000 coins ≈ NPR 100), not one the server has published.
  static const _nprPerCoin = 0.1;

  /// Rewards, as the design shows them. Illustrative.
  static const _rewardList =
      <({String name, String detail, int cost, IconData icon, Color color})>[
        (
          name: 'Rs. 100 Off',
          detail: 'On orders over Rs. 1,500',
          cost: 500,
          icon: Icons.shopping_bag_outlined,
          color: Color(0xFFF26A3D),
        ),
        (
          name: 'Free Delivery',
          detail: 'On your next order',
          cost: 750,
          icon: Icons.local_shipping_outlined,
          color: Color(0xFF22A45D),
        ),
        (
          name: 'Rs. 250 Off',
          detail: 'On orders over Rs. 3,000',
          cost: 1200,
          icon: Icons.sell_outlined,
          color: Color(0xFF1E88E5),
        ),
        (
          name: 'Product Voucher',
          detail: 'For selected products',
          cost: 1500,
          icon: Icons.card_giftcard,
          color: Color(0xFF9B45D9),
        ),
        (
          name: 'Exclusive Brand Deals',
          detail: 'Special offers from top brands',
          cost: 2000,
          icon: Icons.workspace_premium_outlined,
          color: Color(0xFFE9A21B),
        ),
        (
          name: 'Partner Store Voucher',
          detail: 'At official brand stores',
          cost: 2500,
          icon: Icons.storefront_outlined,
          color: Color(0xFF1E9AA8),
        ),
        (
          name: 'Cashback',
          detail: 'Direct wallet credit',
          cost: 3000,
          icon: Icons.account_balance_wallet_outlined,
          color: Color(0xFFE83A5F),
        ),
        (
          name: 'Premium Gift',
          detail: 'Curated gifts & accessories',
          cost: 5000,
          icon: Icons.redeem,
          color: Color(0xFF6E4BD8),
        ),
      ];

  static const _howItWorksLines = [
    'Coins are added once an order is delivered.',
    'Spend them against an order at checkout.',
    'Coins do not expire while your account is active.',
  ];

  List<Widget> _redeem() {
    final theme = Theme.of(context);

    return [
      Text(
        'Redeem Your Coins',
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.himalayanSlate,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Choose from a range of rewards and make the most of your coins.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, constraints) {
          // Two across as the design has it; one across on a phone too narrow
          // for two cards to hold their title and cost.
          final perRow = constraints.maxWidth < 330 ? 1 : 2;
          return Column(
            children: [
              for (var i = 0; i < _rewardList.length; i += perRow)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = i; j < i + perRow; j++) ...[
                          if (j > i) const SizedBox(width: 10),
                          Expanded(
                            child: j < _rewardList.length
                                ? _RewardCard(
                                    reward: _rewardList[j],
                                    onTap: _redeemNotYet,
                                  )
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  Widget _infoCard() {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('coins-info-card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F3F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.shopping_bag_outlined,
            size: 40,
            color: AppColors.himalayanSlate,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Coins are added once an order is delivered, spend them '
                  'against an order at checkout.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 6),
                InkWell(
                  key: const ValueKey('coins-learn-more'),
                  onTap: _showHowItWorks,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Learn more ›',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.trustBlue,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.trustBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showHowItWorks() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How coins work',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final line in _howItWorksLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 10),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bottomBanner() {
    return ClipRRect(
      key: const ValueKey('coins-bottom-banner'),
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1409 / 340,
        child: Image.asset(bottomBannerAsset, fit: BoxFit.cover),
      ),
    );
  }

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
    final npr = (_coins.balance * _nprPerCoin).round();

    return ClipRRect(
      key: const ValueKey('coins-balance-card'),
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFDE7D2), Color(0xFFF6EFE6), Color(0xFFE3EEF3)],
          ),
        ),
        child: Stack(
          children: [
            // Stand-in artwork on the right, fading into the card so the
            // balance never sits on top of a busy picture.
            // Filled on every side so the share below has a width to be a
            // share of; left open, the picture was laid out unbounded.
            Positioned.fill(
              child: FractionallySizedBox(
                widthFactor: 0.4,
                heightFactor: 1,
                alignment: Alignment.centerRight,
                child: ShaderMask(
                  // A long, soft fade, so the picture starts where the
                  // balance ends rather than cutting in beside it.
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [Colors.transparent, Colors.black],
                    stops: [0, 0.6],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: ClipRect(
                    // Scaled up a little so the stand-in's own rounded, dark
                    // corners fall outside the card.
                    child: Transform.scale(
                      scale: 1.15,
                      alignment: Alignment.centerRight,
                      child: Image.asset(
                        heroBannerAsset,
                        fit: BoxFit.cover,
                        alignment: const Alignment(0.7, 0),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: FractionallySizedBox(
                widthFactor: 0.6,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _CoinG(size: 64),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Coins',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.himalayanSlate,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  // Counted, not priced. See the class doc.
                                  formatGrouped(_coins.balance),
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF14233C),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                key: const ValueKey('coins-npr-chip'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCDE7F2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '≈ NPR ${formatGrouped(npr)}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.trustBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Said plainly when the figure above is the stand-in
                    // rather than this account's own.
                    if (_coins.readFailed) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Your balance could not be read just now, so this is '
                        'the standard starting figure.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.himalayanSlate,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Material(
                      color: Colors.white,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        key: const ValueKey('coins-refresh'),
                        customBorder: const StadiumBorder(),
                        onTap: _load,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.refresh,
                                size: 18,
                                color: Color(0xFF14233C),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Refresh',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF14233C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

/// One reward in the Redeem grid: a coloured badge, what it is, and its cost.
class _RewardCard extends StatelessWidget {
  const _RewardCard({required this.reward, required this.onTap});

  final ({String name, String detail, int cost, IconData icon, Color color})
  reward;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = reward.color;

    return Material(
      color: Color.alphaBlend(tint.withValues(alpha: 0.07), Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tint.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('reward-${reward.name}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(reward.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF14233C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reward.detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const _CoinG(size: 20),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            formatGrouped(reward.cost),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF14233C),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 22,
                          color: Color(0xFF14233C),
                        ),
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

/// A gold "G" coin, drawn rather than an image so it is sharp at any size.
class _CoinG extends StatelessWidget {
  const _CoinG({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFFFE07A), Color(0xFFF5B316), Color(0xFFD98A0E)],
          stops: [0, 0.6, 1],
        ),
        border: Border.all(color: const Color(0xFFE39B12), width: size * 0.06),
      ),
      child: Text(
        'G',
        style: TextStyle(
          fontSize: size * 0.55,
          height: 1,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          shadows: const [
            Shadow(color: Color(0x66A0600A), offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

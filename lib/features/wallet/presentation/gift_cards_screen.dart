import 'package:flutter/material.dart';

import '../../help/presentation/contact_support_screen.dart';

/// Gift cards.
///
/// **There is no gift-card feature.** The server keeps one route for them and
/// it is `/admin/gift-cards-table`; every customer-facing spelling --
/// `gift-cards`, `gift-card`, `vouchers`, `store-credits` -- answers 404. So
/// this page cannot show a balance, sell one, or redeem one, and inventing a
/// form that posts nowhere would be worse than saying so.
///
/// It says so, and offers the one thing that does work: asking a person. The
/// card on the home page leads here rather than nowhere.
class GiftCardsScreen extends StatelessWidget {
  const GiftCardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Gift Cards')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7FD),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.card_giftcard,
                  size: 36,
                  color: Color(0xFF7C3AED),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Gift cards are not on sale yet',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We cannot sell or redeem one in the app today. If you want to '
                'buy a gift for somebody, support can arrange it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ContactSupportScreen(),
                  ),
                ),
                child: const Text('Ask support'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

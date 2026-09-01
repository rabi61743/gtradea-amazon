import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_error.dart';
import '../../orders/presentation/track_order_screen.dart';
import '../data/help_repository.dart';
import 'contact_support_screen.dart';
import 'help_center_screen.dart';

/// How to reach the shop, and the two places people go next.
///
/// The address and the number are the shop's own settings, read from
/// `site-settings` -- the same values the website prints, so the two cannot
/// drift apart. Nothing on this page is written into the app.
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  String? _email;
  String? _phone;
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
      // Two settings, asked for together rather than one after the other.
      final results = await Future.wait([
        HelpRepository.instance.supportEmail(),
        HelpRepository.instance.supportPhone(),
      ]);
      if (!mounted) return;
      setState(() {
        _email = results[0];
        _phone = results[1];
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

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label copied')));
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _ContactInformation(
              loading: _loading,
              error: _error,
              email: _email,
              phone: _phone,
              onRetry: _load,
              onCopy: _copy,
            ),
            const SizedBox(height: 16),
            _QuickLinks(
              onHelpCenter: () => _push(const HelpCenterScreen()),
              onTrackOrder: () => _push(const TrackOrderScreen()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _push(const ContactSupportScreen()),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Submit a Ticket'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Email, response time and phone, as the reference has them.
class _ContactInformation extends StatelessWidget {
  const _ContactInformation({
    required this.loading,
    required this.error,
    required this.email,
    required this.phone,
    required this.onRetry,
    required this.onCopy,
  });

  final bool loading;
  final ApiError? error;
  final String? email;
  final String? phone;
  final VoidCallback onRetry;
  final Future<void> Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact Information',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null) ...[
              Text(error!.message, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ] else ...[
              if (email != null)
                _ContactRow(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  value: email!,
                  onTap: () => onCopy('Email', email!),
                ),
              // Not a setting: the shop publishes no response-time key, and
              // this is the commitment its own Help Center states.
              const _ContactRow(
                icon: Icons.schedule,
                label: 'Response Time',
                value: '2-4 hours (business hours)',
              ),
              if (phone != null)
                _ContactRow(
                  icon: Icons.call_outlined,
                  label: 'Phone',
                  value: phone!,
                  onTap: () => onCopy('Phone number', phone!),
                ),
              if (email == null && phone == null)
                Text(
                  'This shop has not published contact details yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One line of contact information: icon, what it is, and the value itself.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Null for a line there is nothing to do with, like the response time.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
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

/// Where people go from here.
class _QuickLinks extends StatelessWidget {
  const _QuickLinks({required this.onHelpCenter, required this.onTrackOrder});

  final VoidCallback onHelpCenter;
  final VoidCallback onTrackOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Links',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            _Link(
              icon: Icons.help_outline,
              label: 'Help Center',
              onTap: onHelpCenter,
            ),
            _Link(
              icon: Icons.location_on_outlined,
              label: 'Track Order',
              onTap: onTrackOrder,
            ),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

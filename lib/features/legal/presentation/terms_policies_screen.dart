import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../data/legal_page_repository.dart';
import 'legal_page_screen.dart';

/// The pages this screen does not list.
///
/// Not a whitelist of policies, which would hide a tenth one the shop
/// published tomorrow. These four are excluded because they are not policies
/// and because the app already has somewhere for them: "about" is its own row
/// on the account page, and the questions the shop answers are the Help
/// Center's job. Careers and press are company news rather than terms.
const _notPolicies = {'about', 'faq', 'careers', 'press'};

/// The order the well-known ones read in. Anything the shop adds that is not
/// on this list still appears, after them, rather than being dropped.
const _order = [
  'terms',
  'terms-and-conditions',
  'privacy',
  'returns',
  'shipping',
];

/// Everything the shop has committed to in writing.
class TermsPoliciesScreen extends StatefulWidget {
  const TermsPoliciesScreen({super.key});

  @override
  State<TermsPoliciesScreen> createState() => _TermsPoliciesScreenState();
}

class _TermsPoliciesScreenState extends State<TermsPoliciesScreen> {
  List<LegalPage> _pages = const [];
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
      final all = await LegalPageRepository.instance.list();
      if (!mounted) return;
      setState(() {
        _pages = _policies(all);
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

  static List<LegalPage> _policies(List<LegalPage> all) {
    final policies = [
      for (final page in all)
        if (!_notPolicies.contains(page.slug)) page,
    ];
    policies.sort((a, b) {
      // Known ones first, in the order above; the rest keep the shop's own
      // order behind them.
      final left = _order.indexOf(a.slug);
      final right = _order.indexOf(b.slug);
      if (left == right) return 0;
      if (left < 0) return 1;
      if (right < 0) return -1;
      return left.compareTo(right);
    });
    return policies;
  }

  void _open(LegalPage page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalPageScreen(slug: page.slug, title: page.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms and policies')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final error = _error;
    if (error != null) {
      return _Message(text: error.message, onRetry: _load);
    }
    if (_pages.isEmpty) {
      return _Message(
        text: 'This shop has not published any policies yet.',
        onRetry: _load,
      );
    }

    return SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        itemCount: _pages.length,
        itemBuilder: (context, i) {
          final page = _pages[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(page.title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(page),
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

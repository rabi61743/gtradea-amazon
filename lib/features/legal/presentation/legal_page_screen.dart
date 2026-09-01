import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../data/legal_blocks.dart';
import '../data/legal_page_repository.dart';

/// One of the shop's written pages, read at length.
///
/// The checkout sheet shows the terms in a box above a checkbox; this is the
/// same text given a screen to be read on, with the headings and lists it was
/// written with left intact.
class LegalPageScreen extends StatefulWidget {
  const LegalPageScreen({super.key, required this.slug, this.title});

  final String slug;

  /// The title to show while the page loads, when the caller already knows it
  /// from the list it came from. Avoids a blank bar and then a jump.
  final String? title;

  @override
  State<LegalPageScreen> createState() => _LegalPageScreenState();
}

class _LegalPageScreenState extends State<LegalPageScreen> {
  LegalPage? _page;
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
      final page = await LegalPageRepository.instance.bySlug(widget.slug);
      if (!mounted) return;
      setState(() {
        _page = page;
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

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final title = page?.title.isNotEmpty == true
        ? page!.title
        : (widget.title ?? '');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _body(page),
    );
  }

  Widget _body(LegalPage? page) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final error = _error;
    if (error != null) {
      return _Retry(message: error.message, onRetry: _load);
    }

    final blocks = legalBlocks(page?.html ?? '');
    if (blocks.isEmpty) {
      return _Retry(
        message: 'This page has not been written yet.',
        onRetry: _load,
      );
    }

    return SafeArea(
      child: ListView.builder(
        // Wide enough to read on a tablet without the line length running
        // away, and full width on a phone.
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        itemCount: blocks.length,
        itemBuilder: (context, i) => _Block(blocks[i]),
      ),
    );
  }
}

/// One heading, paragraph or bullet, in the app's own type scale.
class _Block extends StatelessWidget {
  const _Block(this.block);

  final LegalBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (block.kind) {
      case LegalBlockKind.heading:
        final style = switch (block.level) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          _ => theme.textTheme.titleMedium,
        };
        return Padding(
          // More air above a heading than below it, so it reads as belonging
          // to what follows rather than floating between two sections.
          padding: EdgeInsets.only(top: block.level == 1 ? 8 : 22, bottom: 8),
          child: Text(
            block.text,
            style: style?.copyWith(fontWeight: FontWeight.w800),
          ),
        );

      case LegalBlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: theme.textTheme.bodyMedium),
              Expanded(
                child: Text(
                  block.text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ),
            ],
          ),
        );

      case LegalBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            block.text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        );
    }
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

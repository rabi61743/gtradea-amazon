import 'package:flutter/material.dart';

import '../../core/async/loadable.dart';

/// Renders a [Loadable] honestly: what is there, what is loading, what failed.
///
/// The rule it enforces is that a failure is never silence. Every error state
/// says what went wrong in the server's own words and offers the one thing that
/// might help, which is trying again.
class LoadableView<T> extends StatelessWidget {
  const LoadableView({
    super.key,
    required this.loadable,
    required this.builder,
    this.loading,
    this.emptyCheck,
    this.empty,
    this.errorPadding = const EdgeInsets.all(16),
  });

  final Loadable<T> loadable;
  final Widget Function(BuildContext context, T value) builder;

  /// Shown on the first load only. Once there is something to show, a refresh
  /// leaves it on screen rather than replacing it with a spinner.
  final Widget? loading;

  /// Whether a loaded value counts as nothing at all.
  final bool Function(T value)? emptyCheck;
  final Widget? empty;

  final EdgeInsets errorPadding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: loadable,
      builder: (context, _) {
        final value = loadable.value;

        if (value != null) {
          final isEmpty = emptyCheck?.call(value) ?? false;
          if (isEmpty && !loadable.isLoading) {
            return empty ?? const SizedBox.shrink();
          }
          if (!isEmpty) return builder(context, value);
        }

        if (loadable.isLoading) {
          return loading ?? const _Spinner();
        }

        final error = loadable.error;
        if (error != null) {
          return Padding(
            padding: errorPadding,
            child: LoadFailed(
              message: error.isNetwork
                  ? 'No connection. Check your network and try again.'
                  : error.message,
              onRetry: loadable.refresh,
            ),
          );
        }

        return empty ?? const SizedBox.shrink();
      },
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

/// What went wrong, and the button that might fix it.
class LoadFailed extends StatelessWidget {
  const LoadFailed({
    super.key,
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

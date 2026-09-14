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
    this.silentOnError = false,
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

  /// Fail by drawing nothing instead of by saying so.
  ///
  /// The exception to the rule above, and it is meant to stay a narrow one. Use
  /// it only for a section a shopper did not ask for and cannot miss -- where
  /// the same failure is already reported by another block on the same page, so
  /// a second copy of it is noise rather than honesty.
  ///
  /// The Random Products rail is the case it was added for: when the product
  /// feed is down, the recommendations below it already say so, with the
  /// server's words and a retry. Two identical error rows one above the other
  /// tell a shopper nothing the first one did not.
  ///
  /// Never use it for something that was asked for. A search that quietly
  /// renders nothing is a bug report waiting to happen.
  final bool silentOnError;

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
        if (error != null && silentOnError) return const SizedBox.shrink();
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
    this.retryLabel,
    this.retryIcon,
  });

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  /// What the button says, when "Try again" would be the wrong thing to
  /// offer. An expired session is the case this exists for: retrying a dead
  /// refresh token fetches the same refusal forever, and the way out is to
  /// sign in. Null keeps the default, so every other caller is unchanged.
  final String? retryLabel;
  final IconData? retryIcon;

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
              icon: Icon(retryIcon ?? Icons.refresh, size: 18),
              label: Text(retryLabel ?? 'Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

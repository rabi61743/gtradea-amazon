import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/location_detector.dart';

/// The detected address, as much of it as could be worked out.
typedef DetectedPlace = ({
  String city,
  String province,
  String? addressLine,
  String? postalCode,
  bool approximate,
});

/// "Use my current location", with the whole flow behind it.
///
/// One widget rather than two copies, because it is offered both when choosing
/// an address at checkout and when adding one from the account page, and the
/// wording for each way it can fail is the part worth getting right once.
///
/// Outcomes are shown in place rather than in a snack bar. A snack bar is the
/// wrong shape for this: the recoveries here are buttons -- open location
/// settings, open app settings, try again -- and a message that slides away
/// after four seconds takes its own remedy with it.
///
/// Sending the shopper to settings and hoping is not enough either, so this
/// watches for the app coming back to the foreground and retries by itself.
/// Turning location on and returning to find nothing happened is the whole
/// reason people give up on this button.
class UseMyLocationTile extends StatefulWidget {
  const UseMyLocationTile({super.key, required this.onDetected});

  /// Called only when a place was actually found.
  final ValueChanged<DetectedPlace> onDetected;

  @override
  State<UseMyLocationTile> createState() => _UseMyLocationTileState();
}

class _UseMyLocationTileState extends State<UseMyLocationTile>
    with WidgetsBindingObserver {
  bool _busy = false;
  DetectResult? _problem;

  /// True while the shopper is away in system settings, so coming back is
  /// treated as "they went to fix it" rather than as any old resume.
  bool _awaitingSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingSettings) return;
    _awaitingSettings = false;
    // Straight back into it. The shopper went to turn something on; making
    // them find this button again would waste the trip.
    _detect();
  }

  Future<void> _detect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });

    final result = await LocationDetector.instance.detect();
    if (!mounted) return;

    setState(() => _busy = false);

    // A modal sheet on top of this one means the shopper has moved on -- they
    // tapped Add address, or a quick city, while this was still running. The
    // tile stays mounted underneath, so `mounted` alone does not catch it, and
    // opening a second prefilled form over the one they are typing into would
    // bury their work.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    switch (result) {
      case DetectResolved(
        :final city,
        :final province,
        :final addressLine,
        :final postalCode,
        :final isApproximate,
      ):
        setState(() => _problem = null);
        // Nothing is said in a snack bar here: onDetected opens a sheet over
        // this one in the same frame, and the message would be drawn
        // underneath it. The hedge travels with the result instead, so it
        // lands on the field it is actually about.
        widget.onDetected((
          city: city,
          province: province,
          addressLine: addressLine,
          postalCode: postalCode,
          approximate: isApproximate,
        ));

      default:
        setState(() => _problem = result);
    }
  }

  Future<void> _openLocationSettings() async {
    _awaitingSettings = true;
    await LocationDetector.instance.openLocationSettings();
  }

  Future<void> _openAppSettings() async {
    _awaitingSettings = true;
    await LocationDetector.instance.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tile(busy: _busy, onTap: _busy ? null : _detect),
        if (_problem != null) ...[
          const SizedBox(height: 10),
          _Problem(
            result: _problem!,
            onRetry: _detect,
            onOpenLocationSettings: _openLocationSettings,
            onOpenAppSettings: _openAppSettings,
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          color: theme.colorScheme.primary.withValues(alpha: 0.07),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.14,
                        ),
                      ),
                      child: Icon(
                        Icons.my_location,
                        size: 19,
                        color: theme.colorScheme.primary,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    busy ? 'Finding you...' : 'Use my current location',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    busy
                        ? 'This takes a moment'
                        : 'Fills in what we can, you check the rest',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!busy)
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// What went wrong and what to do about it, side by side.
///
/// Every case names its own remedy. "Something went wrong" is the one message
/// that leaves a shopper stuck, so it is never the message.
class _Problem extends StatelessWidget {
  const _Problem({
    required this.result,
    required this.onRetry,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  final DetectResult result;
  final VoidCallback onRetry;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (message, actionLabel, action, isBlocking) = _describe();

    final tone = isBlocking
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        color: tone.withValues(alpha: 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isBlocking ? Icons.error_outline : Icons.info_outline,
                size: 18,
                color: tone,
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
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonal(onPressed: action, child: Text(actionLabel)),
              // Only when the primary action is something else. Four of these
              // states already retry, and two identical buttons side by side
              // reads as a rendering bug.
              if (actionLabel != 'Try again') ...[
                const SizedBox(width: 8),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ],
          ),
        ],
      ),
    );
  }

  (String message, String actionLabel, VoidCallback action, bool blocking)
  _describe() {
    switch (result) {
      case DetectServiceDisabled():
        return (
          'Location is switched off on this device. Turn it on and we will '
              'pick up where we left off.',
          'Enable location',
          onOpenLocationSettings,
          true,
        );

      case DetectPermissionDenied(permanently: true):
        return (
          'Location is blocked for this app. You can allow it in app '
              'settings.',
          'Open settings',
          onOpenAppSettings,
          true,
        );

      case DetectPermissionDenied(permanently: false):
        return (
          'We need permission to use your location. It is only used to fill '
              'in this address.',
          'Allow location',
          onRetry,
          false,
        );

      case DetectTimeout():
        return (
          'That took too long. A window or a step outside usually helps.',
          'Try again',
          onRetry,
          false,
        );

      case DetectUnavailable():
        return (
          'This device could not work out where it is just now. You can type '
              'the address instead.',
          'Try again',
          onRetry,
          false,
        );

      case DetectOutsideServedArea(:final nearest):
        return (
          'We could not match you to a city we deliver to. The nearest is '
              '$nearest.',
          'Try again',
          onRetry,
          false,
        );

      case DetectFailed():
        return (
          'Could not get your location just now. You can type the address '
              'instead.',
          'Try again',
          onRetry,
          false,
        );

      case DetectResolved():
        // Never rendered: a resolved result is handled before this widget is
        // shown. Kept so the switch stays exhaustive rather than defaulting.
        return ('', 'Try again', onRetry, false);
    }
  }
}

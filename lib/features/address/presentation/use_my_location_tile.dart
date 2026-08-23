import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/location_detector.dart';

/// The detected city and province, or null when nothing usable came back.
typedef DetectedCity = ({String city, String province});

/// "Use my current location", with the whole flow behind it.
///
/// One widget rather than two copies, because it is offered both when choosing
/// an address at checkout and when adding one from the account page, and the
/// wording for each way it can fail is the part worth getting right once.
///
/// It reports the city, not the doorstep, and the caption says so. There is no
/// geocoder here -- [LocationDetector] matches the fix to the nearest city the
/// shop serves -- so promising a full address would be promising something it
/// cannot deliver.
class UseMyLocationTile extends StatefulWidget {
  const UseMyLocationTile({super.key, required this.onDetected});

  /// Called only when a city was actually found.
  final ValueChanged<DetectedCity> onDetected;

  @override
  State<UseMyLocationTile> createState() => _UseMyLocationTileState();
}

class _UseMyLocationTileState extends State<UseMyLocationTile> {
  bool _busy = false;

  Future<void> _detect() async {
    setState(() => _busy = true);
    final result = await LocationDetector.instance.detect();
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case DetectResolved(:final city, :final province, :final isApproximate):
        _say(isApproximate
            ? 'Looks like you are near $city. Change it if that is wrong.'
            : 'Found you in $city.');
        widget.onDetected((city: city, province: province));

      case DetectOutsideServedArea(:final nearest):
        _say('We could not match you to a city we deliver to. The nearest is '
            '$nearest.');

      case DetectServiceDisabled():
        // No permission prompt would ever appear for this, so asking for one
        // would only look broken.
        _say('Location is switched off on this phone. Turn it on and try '
            'again.');

      case DetectPermissionDenied(:final permanently):
        _say(permanently
            ? 'Location is blocked for this app. You can allow it in your '
                'phone settings.'
            : 'We need location permission to find your city.');

      case DetectFailed():
        _say('Could not get your location just now. You can type the address '
            'instead.');
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: _busy ? null : _detect,
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
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.14),
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
                    _busy ? 'Finding you...' : 'Use my current location',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _busy
                        ? 'This takes a moment'
                        : 'Fills in your city, you add the street',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!_busy)
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

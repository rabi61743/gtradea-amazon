import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../data/voice_search.dart';

/// The microphone, while it is open.
///
/// A sheet rather than a snack bar or a dialog, for the same reason the address
/// feature shows its location problems in place: every way this can end has its
/// own remedy -- speak again, allow the microphone, open settings, give up and
/// type -- and a message that slides away after four seconds takes its own
/// remedy with it.
///
/// Returns the transcript, or null if nothing usable came of it.
class VoiceSearchSheet extends StatefulWidget {
  const VoiceSearchSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // Not dismissible by dragging: the microphone is live, and a sheet that
      // slides shut under a thumb would leave it open behind the app.
      enableDrag: false,
      builder: (_) => const VoiceSearchSheet(),
    );
  }

  @override
  State<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends State<VoiceSearchSheet> {
  StreamSubscription<VoiceEvent>? _subscription;

  String _heard = '';
  double _level = 0;
  VoiceOutcome? _problem;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // Whatever state the sheet was in, the microphone does not outlive it.
    unawaited(VoiceSearch.instance.cancel());
    super.dispose();
  }

  void _start() {
    _subscription?.cancel();
    setState(() {
      _heard = '';
      _level = 0;
      _problem = null;
      _listening = true;
    });

    _subscription = VoiceSearch.instance
        .listen(language: LanguageStore.instance.language)
        .listen((event) {
          if (!mounted) return;
          switch (event) {
            case VoiceLevel(:final level):
              setState(() => _level = level);
            case VoicePartial(:final text):
              setState(() => _heard = text);
            case VoiceHeard(:final transcript):
              // Closing with the answer rather than showing it and waiting for a
              // confirm tap. The shopper just said it out loud; asking them to
              // approve their own sentence is a step for nothing.
              Navigator.of(context).pop(transcript);
            case VoiceOutcome():
              setState(() {
                _listening = false;
                _problem = event;
              });
          }
        });
  }

  Future<void> _stop() async {
    setState(() => _listening = false);
    // Not a cancel: stopping takes whatever has been heard so far as the
    // answer, which arrives on the stream as a normal final result.
    await VoiceSearch.instance.stop();
  }

  Future<void> _openSettings() async {
    await VoiceSearch.instance.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _problem;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (problem == null) ...[
              _Pulse(level: _level, active: _listening),
              const SizedBox(height: 18),
              Text(
                _listening ? 'Listening...' : 'One moment',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _heard.isEmpty ? 'Say what you are looking for' : _heard,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.35,
                  color: _heard.isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                  fontWeight: _heard.isEmpty
                      ? FontWeight.w400
                      : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _listening ? _stop : null,
                    child: const Text('Done'),
                  ),
                ],
              ),
            ] else
              _Problem(
                outcome: problem,
                onRetry: _start,
                onOpenSettings: _openSettings,
                onDismiss: () => Navigator.of(context).pop(),
              ),
          ],
        ),
      ),
    );
  }
}

/// The microphone, breathing with whatever it can hear.
///
/// Driven by the sound level rather than by a fixed animation: a ring that
/// pulses on a timer looks identical whether the microphone is working or dead,
/// which is the one thing this needs to show.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.level, required this.active});

  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ring = 64 + (active ? level * 36 : 0.0);

    return SizedBox(
      width: 108,
      height: 108,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: ring,
              height: ring,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(
                  alpha: active ? 0.18 : 0.08,
                ),
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
              child: Icon(
                active ? Icons.mic : Icons.mic_none,
                size: 26,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What went wrong and what to do about it.
///
/// Every case names its own remedy. "Something went wrong" is the one message
/// that leaves a shopper stuck, so it is never the message.
class _Problem extends StatelessWidget {
  const _Problem({
    required this.outcome,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onDismiss,
  });

  final VoiceOutcome outcome;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, message, canRetry, needsSettings) = _describe();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
          ),
          child: Icon(icon, size: 26, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: onDismiss,
              // Typing is always the way out, and saying so is more use than a
              // bare "Close".
              child: const Text('Type instead'),
            ),
            const SizedBox(width: 8),
            // Both offered whenever the microphone was refused. The platform's
            // "permanently denied" flag is not reliable enough to hide one of
            // them behind it -- it only decides which reads as the primary.
            if (needsSettings)
              FilledButton.tonal(
                onPressed: onOpenSettings,
                child: const Text('Open settings'),
              ),
            if (needsSettings && canRetry) const SizedBox(width: 8),
            if (canRetry)
              needsSettings
                  ? TextButton(onPressed: onRetry, child: const Text('Retry'))
                  : FilledButton.tonal(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
          ],
        ),
      ],
    );
  }

  (IconData, String, String, bool canRetry, bool needsSettings) _describe() {
    switch (outcome) {
      case VoiceNothingHeard():
        return (
          Icons.hearing_disabled,
          'We did not catch that',
          'Try again a little closer to the microphone.',
          true,
          false,
        );

      case VoicePermissionDenied(permanently: true):
        return (
          Icons.mic_off,
          'The microphone is blocked',
          'Voice search needs the microphone. You can allow it in app '
              'settings.',
          true,
          true,
        );

      case VoicePermissionDenied(permanently: false):
        return (
          Icons.mic_off,
          'The microphone is off for this app',
          'Voice search needs the microphone. It is only used while you are '
              'speaking a search.',
          true,
          true,
        );

      case VoiceUnavailable():
        return (
          Icons.mic_off,
          'Voice search is not available here',
          'This device has no speech recognition installed. You can type your '
              'search instead.',
          false,
          false,
        );

      case VoiceFailed(reason: 'network'):
        return (
          Icons.wifi_off,
          'No connection',
          'Speech recognition needs a connection on this device. Check yours '
              'and try again.',
          true,
          false,
        );

      case VoiceFailed():
        return (
          Icons.mic_off,
          'Voice search stopped',
          'Something interrupted the microphone. You can try again or type '
              'your search.',
          true,
          false,
        );

      case VoiceHeard():
        // Never rendered: a transcript closes the sheet before this widget is
        // built. Kept so the switch stays exhaustive rather than defaulting.
        return (Icons.mic, '', '', true, false);
    }
  }
}

/// The microphone button as it sits inside a search pill.
///
/// Its own widget because both search bars carry one and they have to look and
/// measure the same -- the home header and the search screens are two places a
/// shopper sees within a second of each other.
class VoiceSearchButton extends StatelessWidget {
  const VoiceSearchButton({
    super.key,
    required this.onResult,
    this.size = 22,
    this.color,
  });

  /// Called with the transcript, once, only when something was heard.
  final ValueChanged<String> onResult;

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.mic_none, size: size, color: color),
      tooltip: 'Search by voice',
      // Constrained to the icon so two of these sit side by side inside a pill
      // without the default 48pt boxes pushing the hint text out.
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size + 14, height: size + 14),
      onPressed: () async {
        final transcript = await VoiceSearchSheet.show(context);
        if (transcript == null || transcript.trim().isEmpty) return;
        onResult(transcript.trim());
      },
    );
  }
}

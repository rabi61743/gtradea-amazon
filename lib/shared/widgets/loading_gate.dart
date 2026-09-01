import 'dart:async';

import 'package:flutter/material.dart';

/// Holds a loading state back until the wait is long enough to be worth showing.
///
/// A cached department tree answers in single-digit milliseconds. Showing a
/// skeleton for one frame and then the content is a flash, and a flash reads as
/// a fault -- it is the thing people mean when they say an app feels janky even
/// though it was fast. Nothing at all for the first [delay] is calmer *and*
/// truer: at that speed there was no wait to report.
///
/// The other half of the same problem is a placeholder that appears and then
/// vanishes immediately because the answer landed just after the delay
/// expired. [minimumVisible] keeps it up long enough to be read rather than
/// perceived as a glitch.
class LoadingGate extends StatefulWidget {
  const LoadingGate({
    super.key,
    required this.loading,
    required this.loadingChild,
    required this.child,
    this.delay = const Duration(milliseconds: 180),
    this.minimumVisible = const Duration(milliseconds: 320),
    this.fade = const Duration(milliseconds: 220),
  });

  /// Whether the caller is still waiting.
  final bool loading;

  /// What to show while waiting, once the wait has earned it.
  final Widget loadingChild;

  /// The real content.
  final Widget child;

  /// How long a wait has to last before it is worth reporting.
  final Duration delay;

  /// Once shown, the least time the placeholder stays up.
  final Duration minimumVisible;

  /// The crossfade when the content arrives. Short: this is a transition, not
  /// an effect, and a slow one makes a fast app feel slow.
  final Duration fade;

  @override
  State<LoadingGate> createState() => _LoadingGateState();
}

class _LoadingGateState extends State<LoadingGate> {
  /// Whether the placeholder is on screen right now.
  bool _showing = false;

  Timer? _appear;
  Timer? _hold;

  /// Set when the answer arrived while the placeholder was serving its minimum,
  /// so the swap happens the moment that expires.
  bool _pendingHide = false;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _scheduleAppear();
  }

  @override
  void didUpdateWidget(LoadingGate old) {
    super.didUpdateWidget(old);
    if (old.loading == widget.loading) return;
    if (widget.loading) {
      _pendingHide = false;
      if (!_showing) _scheduleAppear();
    } else {
      _appear?.cancel();
      _appear = null;
      // Still inside its minimum, so the hide waits for the hold timer.
      if (_showing && _hold != null) {
        _pendingHide = true;
      } else if (_showing) {
        setState(() => _showing = false);
      }
    }
  }

  void _scheduleAppear() {
    _appear?.cancel();
    _appear = Timer(widget.delay, () {
      if (!mounted || !widget.loading) return;
      setState(() => _showing = true);
      _hold = Timer(widget.minimumVisible, () {
        if (!mounted) return;
        _hold = null;
        if (_pendingHide) setState(() => _showing = false);
      });
    });
  }

  @override
  void dispose() {
    // Both cancelled, always. A timer outliving the tree is a pending-timer
    // failure in every test that pumps this and a leak in the app.
    _appear?.cancel();
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: widget.fade,
      // Cross-faded in place rather than the default's scale, and with the two
      // children stacked so the outgoing one does not collapse the layout
      // mid-transition and shift everything below it.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: _showing
          ? KeyedSubtree(
              key: const ValueKey('loading'),
              child: widget.loadingChild,
            )
          : KeyedSubtree(key: const ValueKey('content'), child: widget.child),
    );
  }
}

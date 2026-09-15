import 'package:flutter/widgets.dart';

/// A part of the storefront the tour can point at.
///
/// Named rather than passed as keys, so the steps are a list of facts about
/// what to explain and the wiring of which widget that is lives with the
/// screen that builds it. A screen registers the anchors it can offer; the
/// tour asks for them and skips what is not there.
enum TourAnchor {
  /// No target: the step dims the page and speaks for itself. The welcome.
  none,

  /// The brand band at the top, with the delivery line and the icon row.
  header,

  /// The search pill.
  search,

  /// The department strip under the header.
  categories,

  /// The cart destination in the bottom bar.
  cart,

  /// The account destination, which is where orders are reached.
  account,

  /// The saved-products destination.
  wishlist,

  /// The "New for You" destination.
  newForYou,

  /// The messages button in the header's icon row.
  messages,

  /// The orders button in the header's icon row.
  orders,

  /// The coin balance chip, beside the delivery line.
  ///
  /// Present only when the account actually has a balance to show -- a guest
  /// has none, and neither has a shopper whose balance has not been read yet.
  /// The step that wants it is skipped in those cases rather than ringing a
  /// chip that was never built.
  coins,
}

/// Where the live widgets are, so the tour can point at the real ones.
///
/// A registry of [GlobalKey]s rather than a rebuilt copy of the UI: the whole
/// point of the highlight is that it rings the header the shopper is about to
/// use, not a picture of a header. A screen puts its keys in on build and
/// takes them out when it goes; an anchor nobody registered simply has no key,
/// and the step that wanted it is skipped.
class TourAnchors {
  TourAnchors._();

  static final TourAnchors instance = TourAnchors._();

  final Map<TourAnchor, GlobalKey> _keys = {};

  /// The key for [anchor], creating it the first time it is asked for.
  ///
  /// Handed to the widget that owns that part of the screen, which is what
  /// puts a real render box behind it.
  GlobalKey keyOf(TourAnchor anchor) =>
      _keys[anchor] ??= GlobalKey(debugLabel: 'tour-${anchor.name}');

  /// The key for [anchor] if one has been handed out, else null.
  ///
  /// Null and "registered but off screen" are both "cannot be shown", and the
  /// overlay treats them the same -- see its `_rectFor`.
  GlobalKey? keyFor(TourAnchor anchor) => _keys[anchor];

  @visibleForTesting
  void clear() => _keys.clear();
}

/// One step of the tour.
@immutable
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    required this.anchor,
    this.icon,
    this.version = 1,
  });

  final String title;
  final String body;

  /// The mark drawn above the words, on the dim.
  ///
  /// The reference leads each instruction with one -- a hand over a heart for
  /// "double tap to wishlist" -- and it is what makes a line of text on a dark
  /// screen read as a pointer at something rather than as a notice. Null falls
  /// back to whatever suits the anchor; see `_iconFor`.
  final IconData? icon;

  /// What to ring. [TourAnchor.none] dims the page without a hole.
  final TourAnchor anchor;

  /// The tour version this step arrived in.
  ///
  /// What makes a later release show only what is new: a shopper who finished
  /// version 1 is offered the steps whose version is above 1, not the lot.
  final int version;
}

/// The tour as it currently stands.
///
/// Five steps, in the order the spec asks for. Each points at something that
/// is really on the home screen; anything that is not on a particular screen
/// or width is skipped by the overlay rather than drawn against nothing.
const tourSteps = <TourStep>[
  TourStep(
    title: 'Welcome to Gtradea',
    body:
        'A quick look at where everything is. It takes a few seconds, and '
        'you can skip it at any point.',
    anchor: TourAnchor.none,
  ),
  TourStep(
    title: 'Search',
    body:
        'Find products quickly using Search. You can also search by voice '
        'or with a photograph.',
    anchor: TourAnchor.search,
  ),
  TourStep(
    title: 'Categories',
    body:
        'Explore products by category. Pick a department here to change '
        'what the page below lists.',
    anchor: TourAnchor.categories,
  ),
  TourStep(
    title: 'Cart',
    body: 'Review your products and manage your cart before checkout.',
    anchor: TourAnchor.cart,
  ),
  TourStep(
    title: 'Your coins',
    body: 'Check your Gtradea Coins balance and see your available rewards.',
    anchor: TourAnchor.coins,
    // Version 2, because the tour has already been shown. Somebody who
    // finished the five steps of version 1 is offered this one alone rather
    // than the whole walkthrough again -- which is what the version on a step
    // is for. A first install still sees all six, in order.
    version: 2,
  ),
  TourStep(
    title: 'Orders',
    body: 'Track your orders and manage your purchases here.',
    // The header's own Orders icon, beside the bell -- not the account
    // destination in the bottom bar. It is the control a shopper actually
    // reaches for while they are waiting for something, and the step rings
    // that rather than the row three taps away from it.
    anchor: TourAnchor.orders,
  ),
];

/// The steps a shopper who has seen everything below [fromVersion] is owed.
///
/// [TourStore.unseenFrom] supplies the number. A first install asks from 1 and
/// gets the whole tour; somebody who finished version 1 asks from 2 and gets
/// only what version 2 added.
List<TourStep> stepsFrom(int fromVersion, [List<TourStep> steps = tourSteps]) =>
    [
      for (final step in steps)
        if (step.version >= fromVersion) step,
    ];

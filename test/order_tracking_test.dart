import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:gtradea_amazon/features/orders/widgets/order_detail_cards.dart';
import 'package:gtradea_amazon/features/orders/presentation/orders_screen.dart';
import 'package:gtradea_amazon/features/orders/widgets/order_timeline.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';
import 'support/orders.dart';

/// The screen must render the **carrier's** vocabulary, not this app's.
///
/// Every fixture here is built with `carrierTrackingJson`, which knows nothing
/// about [OrderStage]. That matters: the older `trackingJson` fixture labels
/// its steps with the app's own six words, so a test written against it passes
/// whether the screen is showing the server's words or substituting its own.
///
/// What these guard against is the shape the code used to have -- a fixed
/// six-row ladder, with the server's timeline consulted only to look up a date
/// for each local row.
late FakeApi api;

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Order _seed(Map<String, dynamic> tracking) =>
    seedOrder(status: 'processing', trackingOverride: tracking);

Future<void> _open(WidgetTester tester, Order order) async {
  await tester.pumpWidget(_wrap(OrderDetailScreen(orderId: order.id)));
  await tester.pumpAndSettle();
}

/// Narrows a finder to the progress rail.
///
/// A carrier step label legitimately appears twice on this screen: once in the
/// timeline, and once in the status chip, which now reports the step the server
/// marked current rather than a word this app chose. Unscoped assertions match
/// both.
Finder _inTimeline(Finder finder) =>
    find.descendant(of: find.byType(OrderTimeline), matching: finder);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    OrderStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('steps come from the carrier', () {
    testWidgets('a step this app has no name for is still shown', (
      tester,
    ) async {
      // The regression this whole change exists for. CUSTOMS_HELD matches none
      // of the six client-side stage words, so it was decoded, mapped to
      // nothing, and silently dropped -- the one state a shopper most needs to
      // see was the one guaranteed to be invisible.
      _tall(tester);
      final order = _seed(
        carrierTrackingJson(
          steps: [
            (
              stage: 'ORDER_PLACED',
              label: 'Order received',
              status: 'done',
              at: DateTime(2026, 8, 20),
            ),
            (
              stage: 'CUSTOMS_HELD',
              label: 'Held at customs',
              status: 'current',
              at: null,
            ),
          ],
        ),
      );

      await _open(tester, order);

      expect(_inTimeline(find.text('Held at customs')), findsOneWidget);
      // The page now carries a six-stage rail as its summary, which is what
      // the reference design asks for. The point this test exists for is
      // unchanged and asserted where it matters: the carrier's own step is
      // in the journey, and the ladder has not replaced it -- there is no
      // ladder row in the journey, only the carrier's steps.
      expect(_inTimeline(find.text('Packed')), findsNothing);
      expect(_inTimeline(find.text('Out for delivery')), findsNothing);
    });

    testWidgets('the timeline is exactly the steps the server sent', (
      tester,
    ) async {
      _tall(tester);
      final order = _seed(
        carrierTrackingJson(
          steps: [
            (
              stage: 'A',
              label: 'Picked up',
              status: 'done',
              at: DateTime(2026, 8, 20),
            ),
            (stage: 'B', label: 'At the depot', status: 'current', at: null),
          ],
        ),
      );

      await _open(tester, order);

      expect(_inTimeline(find.text('Picked up')), findsOneWidget);
      expect(_inTimeline(find.text('At the depot')), findsOneWidget);
      // Two steps in, two rows out. The rail above draws six stages by
      // design; the journey draws only what the carrier sent.
      expect(_inTimeline(find.text('Order placed')), findsNothing);
      expect(_inTimeline(find.text('Delivered')), findsNothing);
    });

    testWidgets('the server decides which step is current', (tester) async {
      // Deliberately out of order: a later step is done while an earlier one is
      // still current. Anything deriving progress from position gets this
      // wrong. The server said which is which.
      _tall(tester);
      final order = _seed(
        carrierTrackingJson(
          steps: [
            (
              stage: 'A',
              label: 'Awaiting paperwork',
              status: 'current',
              at: null,
            ),
            (
              stage: 'B',
              label: 'Flight booked',
              status: 'done',
              at: DateTime(2026, 8, 21),
            ),
          ],
        ),
      );

      await _open(tester, order);

      final current = tester.widget<Text>(
        _inTimeline(find.text('Awaiting paperwork')),
      );
      final other = tester.widget<Text>(
        _inTimeline(find.text('Flight booked')),
      );
      expect(current.style?.fontWeight, FontWeight.w800);
      expect(other.style?.fontWeight, isNot(FontWeight.w800));
    });

    testWidgets('a step with no time carries no invented one', (tester) async {
      _tall(tester);
      final order = _seed(
        carrierTrackingJson(
          steps: [
            (stage: 'A', label: 'Booked in', status: 'current', at: null),
            (stage: 'B', label: 'Onward leg', status: 'upcoming', at: null),
          ],
        ),
      );

      await _open(tester, order);

      expect(_inTimeline(find.text('Onward leg')), findsOneWidget);
      // The old build printed "Expected <date>" against steps still to come.
      expect(find.textContaining('Expected'), findsNothing);
    });
  });

  group('what the carrier says about the parcel', () {
    testWidgets('the shipment\'s own sentence is shown verbatim', (
      tester,
    ) async {
      _tall(tester);
      final order = _seed(
        carrierTrackingJson(
          stageMessage: 'Cleared customs in Kathmandu',
          steps: [
            (stage: 'A', label: 'In transit', status: 'current', at: null),
          ],
        ),
      );

      await _open(tester, order);

      expect(find.text('Cleared customs in Kathmandu'), findsOneWidget);
    });

    testWidgets('a delay is reported in the carrier\'s words', (tester) async {
      _tall(tester);
      final order = _seed(
        carrierTrackingJson(
          delayed: true,
          delayMessage: 'Held by weather at Rasuwagadhi',
          steps: [
            (stage: 'A', label: 'In transit', status: 'current', at: null),
          ],
        ),
      );

      await _open(tester, order);

      expect(find.text('Held by weather at Rasuwagadhi'), findsOneWidget);
    });

    testWidgets('the update feed is rendered, newest first', (tester) async {
      // Decoded off the wire since tracking was added, and never once drawn.
      _tall(tester);
      final order = _seed(
        carrierTrackingJson(
          steps: [
            (stage: 'A', label: 'In transit', status: 'current', at: null),
          ],
          updates: [
            {
              'at': DateTime(2026, 8, 20).toUtc().toIso8601String(),
              'type': 'shipped',
              'title': 'Left the warehouse',
            },
            {
              'at': DateTime(2026, 8, 22).toUtc().toIso8601String(),
              'type': 'transit',
              'title': 'Arrived in Birgunj',
            },
          ],
        ),
      );

      await _open(tester, order);

      expect(find.text('Latest updates'), findsOneWidget);
      expect(find.text('Left the warehouse'), findsWidgets);

      // Inside the card, which shows the two newest and keeps the rest behind
      // its own link -- so 'first' means first in the card, not on the page.
      Finder inCard(Finder matching) => find.descendant(
        of: find.byType(OrderUpdatesCard),
        matching: matching,
      );
      final newest = tester.getTopLeft(inCard(find.text('Arrived in Birgunj')));
      final older = tester.getTopLeft(inCard(find.text('Left the warehouse')));
      expect(newest.dy, lessThan(older.dy), reason: 'newest first');
    });

    testWidgets('every parcel of a split order is shown', (tester) async {
      // Only shipments.first was ever read, so the second leg of a split order
      // was invisible along with everything on it.
      _tall(tester);
      final order = _seed(
        carrierTrackingJson(
          shipments: [
            carrierShipment(
              shipmentNo: 'AIR-1',
              modeLabel: 'Air freight',
              mode: 'air',
              steps: [
                (
                  stage: 'A',
                  label: 'Flown to Kathmandu',
                  status: 'done',
                  at: null,
                ),
              ],
            ),
            carrierShipment(
              shipmentNo: 'SEA-2',
              modeLabel: 'Sea freight',
              mode: 'sea',
              steps: [
                (
                  stage: 'B',
                  label: 'Loaded at Ningbo',
                  status: 'current',
                  at: null,
                ),
              ],
            ),
          ],
        ),
      );

      await _open(tester, order);

      expect(find.textContaining('Air freight'), findsWidgets);
      expect(find.textContaining('Sea freight'), findsWidgets);
      expect(find.text('Flown to Kathmandu'), findsOneWidget);
      expect(find.text('Loaded at Ningbo'), findsOneWidget);
    });
  });

  group('silence is kept', () {
    testWidgets('nothing is claimed when the server sent nothing', (
      tester,
    ) async {
      _tall(tester);
      final order = _seed(const {});

      await _open(tester, order);

      expect(find.text('Latest updates'), findsNothing);
      expect(find.text('Journey'), findsNothing);
      expect(find.textContaining('Arriving'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('a consignment number is the server\'s to give', () {
      // The app used to withhold this until its own derived stage reached
      // "shipped" -- second-guessing the server about whether its own number
      // was real yet. The carrier's silence is the gate now.
      final withNumber = _seed(
        carrierTrackingJson(
          shipmentNo: 'CN-9',
          steps: [(stage: 'A', label: 'Booked', status: 'current', at: null)],
        ),
      );
      expect(withNumber.trackingNumber(), 'CN-9');

      final withoutNumber = _seed(
        carrierTrackingJson(
          shipmentNo: '',
          steps: [(stage: 'A', label: 'Booked', status: 'current', at: null)],
        ),
      );
      expect(withoutNumber.trackingNumber(), isNull);
    });
  });

  group('the orders list asks for tracking', () {
    testWidgets('an unsettled order has its carrier view fetched', (
      tester,
    ) async {
      // The list drew a status and an arrival date off the tracking payload and
      // then never asked for it, so the arrival line almost never appeared.
      _tall(tester);
      signInForTest();
      api.on('GET', '/orders', body: [orderJson(status: 'processing')]);
      api.on(
        'GET',
        '/orders/order-1/tracking',
        body: carrierTrackingJson(
          statusLabel: 'On the road',
          steps: [
            (stage: 'A', label: 'In transit', status: 'current', at: null),
          ],
        ),
      );

      // Seeded rather than fetched, and never awaited directly: awaiting a
      // store method that goes to the network deadlocks inside testWidgets --
      // the request needs the frames that only pump() delivers, so the await
      // waits for something that cannot happen until the await returns.
      seedOrder(status: 'processing', withTracking: false);

      await tester.pumpWidget(_wrap(const OrdersScreen()));
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path == '/orders/order-1/tracking'),
        isNotEmpty,
      );
      expect(find.text('On the road'), findsWidgets);
    });

    testWidgets('a delivered order is not asked about again', (tester) async {
      _tall(tester);
      signInForTest();
      seedOrder(
        reached: OrderStage.delivered,
        status: 'delivered',
        withTracking: false,
      );

      await tester.pumpWidget(_wrap(const OrdersScreen()));
      await tester.pumpAndSettle();

      // Its status will not change, and a long history would otherwise mean one
      // request per row.
      expect(api.calls.where((c) => c.path.endsWith('/tracking')), isEmpty);
    });

    testWidgets('an order the server has never seen is not asked about', (
      tester,
    ) async {
      // place() mints a local 'GT…' id. Asking about it is a guaranteed 404 on
      // every screen open.
      _tall(tester);
      signInForTest();
      OrderStore.instance.place(
        lines: const [
          CartLine(productId: 'p', title: 'A thing', unitPrice: 100),
        ],
        delivery: 100,
        recipient: 'Rabi',
        address: 'Jhamsikhel, Lalitpur',
        paymentState: PaymentState.pending,
      );

      await tester.pumpWidget(_wrap(const OrdersScreen()));
      await tester.pumpAndSettle();

      expect(api.calls.where((c) => c.path.endsWith('/tracking')), isEmpty);
    });
  });
}

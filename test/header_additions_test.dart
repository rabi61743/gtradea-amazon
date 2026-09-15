import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/address/presentation/address_picker_sheet.dart';
import 'package:gtradea_amazon/features/address/presentation/delivery_location_button.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/auth/presentation/auth_screen.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/home/widgets/department_tabs.dart';
import 'package:gtradea_amazon/features/home/widgets/delivery_points_card.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notifications_screen.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_tracker_button.dart';
import 'package:gtradea_amazon/features/support/data/support_repository.dart';
import 'package:gtradea_amazon/features/support/presentation/support_button.dart';
import 'package:gtradea_amazon/features/support/presentation/support_tickets_screen.dart';
import 'package:gtradea_amazon/features/support/presentation/ticket_detail_screen.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:gtradea_amazon/shared/widgets/brand_lockup.dart';
import 'package:gtradea_amazon/shared/widgets/brand_wordmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// A default address that reads as the reference's "Lalitpur, Nepal".
///
/// Added through the store's own API rather than a test-only seeder, so the
/// path the app uses is the path the header then reads back.
void _seedLalitpur() {
  AddressStore.instance.add(
    label: AddressLabel.home,
    fullName: 'Rabi',
    phone: '9800000000',
    province: 'Nepal',
    city: 'Lalitpur',
    area: '',
    makeDefault: true,
  );
}

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

/// Tall enough to build the whole shell without the hero banner's copy column
/// overflowing, which it does at 360x667 for reasons that predate the band and
/// have nothing to do with it.
void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 4400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Map<String, dynamic> _ticketJson({
  String id = 'ticket-1',
  String status = 'open',
  String subject = 'Parcel arrived damaged',
}) => {
  'id': id,
  'ticket_number': 'TK-100',
  'subject': subject,
  'description': 'The box was torn open.',
  'status': status,
  'category': 'shipping',
  'created_at': '2026-08-20T10:00:00Z',
  'updated_at': '2026-08-21T10:00:00Z',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    AuthStore.instance.resetForTest();
    AddressStore.instance.resetForTest();
  });

  group('the band', () {
    testWidgets('is one gradient behind the header and the strip', (
      tester,
    ) async {
      // The whole point of painting it in the shell rather than in each of
      // them. Two top-to-bottom gradients stacked would run the ramp twice and
      // snap back to the dark end at the join -- the seam this header has
      // already had removed once, reintroduced as a gradient.
      _tallPhone(tester);
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      final bands = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.gradient == AppColors.brandBand);

      expect(bands, hasLength(1));
    });

    testWidgets('neither child paints a background of its own', (tester) async {
      // If one of them starts doing so again, it covers its slice of the ramp
      // with a flat colour and the band goes back to being two-tone.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final flat = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(SearchHeader),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where(
            (d) =>
                d.color == AppColors.trustBlueDeep ||
                d.color == AppColors.trustBlue ||
                d.color == AppColors.brandBandTop,
          );

      expect(flat, isEmpty);
    });

    testWidgets('runs behind the status bar, not up to it', (tester) async {
      // The band absorbs the status bar inset itself rather than sitting under
      // a SafeArea, so the teal reaches the top of the screen. A gradient that
      // started below it would leave a white strip above the dark end.
      _tallPhone(tester);
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      final band = find
          .byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).gradient == AppColors.brandBand,
          )
          .first;

      expect(tester.getRect(band).top, 0);
    });
  });

  group('the header still holds its shape', () {
    testWidgets('the brand keeps its inset, at the size the screen allows', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final logo = tester.getRect(find.byType(BrandLockup));
      expect(logo.left, 16, reason: 'same inset as before');

      // 30 on a phone this width, 26 below 360 and 34 from a tablet up: the
      // lockup grew when the header did, and it is sized rather than fixed so
      // it cannot crowd a small screen.
      final lockup = tester.widget<BrandLockup>(find.byType(BrandLockup));
      expect(lockup.height, 30);
      // The mark inside it is the on-dark artwork, unchanged.
      final mark = tester.widget<BrandWordmark>(find.byType(BrandWordmark));
      expect(mark.height, lockup.height);
    });

    testWidgets('the action group ends on the margin', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      // The group is a block now rather than three loose IconButtons, so it is
      // the block that lands on the margin -- and its last tile with it. That
      // is the bell again: messages and notifications were swapped by request,
      // so the last thing on the row is notifications.
      final group = tester.getRect(find.byType(NotificationBell));

      expect(group.right, lessThanOrEqualTo(width - 16));
      expect(group.right, greaterThan(width - 40), reason: 'on the margin');
    });

    testWidgets('the search pill spans the header, compactly', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final pill = tester.getRect(find.byKey(SearchHeader.pillKey));

      expect(pill.left, 16);
      expect(pill.right, width - 16);
      // 38 by request: the pill was made more compact. It is short for a tap
      // target and gets away with it because it spans the header -- the height
      // is the only tight dimension.
      //
      // Compared loosely because this measures the laid-out rect, not the
      // widget: the pill is a literal `SizedBox(height: 38)`, but the row above
      // it now ends on a fractional y, and bottom-minus-top came back as
      // 38.000000000000014. Pinning the exact double would be pinning the
      // arithmetic of whatever sits above the pill.
      expect(pill.height, moreOrLessEquals(38));
    });

    testWidgets('the microphone and the camera sit close together', (
      tester,
    ) async {
      // Pinned because this silently did not work once. Both buttons were
      // given a 26pt box and stayed 48pt apart: an IconButton takes Material's
      // padded tap target from the theme and expands to a 48pt minimum
      // *outside* its constraints, so the constant read 26 while the layout
      // never moved.
      //
      // What is asserted is therefore the rendered distance between the two
      // glyphs, never the constant that is supposed to produce it -- measuring
      // the constant is what made the first attempt look finished.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          SearchHeader(
            onTap: () {},
            onVoiceResult: (_) {},
            onImageSearch: () {},
          ),
        ),
      );
      await tester.pump();

      final mic = tester.getRect(find.byIcon(Icons.mic_none));
      final cam = tester.getRect(find.byIcon(Icons.center_focus_weak));

      expect(
        cam.left - mic.right,
        lessThanOrEqualTo(10),
        reason: 'was 30 while the tap target overruled the box',
      );
      expect(
        cam.left - mic.right,
        greaterThan(0),
        reason: 'close together, not overlapping',
      );
      expect(mic.top, cam.top, reason: 'and still level with each other');
    });

    testWidgets('the actions keep their order: orders, messages, alerts', (
      tester,
    ) async {
      // Messages and notifications were swapped by request. The order is the
      // assertion: orders, then the conversation about them, then the alerts.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final tracker = tester.getRect(find.byType(OrderTrackerButton));
      final messages = tester.getRect(find.byType(SupportButton));
      final bell = tester.getRect(find.byType(NotificationBell));

      expect(tracker.right, lessThanOrEqualTo(messages.left));
      expect(messages.right, lessThanOrEqualTo(bell.left));
    });

    testWidgets('each action says what it is', (tester) async {
      // The words are the whole point of the group: three bare glyphs on a
      // teal band were a guessing game, and the truck read as delivery rather
      // than as orders.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      for (final word in ['Orders', 'Notifications', 'Messages']) {
        expect(
          find.descendant(
            of: find.byType(SearchHeader),
            matching: find.text(word),
          ),
          findsOneWidget,
          reason: word,
        );
      }
    });

    testWidgets('nothing overflows once both are added', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('the three icons are one size, and it is the smaller one', (
      tester,
    ) async {
      // They have to agree with each other and with the header's right inset,
      // which is derived from the same number. Three buttons each carrying
      // their own default is how the bell wandered off its margin.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final cart = tester.widget<SupportButton>(find.byType(SupportButton));
      final tracker = tester.widget<OrderTrackerButton>(
        find.byType(OrderTrackerButton),
      );
      final bell = tester.widget<NotificationBell>(
        find.byType(NotificationBell),
      );

      expect(cart.size, tracker.size);
      expect(tracker.size, bell.size);
      expect(cart.size, lessThan(24), reason: 'smaller than Material default');
    });

    testWidgets('the glyphs are drawn at the size the row asks for', (
      tester,
    ) async {
      // The size passed to the button and the size actually rendered are two
      // different claims. An IconButton that ignored the parameter would leave
      // this passing on the widget's field while the header looked unchanged.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final bell = tester.widget<NotificationBell>(
        find.byType(NotificationBell),
      );
      final glyph = tester.widget<Icon>(
        find.descendant(
          of: find.byType(NotificationBell),
          matching: find.byIcon(Icons.notifications_none),
        ),
      );

      expect(glyph.size, bell.size);
    });

    testWidgets('and the location is the reference card, chevron included', (
      tester,
    ) async {
      // This used to pin a small outlined pin and no chevron: the compact
      // address chip shared its row with the coins and could not afford them.
      // The Delivery + Points card now follows its
      // reference -- a solid pin, still under Material's 24, and the
      // chevron-down that says the address can be changed. Recorded rather
      // than deleted, because the old rule was deliberate.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final pin = tester.widget<Icon>(
        find.descendant(
          of: find.byType(DeliveryPointsCard),
          matching: find.byIcon(Icons.location_on),
        ),
      );
      expect(pin.size, lessThan(24));
      expect(
        find.descendant(
          of: find.byType(DeliveryPointsCard),
          matching: find.byIcon(Icons.keyboard_arrow_down),
        ),
        findsOneWidget,
      );
    });

    testWidgets('and the group is tight without losing the targets', (
      tester,
    ) async {
      // The tiles are equal columns rather than three boxes sized by how long
      // their words are, and each is still something a thumb can hit: the
      // glyph shrank when the label arrived under it, the target did not.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final sizes = <String, Size>{};
      for (final button in [
        OrderTrackerButton,
        NotificationBell,
        SupportButton,
      ]) {
        final box = tester.getSize(
          find.descendant(
            of: find.byType(button),
            matching: find.byType(InkWell),
          ),
        );
        sizes['$button'] = box;
        expect(box.width, greaterThanOrEqualTo(44), reason: '$button');
        expect(box.height, greaterThanOrEqualTo(36), reason: '$button');
      }

      expect(sizes.values.map((s) => s.width).toSet(), hasLength(1));
    });

    testWidgets('compacting the three did not grow the blurred field', (
      tester,
    ) async {
      // The condition the compaction was asked under: smaller glyphs and
      // smaller words inside the *existing* block, not a taller block. It was
      // 52 tall when the tiles carried 20pt glyphs over 10.5pt labels; it is
      // 44 now, which is the tap-target floor (36) plus the block's own 4pt of
      // padding, top and bottom.
      //
      // Pinned against the field beside it rather than only as a number: the
      // two blurred fields read as a pair, and the actions block used to
      // overhang its neighbour by ten points.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      Size block(Type of) => tester.getSize(
        find
            .ancestor(of: find.byType(of), matching: find.byType(Container))
            .first,
      );

      final actions = block(SupportButton);
      expect(actions.height, lessThanOrEqualTo(44));
      expect(
        (actions.height - tester.getSize(find.byType(DeliveryPointsCard)).height)
            .abs(),
        lessThanOrEqualTo(2),
        reason: 'level with the Delivery + Points card beside it',
      );
    });
  });

  group('the delivery line', () {
    testWidgets('asks for a location when none is set', (tester) async {
      // Never a guess. Naming a city nobody chose would be worse than asking.
      _phone(tester);
      await tester.pumpWidget(_wrap(const DeliveryLocationButton()));
      await tester.pump();

      expect(find.text('Set delivery location'), findsOneWidget);
      expect(find.text('Deliver to'), findsNothing);
    });

    testWidgets('names the default address once there is one', (tester) async {
      _phone(tester);
      _seedLalitpur();

      await tester.pumpWidget(_wrap(const DeliveryLocationButton()));
      await tester.pump();

      expect(find.text('Deliver to'), findsOneWidget);
      expect(find.text('Lalitpur, Nepal'), findsOneWidget);
    });

    testWidgets('opens the address picker', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const DeliveryLocationButton()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DeliveryLocationButton));
      await tester.pumpAndSettle();

      expect(find.byType(AddressPickerSheet), findsOneWidget);
    });

    testWidgets('reads as one control to a screen reader', (tester) async {
      // Not "location pin, Deliver to, Lalitpur, Nepal, arrow" as four nodes.
      _phone(tester);
      final handle = tester.ensureSemantics();
      _seedLalitpur();

      await tester.pumpWidget(_wrap(const DeliveryLocationButton()));
      await tester.pump();

      expect(
        find.bySemanticsLabel(
          'Delivering to Lalitpur, Nepal. Change delivery location.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group('the chat icon', () {
    testWidgets('opens the conversations for a signed-in shopper', (
      tester,
    ) async {
      signInForTest();
      api.on('GET', '/support/tickets', body: [_ticketJson()]);

      _phone(tester);
      await tester.pumpWidget(_wrap(const SupportButton()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SupportButton));
      await tester.pumpAndSettle();

      expect(find.byType(SupportTicketsScreen), findsOneWidget);
      expect(find.text('Parcel arrived damaged'), findsOneWidget);
    });

    testWidgets('sends a guest to sign in rather than to a 401', (
      tester,
    ) async {
      // The tickets endpoint answers 401 to a guest, so opening the list would
      // show an error where a conversation should be.
      _phone(tester);
      await tester.pumpWidget(_wrap(const SupportButton()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SupportButton));
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.byType(SupportTicketsScreen), findsNothing);
    });

    testWidgets('carries no badge it cannot compute', (tester) async {
      // The bell and the tracker each badge a real count. This endpoint gives
      // no unread figure, and a dot invented from nothing would claim someone
      // is waiting when nobody knows.
      //
      // The tile it shares with those two always builds the badge widget and
      // hides it at zero, so what is asserted is that nothing is shown rather
      // than that nothing is built.
      _phone(tester);
      await tester.pumpWidget(_wrap(const SupportButton()));
      await tester.pump();

      for (final badge in tester.widgetList<Badge>(find.byType(Badge))) {
        expect(badge.isLabelVisible, isFalse);
      }
    });
  });

  group('a conversation', () {
    setUp(() {
      signInForTest();
      api.on('GET', '/support/tickets/ticket-1', body: _ticketJson());
    });

    testWidgets('shows the thread, mine and theirs', (tester) async {
      api.on(
        'GET',
        '/support/tickets/ticket-1/messages',
        body: [
          {
            'id': 'm1',
            'sender_type': 'user',
            'message': 'Any update on this?',
            'created_at': '2026-08-21T09:00:00Z',
          },
          {
            'id': 'm2',
            'sender_type': 'support',
            'message': 'Refunding today.',
            'created_at': '2026-08-21T10:00:00Z',
          },
        ],
      );

      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          TicketDetailScreen(ticket: SupportTicket.fromJson(_ticketJson())),
        ),
      );
      await tester.pumpAndSettle();

      // The ticket's own description opens the thread -- the server does not
      // repeat it as a message.
      expect(find.text('The box was torn open.'), findsOneWidget);
      expect(find.text('Any update on this?'), findsOneWidget);
      expect(find.text('Refunding today.'), findsOneWidget);
    });

    testWidgets('sends a reply and reloads the thread', (tester) async {
      var sent = 0;
      api.on('GET', '/support/tickets/ticket-1/messages', body: const []);
      api.onCall('POST', '/support/tickets/ticket-1/messages', (call) {
        sent++;
        return reply({'ok': true});
      });

      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          TicketDetailScreen(ticket: SupportTicket.fromJson(_ticketJson())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Still waiting');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(sent, 1);
      final body = api.calls
          .lastWhere(
            (c) =>
                c.path == '/support/tickets/ticket-1/messages' &&
                c.method == 'POST',
          )
          .json;
      expect(body['message'], 'Still waiting');
    });

    testWidgets('offers no composer on a closed thread', (tester) async {
      // The server rejects a reply to a closed ticket, so a box here would be
      // an invitation to write something that goes nowhere.
      api.on(
        'GET',
        '/support/tickets/ticket-1',
        body: _ticketJson(status: 'closed'),
      );
      api.on('GET', '/support/tickets/ticket-1/messages', body: const []);

      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          TicketDetailScreen(
            ticket: SupportTicket.fromJson(_ticketJson(status: 'closed')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining('This conversation is closed'),
        findsOneWidget,
      );
    });

    testWidgets('says awaiting your reply in the shoppers own terms', (
      tester,
    ) async {
      // The raw enum is written from support's side and reads backwards.
      expect(
        customerTicketStatusLabel('waiting_customer'),
        'Awaiting your reply',
      );
      expect(customerTicketStatusLabel('in_progress'), 'In progress');
    });
  });

  group('the header is one surface', () {
    testWidgets('the header paints no band colour of its own', (tester) async {
      // These two used to assert that every surface in here was the same flat
      // teal, because the band had briefly been two tones and the join read as
      // a seam. The band is a gradient now, painted once by the shell -- so the
      // rule that keeps the seam away is the opposite one: nothing in here
      // paints a band colour at all. A flat patch on a ramp is the same seam
      // wearing a different hat.
      _phone(tester);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final painted = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SearchHeader),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.color)
          .whereType<Color>()
          .toSet();

      expect(painted, isNot(contains(AppColors.trustBlueDeep)));
      expect(painted, isNot(contains(AppColors.trustBlue)));
      expect(painted, isNot(contains(AppColors.brandBandTop)));
    });

    testWidgets('nor does the department strip', (tester) async {
      // The strip is a separate widget drawn under the header, on the same
      // band. If it painted its own colour the ramp would stop at the join.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          DepartmentTabs(
            categories: const [],
            selectedCid: null,
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      final painted = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(DepartmentTabs),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.color)
          .whereType<Color>();

      expect(painted, isNot(contains(AppColors.trustBlueDeep)));
      expect(painted, isNot(contains(AppColors.trustBlue)));
    });
  });
}

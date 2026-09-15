import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/home/widgets/delivery_points_card.dart';
import 'package:gtradea_amazon/features/home/widgets/product_rail.dart'
    show formatGrouped;
import 'package:gtradea_amazon/features/wallet/data/coin_balance_store.dart';

Widget _wrap({double textScale = 1}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: const Scaffold(
      backgroundColor: Color(0xFF1F6070),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: DeliveryPointsCard(),
      ),
    ),
  ),
);

Address _jawalakhel() => AddressStore.instance.add(
  label: AddressLabel.home,
  fullName: 'Rabi',
  phone: '9800000000',
  province: 'Bagmati',
  city: 'Lalitpur',
  area: 'Jawalakhel, house 12',
  makeDefault: true,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AddressStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    CoinBalanceStore.instance.resetForTest();
  });

  test('the place is the neighbourhood and the city, like the reference', () {
    // "Jawalakhel, house 12" + Lalitpur reads "Jawalakhel, Lalitpur": the
    // house number and the province are not what a header has room for.
    expect(DeliveryPointsCard.placeOf(_jawalakhel()), 'Jawalakhel, Lalitpur');
    expect(DeliveryPointsCard.placeOf(null), isNull);
  });

  test('a detected address skips the province and postcode for the place', () {
    // The real address on the test phone, as the location detector wrote it:
    // province and postcode first, neighbourhood last.
    const detected = Address(
      id: 'a1',
      label: AddressLabel.home,
      fullName: 'Prabhakar Adhikari',
      phone: '',
      province: 'Bagmati',
      city: 'Lalitpur',
      area: 'Bagmati Province 44600, Ekantakuna',
      postalCode: '44600',
    );
    expect(DeliveryPointsCard.placeOf(detected), 'Ekantakuna, Lalitpur');

    // Nothing but the province and a postcode: the city alone, not a blank.
    const bare = Address(
      id: 'a2',
      label: AddressLabel.home,
      fullName: 'R',
      phone: '',
      province: 'Bagmati',
      city: 'Lalitpur',
      area: 'Bagmati Province, 44600',
    );
    expect(DeliveryPointsCard.placeOf(bare), 'Lalitpur');
  });

  test('the dense form names the neighbourhood alone, or the city', () {
    expect(
      DeliveryPointsCard.placeOf(_jawalakhel(), withCity: false),
      'Jawalakhel',
    );
    const noArea = Address(
      id: 'a3',
      label: AddressLabel.home,
      fullName: 'R',
      phone: '',
      province: 'Bagmati',
      city: 'Lalitpur',
      area: 'Bagmati Province 44600',
    );
    expect(DeliveryPointsCard.placeOf(noArea, withCity: false), 'Lalitpur');
  });

  testWidgets('a phone-width card drops the arrows for the address', (
    tester,
  ) async {
    _jawalakhel();
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap());

    expect(find.text('Jawalakhel'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.text('Points'), findsOneWidget);
  });

  testWidgets('shows Deliver to, the place, the balance and Points', (
    tester,
  ) async {
    _jawalakhel();
    await tester.pumpWidget(_wrap());

    expect(find.text('Deliver to'), findsOneWidget);
    expect(find.text('Jawalakhel, Lalitpur'), findsOneWidget);
    expect(
      find.text(formatGrouped(CoinBalanceStore.instance.balance)),
      findsOneWidget,
    );
    expect(find.text('Points'), findsOneWidget);
    expect(find.text('P'), findsOneWidget, reason: 'the gold P coin');
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('asks for a location when none is set', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.text('Set delivery location'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 406.0]) {
    testWidgets('nothing overflows at $width dp, even at 2x text', (
      tester,
    ) async {
      _jawalakhel();
      tester.view.physicalSize = Size(width * 3, 900);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(_wrap(textScale: scale));
        expect(tester.takeException(), isNull, reason: '$width dp at ${scale}x');
      }
    });
  }
}

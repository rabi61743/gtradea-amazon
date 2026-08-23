import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/address/presentation/address_form_sheet.dart';
import 'package:gtradea_amazon/features/address/presentation/address_list_screen.dart';
import 'package:gtradea_amazon/features/address/presentation/address_picker_sheet.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Address _add({
  String name = 'Rabi Yadav',
  String city = 'Lalitpur',
  String area = 'Jhamsikhel, house 12',
  AddressLabel label = AddressLabel.home,
  bool makeDefault = false,
}) =>
    AddressStore.instance.add(
      label: label,
      fullName: name,
      phone: '9800000000',
      province: 'Bagmati',
      city: city,
      area: area,
      makeDefault: makeDefault,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AddressStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('Address', () {
    test('reads as one line and as a full address', () {
      const address = Address(
        id: 'a',
        label: AddressLabel.home,
        fullName: 'Rabi',
        phone: '9800000000',
        province: 'Bagmati',
        city: 'Lalitpur',
        area: 'Jhamsikhel',
        landmark: 'Summit Hotel',
      );

      expect(address.oneLine, 'Jhamsikhel, Lalitpur, Bagmati');
      expect(address.full, contains('Near Summit Hotel'));
    });

    test('a blank landmark is left out rather than printed as "Near "', () {
      const address = Address(
        id: 'a',
        label: AddressLabel.home,
        fullName: 'Rabi',
        phone: '',
        province: 'Bagmati',
        city: 'Lalitpur',
        area: 'Jhamsikhel',
        landmark: '   ',
      );
      expect(address.full, isNot(contains('Near')));
    });
  });

  group('AddressStore', () {
    test('the first address saved becomes the default on its own', () {
      final first = _add();
      expect(AddressStore.instance.isDefault(first.id), isTrue);
    });

    test('a later address only becomes default when asked', () {
      final first = _add();
      final second = _add(name: 'Sita', city: 'Kathmandu');
      expect(AddressStore.instance.isDefault(first.id), isTrue);

      AddressStore.instance.setDefault(second.id);
      expect(AddressStore.instance.isDefault(second.id), isTrue);
      expect(AddressStore.instance.isDefault(first.id), isFalse);
    });

    test('deleting the default falls back rather than leaving none', () {
      final first = _add();
      final second = _add(name: 'Sita', city: 'Kathmandu');
      AddressStore.instance.setDefault(second.id);

      AddressStore.instance.remove(second.id);
      // A book with an address in it must never report "no address selected".
      expect(AddressStore.instance.defaultAddress?.id, first.id);
    });

    test('an empty book has no default', () {
      expect(AddressStore.instance.defaultAddress, isNull);
    });

    test('editing keeps the id and the default', () {
      final address = _add();
      AddressStore.instance.update(address.copyWith(area: 'Kupondole 44'));

      expect(AddressStore.instance.count, 1);
      expect(AddressStore.instance.byId(address.id)?.area, 'Kupondole 44');
      expect(AddressStore.instance.isDefault(address.id), isTrue);
    });

    test('search matches name, area, city and label', () {
      _add(name: 'Rabi Yadav', city: 'Lalitpur', area: 'Jhamsikhel');
      _add(
        name: 'Sita Sharma',
        city: 'Pokhara',
        area: 'Lakeside',
        label: AddressLabel.work,
      );

      expect(AddressStore.instance.search('sita').length, 1);
      expect(AddressStore.instance.search('lakeside').length, 1);
      expect(AddressStore.instance.search('pokhara').length, 1);
      expect(AddressStore.instance.search('work').length, 1);
      expect(AddressStore.instance.search('').length, 2,
          reason: 'an empty query is not a filter');
      expect(AddressStore.instance.search('nowhere'), isEmpty);
    });

    test('survives a reload, default and all', () async {
      final first = _add();
      final second = _add(name: 'Sita', city: 'Kathmandu');
      AddressStore.instance.setDefault(second.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      AddressStore.instance.resetForTest();
      await AddressStore.instance.load();

      expect(AddressStore.instance.count, 2);
      expect(AddressStore.instance.isDefault(second.id), isTrue);
      expect(AddressStore.instance.byId(first.id), isNotNull);
    });

    test('a corrupt book degrades to empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'gtradea_addresses': 'not json'});
      AddressStore.instance.resetForTest();
      await AddressStore.instance.load();
      expect(AddressStore.instance.isEmpty, isTrue);
    });

    test('an address missing what a courier needs is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_addresses': '{"addresses":['
            '{"id":"1","fullName":"No area","city":"Lalitpur"},'
            '{"id":"2","fullName":"No city","area":"Jhamsikhel"},'
            '{"id":"3","fullName":"Fine","area":"Jhamsikhel","city":"Lalitpur"}'
            '],"default":"3"}',
      });
      AddressStore.instance.resetForTest();
      await AddressStore.instance.load();

      // A row with blanks in it looks like a bug and is undeliverable anyway.
      expect(AddressStore.instance.addresses.map((a) => a.id), ['3']);
    });

    test('a guest book follows the shopper into their account', () async {
      _add();
      AddressStore.instance.bindToAuth();

      AuthStore.instance.signIn(email: 'rabi@example.com');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(AddressStore.instance.count, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('gtradea_addresses'), isNull,
          reason: 'the guest copy is cleared once carried over');
    });
  });

  group('AddressPickerSheet', () {
    testWidgets('an empty book offers a way forward, not a wall',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AddressPickerSheet.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('No addresses yet'), findsOneWidget);
      // The reference put a padlock and a login wall here. A guest can order
      // in this app, so they get cities to start from instead.
      expect(find.text('Kathmandu'), findsOneWidget);
      expect(find.text('Add a new address'), findsOneWidget);
      expect(find.textContaining('shopping as a guest'), findsOneWidget);
    });

    testWidgets('saved addresses are listed with the default marked',
        (tester) async {
      _useTallWindow(tester);
      _add();
      _add(name: 'Sita Sharma', city: 'Pokhara', label: AddressLabel.work);

      await tester.pumpWidget(_wrap(const AddressPickerSheet()));
      await tester.pumpAndSettle();

      expect(find.text('Rabi Yadav'), findsOneWidget);
      expect(find.text('Sita Sharma'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('the search box only appears once the book needs one',
        (tester) async {
      _useTallWindow(tester);
      _add();
      _add(name: 'Sita', city: 'Pokhara');

      await tester.pumpWidget(_wrap(const AddressPickerSheet()));
      await tester.pumpAndSettle();
      // Two addresses do not need searching; a box above them is furniture.
      expect(find.byType(TextField), findsNothing);

      _add(name: 'Hari', city: 'Butwal');
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('searching narrows the list and says so when nothing matches',
        (tester) async {
      _useTallWindow(tester);
      _add(name: 'Rabi Yadav', city: 'Lalitpur');
      _add(name: 'Sita Sharma', city: 'Pokhara');
      _add(name: 'Hari Thapa', city: 'Butwal');

      await tester.pumpWidget(_wrap(const AddressPickerSheet()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'pokhara');
      await tester.pumpAndSettle();
      expect(find.text('Sita Sharma'), findsOneWidget);
      expect(find.text('Rabi Yadav'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No saved address matches'), findsOneWidget);
    });
  });

  group('AddressFormSheet', () {
    testWidgets('rejects an address a courier could not use', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const AddressFormSheet()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.text('Enter a phone number'), findsOneWidget);
      expect(find.text('Enter a city'), findsOneWidget);
      expect(AddressStore.instance.isEmpty, isTrue);
    });

    testWidgets('a filled form saves and becomes the default', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const AddressFormSheet()));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name'), 'Rabi Yadav');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone'), '9800000000');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'City or district'), 'Lalitpur');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tole, street and house number'),
        'Jhamsikhel, house 12',
      );
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();

      expect(AddressStore.instance.count, 1);
      final saved = AddressStore.instance.addresses.single;
      expect(saved.fullName, 'Rabi Yadav');
      expect(saved.city, 'Lalitpur');
      expect(saved.label, AddressLabel.home,
          reason: 'Home is the default label, untouched');
      expect(AddressStore.instance.isDefault(saved.id), isTrue);
    });

    testWidgets('a province the dropdown does not know does not crash it',
        (tester) async {
      _useTallWindow(tester);
      // A geocoder can return 'Bagmati Province' or a district name. Handing
      // that straight to the dropdown asserts, and the form never opens at
      // all -- so the seed is guarded rather than trusted.
      await tester.pumpWidget(_wrap(
        const AddressFormSheet(
          seed: Address(
            id: '',
            label: AddressLabel.home,
            fullName: '',
            phone: '',
            province: 'Province No. 3',
            city: 'Kathmandu',
            area: '',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('New address'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Kathmandu'), findsOneWidget);
    });

    testWidgets('a seeded form is still an add, not an edit', (tester) async {
      _useTallWindow(tester);
      // The picker seeds city and province from a chip. Treating that as an
      // edit would try to update a row with no id and save nothing at all.
      await tester.pumpWidget(_wrap(
        const AddressFormSheet(
          seed: Address(
            id: '',
            label: AddressLabel.home,
            fullName: '',
            phone: '',
            province: 'Gandaki',
            city: 'Pokhara',
            area: '',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('New address'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name'), 'Sita');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone'), '9800000000');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tole, street and house number'),
        'Lakeside',
      );
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();

      expect(AddressStore.instance.count, 1);
      expect(AddressStore.instance.addresses.single.city, 'Pokhara');
    });

    testWidgets('editing an existing address updates it in place',
        (tester) async {
      _useTallWindow(tester);
      final address = _add();

      await tester.pumpWidget(_wrap(AddressFormSheet(existing: address)));
      await tester.pumpAndSettle();

      expect(find.text('Edit address'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tole, street and house number'),
        'Kupondole 44',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(AddressStore.instance.count, 1, reason: 'edited, not duplicated');
      expect(AddressStore.instance.byId(address.id)?.area, 'Kupondole 44');
    });
  });

  group('AddressListScreen', () {
    testWidgets('explains itself when empty', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const AddressListScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No addresses saved'), findsOneWidget);
    });

    testWidgets('shows the default as a statement, not a button',
        (tester) async {
      _useTallWindow(tester);
      _add();
      _add(name: 'Sita', city: 'Pokhara');

      await tester.pumpWidget(_wrap(const AddressListScreen()));
      await tester.pumpAndSettle();

      // One is the default and says so; the other offers to become it.
      expect(find.text('Default address'), findsOneWidget);
      expect(find.text('Set as default'), findsOneWidget);
    });

    testWidgets('setting a default moves it', (tester) async {
      _useTallWindow(tester);
      _add();
      final second = _add(name: 'Sita', city: 'Pokhara');

      await tester.pumpWidget(_wrap(const AddressListScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set as default'));
      await tester.pumpAndSettle();
      expect(AddressStore.instance.isDefault(second.id), isTrue);
    });

    testWidgets('deleting asks first, and backing out keeps it',
        (tester) async {
      _useTallWindow(tester);
      _add();

      await tester.pumpWidget(_wrap(const AddressListScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this address?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(AddressStore.instance.count, 1);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(AddressStore.instance.isEmpty, isTrue);
    });
  });
}

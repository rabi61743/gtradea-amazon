import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:gtradea_amazon/features/orders/widgets/order_status_chip.dart';
import 'package:gtradea_amazon/features/orders/widgets/order_status_colors.dart';

import 'support/orders.dart';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final hi = math.max(_luminance(a), _luminance(b));
  final lo = math.min(_luminance(a), _luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

const _white = Color(0xFFFFFFFF);

/// The order page, at a given stage.
Future<Order> _open(WidgetTester tester, OrderStage stage) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final order = seedOrder(reached: stage, status: stage.name);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OrderDetailScreen(orderId: order.id),
    ),
  );
  await tester.pump();
  return order;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OrderStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('the status colours', () {
    test('are the exact hexes the brand specifies', () {
      // Byte-for-byte: a status colour that drifts is a status that means
      // something slightly different on every screen it appears on.
      expect(_hex(OrderStatusPalette.markFor(OrderStage.placed)), '#267488');
      expect(_hex(OrderStatusPalette.markFor(OrderStage.confirmed)), '#22C55E');
      expect(_hex(OrderStatusPalette.markFor(OrderStage.packed)), '#F59E0B');
      expect(_hex(OrderStatusPalette.markFor(OrderStage.shipped)), '#2563EB');
      expect(
        _hex(OrderStatusPalette.markFor(OrderStage.outForDelivery)),
        '#E94724',
      );
      expect(_hex(OrderStatusPalette.markFor(OrderStage.delivered)), '#16A34A');
      expect(_hex(OrderStatusPalette.upcoming), '#E5E7EB');
    });

    test('and every one of them is readable where it carries words', () {
      // Three of the specified colours cannot be read as small text -- the
      // green measures 2.28:1, the amber 2.15:1. The ink is the same colour
      // taken down until it can be, which is why a label never wears the raw
      // hex.
      for (final stage in OrderStage.values) {
        final ink = OrderStatusPalette.inkFor(stage);
        expect(
          _contrast(ink, _white),
          greaterThan(stage == OrderStage.outForDelivery ? 3.0 : 4.5),
          reason: stage.name,
        );
      }
    });

    test('and the ink is the same colour, not a different one', () {
      // Derived rather than picked: the amber ink is the brand amber with the
      // light turned down, so "packed" is one colour whether it is a dot or a
      // sentence.
      final amber = HSLColor.fromColor(OrderStatusPalette.warmAmber);
      final ink = HSLColor.fromColor(OrderStatusPalette.amberInk);

      expect((amber.hue - ink.hue).abs(), lessThan(5));
      expect(ink.lightness, lessThan(amber.lightness));
    });
  });

  group('on the order page', () {
    testWidgets('the badge wears the stage the server reports', (tester) async {
      // The chip the orders list draws, pumped on its own so the assertion is
      // about the badge rather than about where a page scrolled to.
      for (final stage in OrderStage.values) {
        OrderStore.instance.resetForTest();
        final order = seedOrder(reached: stage, status: stage.name);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: OrderStatusChip(order: order, now: DateTime.now()),
            ),
          ),
        );
        await tester.pump();

        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byType(OrderStatusChip),
            matching: find.byType(Icon),
          ),
        );
        expect(
          icon.color,
          OrderStatusPalette.markFor(stage),
          reason: 'mark for ${stage.name}',
        );

        final label = tester.widget<Text>(
          find.descendant(
            of: find.byType(OrderStatusChip),
            matching: find.byType(Text),
          ),
        );
        expect(
          label.style?.color,
          OrderStatusPalette.inkFor(stage),
          reason: 'ink for ${stage.name}',
        );
      }
    });

    testWidgets('and so does the pill at the top of the order page', (
      tester,
    ) async {
      await _open(tester, OrderStage.shipped);

      final label = tester.widget<Text>(find.text('Shipped').first);
      expect(label.style?.color, OrderStatusPalette.inkFor(OrderStage.shipped));
    });

    testWidgets('and the journey steps take the stage they belong to', (
      tester,
    ) async {
      // The carrier names its own steps; each is coloured by the stage its
      // words map to, so 'Shipped' is the same blue whether it is a rung on
      // the rail or a row in the journey.
      await _open(tester, OrderStage.shipped);

      final marks = tester
          .widgetList<Container>(find.byType(Container))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .toList();

      expect(
        marks,
        contains(OrderStatusPalette.markFor(OrderStage.shipped)),
        reason: 'the shipped blue is on the page',
      );
    });

    testWidgets('and an upcoming step is Mountain Grey until it happens', (
      tester,
    ) async {
      await _open(tester, OrderStage.packed);

      // The line into a stage that has not been reached.
      final lines = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration == null && c.color != null)
          .map((c) => c.color)
          .toList();

      expect(
        lines,
        contains(OrderStatusPalette.upcoming),
        reason: 'the road ahead is grey',
      );
    });
  });
}

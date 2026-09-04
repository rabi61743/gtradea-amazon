import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/free_delivery/presentation/free_delivery_screen.dart';
import 'package:gtradea_amazon/features/free_delivery/presentation/free_delivery_skeleton.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:gtradea_amazon/shared/widgets/shimmer.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

Map<String, dynamic> _row(String id, String title) => {
  'source': '1688',
  'num_iid': id,
  'free_delivery': true,
  'product_data': {
    'item': {
      'num_iid': id,
      'title': title,
      'pic_url': 'https://cdn.invalid/$id.jpg',
    },
    'pricing': {'displayPrice': 1200, 'displayCurrency': 'NPR'},
  },
};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WishlistStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    api.on(
      'GET',
      '/free-delivery',
      body: [_row('a', 'Summer Polo Shirt'), _row('b', 'Refrigerator box')],
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const FreeDeliveryScreen()),
    );
  }

  group('while the collection is arriving', () {
    testWidgets('the page is shaped, not spinning', (tester) async {
      await open(tester);
      await tester.pump();

      expect(find.byType(FreeDeliverySkeleton), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'a spinner says nothing about what is coming',
      );

      await tester.pumpAndSettle();
    });

    testWidgets('with card placeholders where the products will be', (
      tester,
    ) async {
      await open(tester);
      await tester.pump();

      expect(find.byType(ResultGridSkeleton), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('and the heading, whose words are not the server to give', (
      tester,
    ) async {
      // Known before any request is made. Drawing it as a grey bar would be
      // pretending not to know it.
      await open(tester);
      await tester.pump();

      expect(find.text('Delivered free'), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });

  group('once it has arrived', () {
    testWidgets('the skeleton is gone', (tester) async {
      await open(tester);
      await tester.pumpAndSettle();

      expect(find.byType(FreeDeliverySkeleton), findsNothing);
      expect(find.byType(ResultGridSkeleton), findsNothing);
      expect(find.text('Summer Polo Shirt'), findsOneWidget);
    });

    testWidgets('and nothing has moved', (tester) async {
      // The point of a skeleton: the real content lands where the bones were.
      await open(tester);
      await tester.pump();

      final headingWhileLoading = tester.getRect(find.text('Delivered free'));
      final gridWhileLoading = tester.getRect(find.byType(ResultGridSkeleton));
      // The first bone is the one standing in for the search field.
      final fieldBone = tester.getRect(find.byType(ShimmerBone).first);

      await tester.pumpAndSettle();

      expect(tester.getRect(find.text('Delivered free')), headingWhileLoading);
      final field = tester.getRect(find.byType(TextField));
      expect(field.top, closeTo(fieldBone.top, 0.5), reason: 'same place');
      expect(field.height, closeTo(fieldBone.height, 0.5), reason: 'same size');
      // The first card lands where the first placeholder was.
      expect(
        tester.getRect(find.byType(ProductResultCard).first).top,
        closeTo(gridWhileLoading.top, 0.5),
      );
    });
  });

  group('the other states are untouched', () {
    testWidgets('a failure still shows the retry, not bones', (tester) async {
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      api.on('GET', '/free-delivery', status: 500, body: const {});
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const FreeDeliveryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FreeDeliverySkeleton), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('an empty collection still says so', (tester) async {
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      api.on('GET', '/free-delivery', body: const []);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const FreeDeliveryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FreeDeliverySkeleton), findsNothing);
      expect(
        find.text('Nothing is on free delivery just now.'),
        findsOneWidget,
      );
    });
  });
}

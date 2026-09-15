import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/search/widgets/search_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

void main() {
  late TextEditingController controller;
  late List<String> submitted;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stubCatalog();
    controller = TextEditingController();
    submitted = [];
  });

  tearDown(() {
    controller.dispose();
    clearApiStub();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SearchField(
            controller: controller,
            onSubmitted: submitted.add,
            onImageSearch: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an empty box offers the other ways of asking', (tester) async {
    await pump(tester);

    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
  });

  testWidgets('typing puts the search where they were', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'polo shirt');
    await tester.pumpAndSettle();

    // The words stay, the two ways of starting a different search go.
    expect(find.text('polo shirt'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });

  testWidgets('and it runs the same search the keyboard key would', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'polo shirt');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();

    expect(submitted, ['polo shirt']);
  });

  testWidgets('clearing the box brings the pair back', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'polo');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
  });

  testWidgets(
    'a query being read back keeps them, as the results header does',
    (tester) async {
      // The results header carries the query in the box permanently. Nobody is
      // typing there, and asking again by voice or photo is what it is for.
      controller.text = 'polo shirt';
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('polo shirt'), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsNothing);
    },
  );

  testWidgets('the swap is a fade, not a jump', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'polo');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // Mid-cross-fade both sides are on screen; neither has moved the pill.
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });
}

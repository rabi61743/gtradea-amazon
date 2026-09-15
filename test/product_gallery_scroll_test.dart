import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/widgets/product_gallery.dart';

/// The gallery at the head of a long page, as the product page has it: a
/// vertical scroll view with plenty below the photographs.
Widget _page({int count = 4}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverList.list(
          children: [
            ProductGallery(
              images: [
                for (var i = 0; i < count; i++) 'https://cdn.invalid/$i.jpg',
              ],
              interval: const Duration(seconds: 4),
            ),
            for (var i = 0; i < 30; i++)
              SizedBox(height: 120, child: Text('Row $i')),
          ],
        ),
      ],
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the countdown bar repaints on its own layer', (tester) async {
    // Every frame of the countdown used to repaint the whole product card --
    // photograph included -- which is what put the top of the page over its
    // frame budget while it sat still.
    _phone(tester);
    await tester.pumpWidget(_page());
    await tester.pump();

    final bar = find.byType(LinearProgressIndicator);
    expect(bar, findsOneWidget);
    final boundary = find.ancestor(
      of: bar,
      matching: find.byType(RepaintBoundary),
    );
    // The nearest boundary above the bar is inside the gallery, not the page.
    final nearest = tester.renderObject<RenderRepaintBoundary>(boundary.first);
    expect(nearest.size.height, lessThan(40));
  });

  testWidgets('the photographs do not turn over while the page scrolls', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_page());
    await tester.pump();
    expect(find.text('Photos 1/4'), findsOneWidget);

    // A long, slow drag that outlasts the interval, finger down throughout.
    final gesture = await tester.startGesture(const Offset(200, 600));
    for (var i = 0; i < 50; i++) {
      await gesture.moveBy(const Offset(0, -2));
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Five seconds of scrolling, past the four-second interval: still on 1.
    expect(find.text('Photos 1/4', skipOffstage: false), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('scrolled past its top edge, it stays put; back in view, it '
      'resumes', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_page());
    await tester.pump();

    // Scrolled so the gallery's top is under the top of the screen.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Photos 1/4', skipOffstage: false),
      findsOneWidget,
      reason: 'a resize now would move the content on screen',
    );

    // Back to the top: rotation carries on as before. Pumped rather than
    // settled -- settling would sit out the running countdown itself.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Photos 1/4'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Photos 2/4'), findsOneWidget);
  });

  testWidgets('left alone at the top, it still rotates on its own', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_page());
    await tester.pump();

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Photos 2/4'), findsOneWidget);
  });
}

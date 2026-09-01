import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/l10n/app_strings.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:gtradea_amazon/features/notifications/presentation/notifications_screen.dart';
import 'package:gtradea_amazon/features/search/data/voice_search.dart';
import 'package:gtradea_amazon/features/search/widgets/search_field.dart';
import 'package:gtradea_amazon/features/search/widgets/voice_search_sheet.dart';
import 'package:gtradea_amazon/shared/widgets/brand_wordmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A recogniser that says exactly what the test tells it to.
///
/// One script per attempt, so a retry can be given a different answer from the
/// first try -- which is the only way to test that Try again actually listens
/// again rather than redrawing the same message.
class FakeVoice extends VoiceSearch {
  FakeVoice(this._script);

  final List<List<VoiceEvent>> _script;

  int listens = 0;
  int stops = 0;
  int cancels = 0;
  int settingsOpened = 0;
  AppLanguage? lastLanguage;

  @override
  Stream<VoiceEvent> listen({AppLanguage? language}) {
    lastLanguage = language;
    final events = _script[listens.clamp(0, _script.length - 1)];
    listens++;
    return Stream.fromIterable(events);
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> openAppSettings() async => settingsOpened++;
}

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

/// Opens the sheet from a button and hands back whatever it returned.
///
/// Callable more than once: the first call opens it, later calls just read the
/// result, so a test can look at the sheet, act on it, and then ask what it
/// finally returned.
Future<String?> Function() _sheetOpener(WidgetTester tester) {
  String? result;
  var opened = false;

  return () async {
    if (!opened) {
      opened = true;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await VoiceSearchSheet.show(context);
                },
                child: const Text('speak'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('speak'));
      await tester.pumpAndSettle();
    }
    return result;
  };
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LanguageStore.instance.resetForTest();
  });

  tearDown(() => VoiceSearch.instance = PlatformVoiceSearch());

  group('the header grid', () {
    /// Every edge in the header, measured rather than eyeballed.
    testWidgets('name, pill and bell icon all land on the same inset', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(SearchHeader(onTap: () {}, onVoiceResult: (_) {})),
      );
      await tester.pump();

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      final wordmark = tester.getRect(find.byType(BrandWordmark));
      final pill = tester.getRect(find.byKey(SearchHeader.pillKey));
      final bell = tester.getRect(
        find.descendant(
          of: find.byType(NotificationBell),
          matching: find.byIcon(Icons.notifications_none),
        ),
      );

      expect(wordmark.left, 16);
      expect(pill.left, 16);
      expect(pill.right, width - 16);
      // The one that would drift if somebody "tidied" the asymmetric padding:
      // an IconButton's box is 12pt wider than its icon on each side.
      expect(bell.right, width - 16);
    });

    testWidgets('the bell keeps a full tap target after being moved', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final button = tester.getSize(
        find.descendant(
          of: find.byType(NotificationBell),
          matching: find.byType(IconButton),
        ),
      );

      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the mark still announces the company name', (tester) async {
      // The header shows the logo rather than the name set as type, so the
      // name has to reach a screen reader some other way. Without this the
      // page opens with an unlabelled graphic.
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      expect(find.byType(BrandWordmark), findsOneWidget);
      expect(find.bySemanticsLabel(AppBrand.name), findsOneWidget);
      // And not as visible type: the mark replaced it, so a stray label would
      // be the name printed twice.
      expect(find.text(AppBrand.name), findsNothing);

      handle.dispose();
    });

    testWidgets('no microphone is offered when nothing would handle it', (
      tester,
    ) async {
      // The button is wired to a callback, so a header without one must not
      // show a control that silently does nothing.
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      expect(find.byType(VoiceSearchButton), findsNothing);
    });
  });

  group('dictating', () {
    testWidgets('a transcript closes the sheet and is handed back', (
      tester,
    ) async {
      VoiceSearch.instance = FakeVoice([
        const [VoicePartial('running'), VoiceHeard('running shoes')],
      ]);

      final open = _sheetOpener(tester);
      expect(await open(), 'running shoes');
    });

    testWidgets('the app language is what it listens in', (tester) async {
      final fake = FakeVoice([
        const [VoiceHeard('जुत्ता')],
      ]);
      VoiceSearch.instance = fake;
      LanguageStore.instance.setLanguage(AppLanguage.nepali);

      await _sheetOpener(tester)();

      expect(fake.lastLanguage, AppLanguage.nepali);
    });

    testWidgets('what has been heard so far is shown while speaking', (
      tester,
    ) async {
      VoiceSearch.instance = FakeVoice([
        const [VoiceLevel(0.6), VoicePartial('red jacket')],
      ]);

      await _sheetOpener(tester)();

      expect(find.text('red jacket'), findsOneWidget);
    });

    testWidgets('from the header, a transcript reaches the caller', (
      tester,
    ) async {
      VoiceSearch.instance = FakeVoice([
        const [VoiceHeard('kettle')],
      ]);

      String? spoken;
      await tester.pumpWidget(
        _wrap(SearchHeader(onTap: () {}, onVoiceResult: (q) => spoken = q)),
      );
      await tester.pump();

      await tester.tap(find.byType(VoiceSearchButton));
      await tester.pumpAndSettle();

      expect(spoken, 'kettle');
    });
  });

  group('when it does not work', () {
    testWidgets('silence offers another go rather than an error', (
      tester,
    ) async {
      VoiceSearch.instance = FakeVoice([
        const [VoiceNothingHeard()],
      ]);

      await _sheetOpener(tester)();

      expect(find.text('We did not catch that'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // No route to settings: nothing about this is a permission problem, and
      // sending someone to settings over a mumble would be a dead end.
      expect(find.text('Open settings'), findsNothing);
    });

    testWidgets('Try again actually listens again', (tester) async {
      final fake = FakeVoice([
        const [VoiceNothingHeard()],
        const [VoiceHeard('second time')],
      ]);
      VoiceSearch.instance = fake;

      final open = _sheetOpener(tester);
      await open();
      expect(fake.listens, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(fake.listens, 2);
      expect(await open(), 'second time');
    });

    testWidgets('a refused microphone offers both settings and a retry', (
      tester,
    ) async {
      final fake = FakeVoice([
        const [VoicePermissionDenied(permanently: true)],
      ]);
      VoiceSearch.instance = fake;

      await _sheetOpener(tester)();

      expect(find.text('The microphone is blocked'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Open settings'));
      await tester.pump();

      expect(fake.settingsOpened, 1);
    });

    testWidgets('a first refusal leads with asking again, not with settings', (
      tester,
    ) async {
      VoiceSearch.instance = FakeVoice([
        const [VoicePermissionDenied(permanently: false)],
      ]);

      await _sheetOpener(tester)();

      expect(find.text('The microphone is off for this app'), findsOneWidget);
      // Still reachable, because the platform's "permanent" flag is not
      // trustworthy enough to hide the only other way out behind it.
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('a device with no recogniser says so and stops offering', (
      tester,
    ) async {
      VoiceSearch.instance = FakeVoice([
        const [VoiceUnavailable()],
      ]);

      await _sheetOpener(tester)();

      expect(find.text('Voice search is not available here'), findsOneWidget);
      // Retrying cannot install a recogniser, so it is not offered. Typing is.
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Type instead'), findsOneWidget);
    });

    testWidgets('a dropped connection is named as one', (tester) async {
      VoiceSearch.instance = FakeVoice([
        const [VoiceFailed('network')],
      ]);

      await _sheetOpener(tester)();

      expect(find.text('No connection'), findsOneWidget);
    });

    testWidgets('the microphone does not outlive the sheet', (tester) async {
      final fake = FakeVoice([
        const [VoiceLevel(0.2)],
      ]);
      VoiceSearch.instance = fake;

      await _sheetOpener(tester)();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fake.cancels, greaterThanOrEqualTo(1));
    });
  });

  group('dictating into a search field', () {
    testWidgets('fills the field and runs the search from it', (tester) async {
      VoiceSearch.instance = FakeVoice([
        const [VoiceHeard('wireless earbuds')],
      ]);

      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? submitted;

      await tester.pumpWidget(
        _wrap(
          SearchField(
            controller: controller,
            onSubmitted: (q) => submitted = q,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(VoiceSearchButton));
      await tester.pumpAndSettle();

      // Both, deliberately: the search runs, and the words stay in front of the
      // shopper to correct if one of them was misheard.
      expect(controller.text, 'wireless earbuds');
      expect(submitted, 'wireless earbuds');
    });
  });
}

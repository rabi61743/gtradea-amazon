import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gtradea_amazon/core/images/app_images.dart';
import 'package:gtradea_amazon/features/account/presentation/recent_views_section.dart';
import 'package:gtradea_amazon/features/home/widgets/hero_banner.dart';
import 'package:gtradea_amazon/features/tour/data/tour_store.dart';

/// Runs once per test file, before anything in it.
///
/// Picked up by `flutter test` automatically because of its name and location,
/// so no test has to remember to do this -- which matters, because forgetting
/// would not fail loudly. It would just mean that one file was exercising a
/// disk cache that cannot work here.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The real provider caches to disk through `path_provider` and `sqflite`,
  // and `flutter_test` supplies neither platform channel. Left alone, every
  // image in the suite would resolve to a platform-channel failure rather than
  // to the 400 the test binding serves -- so a widget would show its error
  // state for a reason that has nothing to do with the widget.
  //
  // A plain NetworkImage keeps the URL readable, which is what the image tests
  // assert on, and behaves the way the suite already expects.
  AppImages.providerOverride = NetworkImage.new;

  // The hero's autoplay clock is also what fills its progress bar, so it keeps
  // a frame scheduled for as long as the carousel is on screen -- and every
  //  on a page with a hero would wait on it forever.
  //
  // Off by default here, and switched back on by the tests that are about the
  // carousel. Nothing is mocked by this: those tests get the real clock at the
  // real interval, and the app is untouched.
  HeroBanner.autoplayEnabled = false;

  // A Product History card waits for its picture as well as its details, and
  // an image decode begun inside the test clock never finishes -- so every
  // card would stay a skeleton. The picture is taken as loaded here; the card
  // tests still exercise the details it waits on.
  RecentViewsSection.warmImage = (_, _) async {};

  // The guided tour opens on a first launch, and every widget test seeds an
  // empty preference store -- which *is* a first launch. Left on, it would
  // open over every suite that pumps the home screen and cover the very
  // widgets they measure, so a header test would fail because of a feature
  // that has nothing to do with it.
  //
  // Off here rather than in each file, for the reason given above about the
  // image provider: forgetting would not fail loudly, it would silently
  // measure an overlay. The tour's own tests switch it back on.
  TourStore.enabled = false;

  await testMain();
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gtradea_amazon/core/images/app_images.dart';

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

  await testMain();
}

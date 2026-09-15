// Writes the iOS launch images from assets/brand/logo.svg.
//
// Not a test, and deliberately not under test/: it writes files, and anything
// in test/ runs on every `flutter test`, which would rewrite checked in
// artwork as a side effect of running the suite. It is shaped as a test
// because that is the one harness here with a Flutter binding, and rendering
// an SVG needs one. Run it by naming it:
//
//     flutter test tool/rasterise_launch_images_test.dart
//
// Why this exists at all: Xcode is not available on this machine, so the
// asset catalogue cannot be regenerated the usual way, and the three
// LaunchImage files shipped by `flutter create` are 68 byte blank
// placeholders. Copying the launcher icon in instead was tried and was wrong:
// the launcher icon carries a white plate, which reads as an app icon pasted
// onto the splash rather than as the mark.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('writes the iOS launch images', (tester) async {
    const dir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

    // 48pt, which is what the storyboard reserves, at the three iOS scales.
    const sizes = <String, int>{
      'LaunchImage.png': 48,
      'LaunchImage@2x.png': 96,
      'LaunchImage@3x.png': 144,
    };

    await tester.runAsync(() async {
      final picture = await vg.loadPicture(
        const SvgAssetLoader('assets/brand/logo.svg'),
        null,
      );

      for (final entry in sizes.entries) {
        final width = entry.value.toDouble();
        // The artwork's own proportions, so the mark cannot be squashed.
        final height = width * picture.size.height / picture.size.width;

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.scale(width / picture.size.width);
        canvas.drawPicture(picture.picture);

        final image = await recorder.endRecording().toImage(
          width.round(),
          height.round(),
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(png, isNotNull, reason: 'encoding ${entry.key} produced nothing');

        File('$dir/${entry.key}')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
        // ignore: avoid_print
        print('wrote $dir/${entry.key} at ${width.round()}x${height.round()}');
      }

      picture.picture.dispose();
    });
  });
}

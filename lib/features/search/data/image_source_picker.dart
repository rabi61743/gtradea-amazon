import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

/// Where a photograph came from.
enum PhotoSource { camera, gallery }

/// How picking a photograph ended.
///
/// One case per thing that can actually happen, because each needs the shopper
/// told something different and offered a different way out -- the same shape
/// the address and voice-search features use. A single "failed" leaves them
/// with nothing to do next.
sealed class PhotoOutcome {
  const PhotoOutcome();
}

/// A file to search with.
final class PhotoTaken extends PhotoOutcome {
  const PhotoTaken(this.file);
  final File file;
}

/// Backed out of the camera or the picker. Not an error, and never worded as
/// one.
final class PhotoCancelled extends PhotoOutcome {
  const PhotoCancelled();
}

/// The camera or the photo library was refused.
///
/// [permanently] is the platform's own opinion and is not always right, so the
/// sheet offers both a retry and a route to settings whichever way it reads.
final class PhotoPermissionDenied extends PhotoOutcome {
  const PhotoPermissionDenied({
    required this.source,
    required this.permanently,
  });

  final PhotoSource source;
  final bool permanently;
}

/// No camera on this device, which no permission grant fixes.
final class PhotoNoCamera extends PhotoOutcome {
  const PhotoNoCamera();
}

/// Anything else, kept so an unexpected platform error is still reported
/// rather than swallowed.
final class PhotoFailed extends PhotoOutcome {
  const PhotoFailed(this.reason);
  final String reason;
}

/// Gets a photograph from the camera or the gallery.
///
/// [instance] is replaceable so the flow can be tested without a device --
/// there is no camera in a widget test, and every path through the UI has to be
/// reachable anyway.
abstract class ImageSourcePicker {
  const ImageSourcePicker();

  static ImageSourcePicker instance = PlatformImageSourcePicker();

  Future<PhotoOutcome> pick(PhotoSource source);
}

class PlatformImageSourcePicker extends ImageSourcePicker {
  PlatformImageSourcePicker();

  final _picker = ImagePicker();

  /// What the camera is asked for.
  ///
  /// Recognition works from a modest picture, and the file is base64-encoded
  /// into a JSON body -- which inflates it by a third. A full 12-megapixel
  /// photo would be a multi-megabyte upload for no better answer; 1280px is
  /// plenty for matching and keeps the request inside a couple of seconds on a
  /// Nepali mobile connection.
  static const _maxEdge = 1280.0;
  static const _quality = 85;

  @override
  Future<PhotoOutcome> pick(PhotoSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: _maxEdge,
        maxHeight: _maxEdge,
        imageQuality: _quality,
      );

      // Null is the shopper backing out, which the plugin reports the same way
      // as nothing being chosen. Not a failure.
      if (file == null) return const PhotoCancelled();
      return PhotoTaken(File(file.path));
    } on PlatformException catch (e) {
      return _fromPlatform(e, source);
    } catch (error) {
      return PhotoFailed(error.toString());
    }
  }

  /// The plugin's error vocabulary, translated into something with a remedy.
  static PhotoOutcome _fromPlatform(PlatformException e, PhotoSource source) {
    final code = e.code.toLowerCase();

    if (code.contains('access') || code.contains('permission')) {
      return PhotoPermissionDenied(
        source: source,
        // The plugin does not distinguish "asked and refused" from "refused
        // for good", so this never claims the harsher one. The sheet offers
        // settings either way.
        permanently: false,
      );
    }
    if (code.contains('no_available_camera') ||
        code.contains('camera_access')) {
      return const PhotoNoCamera();
    }
    return PhotoFailed(e.message ?? e.code);
  }
}

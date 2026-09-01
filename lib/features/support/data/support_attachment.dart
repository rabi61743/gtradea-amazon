import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';

/// A file the shopper has chosen but not yet sent.
///
/// Held in memory rather than by path: the picker hands back a cache file the
/// OS may delete, and the bytes are what the upload needs anyway.
class PickedAttachment {
  const PickedAttachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  /// Lower-case, no dot. Empty when the name carries no extension at all.
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Whether this is something that can be shown rather than described.
  ///
  /// The list is the image half of what the bucket accepts, and it decides
  /// whether the shopper gets a thumbnail of what they picked or an icon
  /// standing in for it.
  bool get isImage =>
      const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension);

  /// What to show beside the name: the kind of file, in the words a shopper
  /// uses for it rather than a MIME type.
  String get kindLabel => switch (extension) {
    'jpg' || 'jpeg' => 'JPEG image',
    'png' => 'PNG image',
    'webp' => 'WEBP image',
    'gif' => 'GIF image',
    'pdf' => 'PDF document',
    'doc' || 'docx' => 'Word document',
    'txt' => 'Text file',
    '' => 'File',
    _ => '${extension.toUpperCase()} file',
  };
}

/// Rounded to the unit a person reads, which is what goes next to the name.
String formatFileSize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) {
    final kilobytes = bytes / kb;
    return '${kilobytes.toStringAsFixed(kilobytes < 10 ? 1 : 0)} KB';
  }
  final megabytes = bytes / mb;
  return '${megabytes.toStringAsFixed(megabytes < 10 ? 1 : 0)} MB';
}

/// Files attached to a support ticket, in the shop's own storage.
///
/// **None of this is invented.** `GET /media/buckets` publishes the storage
/// the server will accept, and one bucket exists for exactly this:
///
/// ```json
/// {"name":"support-attachments","admin_only":false,"requires_auth":true,
///  "per_user_folder":true,"max_bytes":10485760}
/// ```
///
/// So the ceiling below is the server's own, not a number chosen here;
/// `per_user_folder` is what files the upload under the signed-in account; and
/// `requires_auth` is why a guest is not offered the option.
///
/// The upload is the same two steps the storefront takes -- multipart to
/// `/media/upload`, then the returned **key** travels with the message as
/// `attachments` -- which is what puts the file in front of support staff: the
/// admin ticket console renders `message.attachments` through the same media
/// endpoint. A file uploaded any other way would sit in storage where nobody
/// answering the ticket would ever see it.
class SupportAttachmentRepository {
  SupportAttachmentRepository._();

  static final SupportAttachmentRepository instance =
      SupportAttachmentRepository._();

  Dio get _dio => ApiClient.http;

  /// The bucket support attachments belong in.
  static const bucket = 'support-attachments';

  /// The bucket's own `max_bytes`. Shown to the shopper and enforced before
  /// the upload, so an oversized file is refused with an explanation here
  /// rather than by a rejection from the server after the wait.
  static const maxBytes = 10485760;

  /// What the storefront's own file input accepts:
  /// `image/*,.pdf,.doc,.docx,.txt`. Spelled out so the picker and the
  /// validation message agree on one list.
  static const allowedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'pdf',
    'doc',
    'docx',
    'txt',
  ];

  /// Human-readable, for the caption under the button.
  static String get allowedLabel =>
      allowedExtensions.map((e) => e.toUpperCase()).join(', ');

  /// Why this file cannot be sent, or null when it can.
  static String? rejectionFor(PickedAttachment file) {
    if (!allowedExtensions.contains(file.extension)) {
      final named = file.extension.isEmpty
          ? 'Files without an extension'
          : '.${file.extension} files';
      return '$named are not supported. Attach one of: $allowedLabel.';
    }
    if (file.sizeBytes > maxBytes) {
      // Worded as "over the limit" rather than stating the two sizes as
      // separate sentences: a file a byte over rounds to the same figure as
      // the ceiling, and "is 10 MB. The limit is 10 MB." reads as nonsense.
      return '${file.name} is ${formatFileSize(file.sizeBytes)}, over the '
          '${formatFileSize(maxBytes)} limit.';
    }
    if (file.sizeBytes == 0) {
      return '${file.name} is empty, so there is nothing to send.';
    }
    return null;
  }

  /// Stands in for the system picker, which a test binding does not have.
  /// The file behind a storage key.
  ///
  /// The bucket is private -- `requires_auth` and a folder per user -- so a
  /// stored file has no public address to point an [Image] at. It comes back
  /// through the media endpoint with the caller's own credentials, which is
  /// also what stops one shopper reading another's.
  ///
  /// Cached for the life of the app: a thread redraws on every keystroke in
  /// its composer, and fetching each picture again on every frame would be
  /// both slow and rude to the server.
  Future<Uint8List> download(String key) {
    return _downloads[key] ??= guarded(() async {
      final res = await _dio.get<List<int>>(
        '/media/$bucket/object',
        queryParameters: {'key': key},
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? const []);
    });
  }

  final _downloads = <String, Future<Uint8List>>{};

  /// What to call a stored file on screen.
  ///
  /// Keys carry the folder they were filed under -- `u/<user>/receipt.pdf` --
  /// and the shopper only ever named the last part of that.
  static String fileNameFor(String key) {
    final cut = key.lastIndexOf('/');
    return cut < 0 ? key : key.substring(cut + 1);
  }

  /// Whether a stored file is something that can be shown rather than listed.
  static bool isImageKey(String key) {
    final name = fileNameFor(key).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp', '.gif'}.any(name.endsWith);
  }

  @visibleForTesting
  void clearDownloadsForTest() => _downloads.clear();

  @visibleForTesting
  static Future<List<PickedAttachment>> Function()? pickerOverride;

  /// Opens the system file picker.
  ///
  /// The picker is pointed at [allowedExtensions], but what it returns is
  /// still checked: Android's document browser will hand back a file of any
  /// type from "Browse" regardless of the filter, and a file silently dropped
  /// afterwards is the one thing the shopper must not get.
  Future<List<PickedAttachment>> pick() async {
    final override = pickerOverride;
    if (override != null) return override();

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      // The bytes, not a path: the picker's file lives in a cache directory
      // the OS may clear, and the upload wants bytes anyway.
      withData: true,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (result == null) return const [];
    return [
      for (final file in result.files)
        if (file.bytes case final bytes?)
          PickedAttachment(name: file.name, bytes: bytes),
    ];
  }

  /// Puts one file in the bucket and returns the storage key that identifies
  /// it. That key, not a URL, is what a message carries.
  Future<String> upload(PickedAttachment file) => guarded(() async {
    final form = FormData.fromMap({
      'bucket': bucket,
      'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
    });
    final res = await _dio.post('/media/upload', data: form);
    final key = asString(asMap(res.data)['key']);
    if (key == null || key.isEmpty) {
      throw const ApiError(
        statusCode: 502,
        message:
            'The file was uploaded but storage did not name it, so it '
            'could not be attached.',
      );
    }
    return key;
  });
}

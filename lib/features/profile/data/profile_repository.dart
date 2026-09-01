import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import 'profile.dart';

/// The profile row and the avatar, against the gateway.
///
/// Every path here was read off the storefront's own JavaScript rather than
/// guessed, because the `/profile` prefix answers 401 before it routes -- so
/// probing it cannot tell a real sub-path from a typo, and a plausible-looking
/// invented endpoint would have failed silently for every shopper:
///
///   * `GET /profile` and `PATCH /profile` -- the storefront's `qp()` and
///     `Bp()`, and what the sibling app already calls.
///   * `POST /media/upload` -- multipart, `bucket` + `file`, answering
///     `{key, public_url}`. The storefront's `uploadViaServer(bucket, file)`,
///     which its account page calls with the bucket `avatars` before patching
///     the profile with the URL it gets back. Both media routes answer **400**
///     unauthenticated rather than 404, which is what says they exist.
///
/// The avatar is therefore two requests and not one: the picture goes to the
/// media service, and the profile stores the URL it returns.
class ProfileRepository {
  ProfileRepository._();

  static final ProfileRepository instance = ProfileRepository._();

  Dio get _dio => ApiClient.http;

  /// The bucket the storefront puts avatars in. Sent as a form field, so it has
  /// to match what the server allows -- this is not a name the app chooses.
  static const avatarBucket = 'avatars';

  /// What the server will take. The storefront refuses anything larger before
  /// it uploads, and so does this: a rejection after a slow mobile upload is a
  /// minute of someone's life for an answer that was knowable up front.
  static const maxPhotoBytes = 5 * 1024 * 1024;

  Future<Profile> fetch() => guarded(() async {
    final res = await _dio.get('/profile');
    final profile = Profile.fromJson(asMap(res.data));
    if (profile == null) {
      throw const ApiError(
        statusCode: null,
        message: 'Your profile could not be read.',
        local: true,
      );
    }
    return profile;
  });

  /// Writes only what is passed.
  ///
  /// Null means "leave it alone", which is why every parameter is nullable and
  /// nothing is defaulted: sending `first_name: ''` because the caller happened
  /// not to be editing the name is how a save wipes a field nobody touched.
  Future<Profile> update({
    String? firstName,
    String? lastName,
    String? phone,
    String? avatarUrl,
  }) => guarded(() async {
    final res = await _dio.patch(
      '/profile',
      data: {
        'first_name': ?firstName,
        'last_name': ?lastName,
        'phone': ?phone,
        'avatar_url': ?avatarUrl,
      },
    );
    final profile = Profile.fromJson(asMap(res.data));
    if (profile == null) {
      throw const ApiError(
        statusCode: null,
        message: 'The server did not return the updated profile.',
        local: true,
      );
    }
    return profile;
  });

  /// Uploads the picture and returns the public URL to store on the profile.
  ///
  /// Does **not** patch the profile -- that is the caller's next step, and
  /// keeping them separate is what lets a failed patch be retried without
  /// uploading the photograph twice.
  Future<String> uploadAvatar(File file) => guarded(() async {
    final bytes = await file.length();
    if (bytes > maxPhotoBytes) {
      throw const ApiError(
        statusCode: null,
        message: 'Pick a photo smaller than 5 MB.',
        local: true,
      );
    }

    final form = FormData.fromMap({
      'bucket': avatarBucket,
      'file': await MultipartFile.fromFile(file.path, filename: _nameOf(file)),
    });

    final res = await _dio.post('/media/upload', data: form);
    final url = asString(asMap(res.data)['public_url']);
    if (url == null) {
      throw const ApiError(
        statusCode: null,
        message: 'The photo uploaded but the server returned no address.',
        local: true,
      );
    }
    return url;
  });

  /// The file's own name, which the server uses to work out the extension.
  ///
  /// `image_picker` hands back a cache path whose basename is already unique,
  /// so this does not need to invent one -- and inventing one with a timestamp
  /// would be a second thing to keep right.
  static String _nameOf(File file) {
    final parts = file.path.split(RegExp(r'[/\\]'));
    final name = parts.isEmpty ? '' : parts.last;
    return name.isEmpty ? 'avatar.jpg' : name;
  }
}

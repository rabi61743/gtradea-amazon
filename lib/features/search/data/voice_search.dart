import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/l10n/app_strings.dart';

/// Something that happened during one dictation.
///
/// A stream of these rather than a pile of callbacks: the sheet needs the
/// partial text and the sound level while the shopper is talking, and exactly
/// one terminal answer at the end. Modelling the terminal answer as a member of
/// the same family is what makes "the stream closed without saying why"
/// impossible to write.
sealed class VoiceEvent {
  const VoiceEvent();
}

/// How loud it is, normalised to 0..1 for whatever the sheet draws with it.
final class VoiceLevel extends VoiceEvent {
  const VoiceLevel(this.level);
  final double level;
}

/// The recogniser's current best guess, which will keep changing.
final class VoicePartial extends VoiceEvent {
  const VoicePartial(this.text);
  final String text;
}

/// How a dictation ended. Always exactly one, always last.
///
/// One case per thing that can actually happen, because each needs the shopper
/// told something different and offered a different way out -- the same shape
/// as [DetectResult] in the address feature, for the same reason. A single
/// "failed" leaves them with nothing to do next.
sealed class VoiceOutcome extends VoiceEvent {
  const VoiceOutcome();
}

/// Words came back.
final class VoiceHeard extends VoiceOutcome {
  const VoiceHeard(this.transcript);
  final String transcript;
}

/// The microphone worked and nobody said anything recognisable. Not an error,
/// and never worded as one -- the remedy is simply to speak again.
final class VoiceNothingHeard extends VoiceOutcome {
  const VoiceNothingHeard();
}

/// The shopper said no to the microphone.
///
/// [permanently] is the platform's own opinion and is not always right, so the
/// sheet offers both a retry and a route to app settings whichever way it
/// reads. It only decides which of the two leads.
final class VoicePermissionDenied extends VoiceOutcome {
  const VoicePermissionDenied({required this.permanently});
  final bool permanently;
}

/// There is no speech recogniser on this device. Common on bare emulators and
/// on phones sold without Google's speech services, and no permission grant
/// fixes it -- so the sheet says so and leaves typing reachable.
final class VoiceUnavailable extends VoiceOutcome {
  const VoiceUnavailable();
}

/// Anything else, kept so an unexpected platform error is still reported
/// rather than swallowed.
final class VoiceFailed extends VoiceOutcome {
  const VoiceFailed(this.reason);
  final String reason;
}

/// Turns "hold the microphone open" into a stream of [VoiceEvent].
///
/// [instance] is replaceable so the sheet can be tested without a device --
/// there is no speech recogniser in a widget test, and every path through the
/// UI has to be reachable anyway.
abstract class VoiceSearch {
  const VoiceSearch();

  static VoiceSearch instance = PlatformVoiceSearch();

  /// One dictation. The stream ends after exactly one [VoiceOutcome].
  Stream<VoiceEvent> listen({AppLanguage? language});

  /// Stops listening and takes whatever has been heard so far as the answer.
  Future<void> stop();

  /// Stops listening and throws away what was heard.
  Future<void> cancel();

  /// Opens this app's settings page, for a microphone refused for good.
  Future<void> openAppSettings();
}

/// The real one, over the platform recogniser.
class PlatformVoiceSearch extends VoiceSearch {
  PlatformVoiceSearch();

  /// Nothing is said for this long and the recogniser calls it finished.
  static const pauseFor = Duration(seconds: 3);

  /// A ceiling on one dictation. Nobody dictates a search query for half a
  /// minute, and an open microphone that never closes is a battery drain the
  /// shopper cannot see.
  static const listenFor = Duration(seconds: 30);

  final _speech = SpeechToText();

  @override
  Stream<VoiceEvent> listen({AppLanguage? language}) {
    // Broadcast is deliberately not used: exactly one sheet listens, and a
    // broadcast stream would drop the events emitted before it subscribed.
    final controller = StreamController<VoiceEvent>();
    unawaited(_run(controller, language));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<VoiceEvent> controller,
    AppLanguage? language,
  ) async {
    var settled = false;
    var lastText = '';

    void finish(VoiceOutcome outcome) {
      if (settled || controller.isClosed) return;
      settled = true;
      controller.add(outcome);
      unawaited(controller.close());
    }

    /// The recogniser stopped on its own. Whatever it had heard is the answer.
    void finishFromWhatWeHave() => finish(
      lastText.isEmpty ? const VoiceNothingHeard() : VoiceHeard(lastText),
    );

    SpeechRecognitionError? initError;

    try {
      final ready = await _speech.initialize(
        onError: (error) {
          initError = error;
          if (settled) return;
          finish(_fromError(error, lastText));
        },
        onStatus: (status) {
          // `done` on Android, `notListening` on iOS. Either means the session
          // is over, and without this a dictation that produced only partial
          // results would hang the sheet open forever.
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            finishFromWhatWeHave();
          }
        },
      );

      if (!ready) {
        // A refused microphone and a missing recogniser both land here, and
        // they need opposite messages -- one has a way back, the other does
        // not. On Android a refusal reports *no error at all*, just false, so
        // the error is not enough to tell them apart and the permission is
        // asked about directly.
        final error = initError;
        if (error != null && error.errorMsg.contains('permission')) {
          finish(VoicePermissionDenied(permanently: error.permanent));
        } else if (await _permitted()) {
          finish(const VoiceUnavailable());
        } else {
          // Not claimed as permanent: Android cannot say, and leading with
          // "blocked, go to settings" for someone who simply tapped the wrong
          // button on the first prompt sends them the long way round. The
          // sheet offers settings either way.
          finish(const VoicePermissionDenied(permanently: false));
        }
        return;
      }

      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            lastText = words;
            if (!settled && !controller.isClosed) {
              controller.add(VoicePartial(words));
            }
          }
          if (result.finalResult) finishFromWhatWeHave();
        },
        onSoundLevelChange: (level) {
          if (settled || controller.isClosed) return;
          controller.add(VoiceLevel(_normalise(level)));
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          // A permanent error ends the session rather than leaving the
          // microphone open behind a sheet that has already given up.
          cancelOnError: true,
          pauseFor: pauseFor,
          listenFor: listenFor,
          localeId: await _localeId(language),
        ),
      );
    } on PlatformException catch (error) {
      // A device with no recogniser throws rather than returning false, so
      // without this the clearest case of all reports "something interrupted
      // the microphone".
      finish(
        error.code == 'recognizerNotAvailable'
            ? const VoiceUnavailable()
            : VoiceFailed(error.code),
      );
    } catch (error) {
      finish(VoiceFailed(error.toString()));
    }
  }

  /// Whether the microphone is granted, asked of the platform rather than
  /// inferred. False also when the question itself fails, which is the safe
  /// way round: it offers a remedy instead of a dead end.
  Future<bool> _permitted() async {
    try {
      return await _speech.hasPermission;
    } catch (_) {
      return false;
    }
  }

  /// The platform's error vocabulary, translated into something with a remedy.
  static VoiceOutcome _fromError(SpeechRecognitionError error, String heard) {
    final code = error.errorMsg;

    // Words first. Android routinely reports `error_no_match` *after* handing
    // back a perfectly good transcription, and throwing it away to show "we
    // did not catch that" would be discarding the answer we already have.
    if (heard.isNotEmpty) return VoiceHeard(heard);

    if (code.contains('permission')) {
      return VoicePermissionDenied(permanently: error.permanent);
    }
    if (code.contains('no_match') || code.contains('speech_timeout')) {
      return const VoiceNothingHeard();
    }
    if (code.contains('network')) {
      return const VoiceFailed('network');
    }
    return VoiceFailed(code);
  }

  /// Sound level to 0..1.
  ///
  /// Android reports roughly -2..10 from `onRmsChanged` and iOS reports a
  /// negative decibel scale; both are clamped rather than trusted, because this
  /// only ever drives an animation and a wrong number should look calm rather
  /// than crash.
  static double _normalise(double level) {
    if (level.isNaN || level.isInfinite) return 0;
    return ((level + 2) / 12).clamp(0.0, 1.0);
  }

  /// The recogniser locale matching the app's language, or null for the
  /// device default.
  ///
  /// Null rather than a guess: a shopper reading the app in Nepali on a phone
  /// with no Nepali recogniser is better served dictating in whatever the
  /// device does speak than by a session that refuses to start.
  Future<String?> _localeId(AppLanguage? language) async {
    if (language == null) return null;
    try {
      final locales = await _speech.locales();
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith(language.code)) {
          return locale.localeId;
        }
      }
    } catch (_) {
      // No locale list is not a reason to refuse to listen.
    }
    return null;
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {
      // Stopping something that already stopped is not worth reporting.
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {
      // As above.
    }
  }

  /// Borrowed from geolocator, which is already a dependency.
  ///
  /// The call is not location-specific -- it opens this app's own settings
  /// page, where every permission including the microphone lives. Adding a
  /// second permissions plugin to reach the same screen would be a dependency
  /// for nothing.
  @override
  Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // Some devices have no settings activity to open. The message beside the
      // button still tells the shopper what to do.
    }
  }
}

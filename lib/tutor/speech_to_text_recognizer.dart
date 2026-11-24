import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'voice_tutor_controller.dart';

String? speechRecognitionLocaleId(String preference) =>
    preference == 'system' || preference.isEmpty ? null : preference;

/// Matches the requested locale to the device's reported speech locales.
/// An empty list means that the platform did not report locale inventory, so
/// the requested locale is still passed through without an English fallback.
String? matchSpeechRecognitionLocale(
  String requestedLocale,
  Iterable<String> availableLocales,
) {
  String normalize(String value) => value.toLowerCase().replaceAll('_', '-');

  final requested = normalize(requestedLocale);
  final available = availableLocales.toList(growable: false);
  if (available.isEmpty) return requestedLocale;
  for (final locale in available) {
    if (normalize(locale) == requested) return locale;
  }
  final language = requested.split('-').first;
  for (final locale in available) {
    if (normalize(locale).split('-').first == language) return locale;
  }
  return null;
}

/// Device speech adapter. Android/iOS may use an online recognition service;
/// this adapter does not promise offline speech recognition.
class SpeechToTextRecognizer
    implements SpeechRecognizer, SpeechRecognitionLocaleResolver {
  SpeechToTextRecognizer({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool? _available;
  void Function(String)? _errorSink;

  @override
  Future<String?> resolveAvailableLocale(String requestedLocale) async {
    try {
      final locales = await _speech.locales();
      return matchSpeechRecognitionLocale(
        requestedLocale,
        locales.map((locale) => locale.localeId),
      );
    } catch (_) {
      // The plugin cannot enumerate online-only recognizer locales on Android.
      // Try the requested locale explicitly; never substitute English.
      return requestedLocale;
    }
  }

  @override
  Future<bool> initialize(void Function(String) onError) async {
    _errorSink = onError;
    _available ??= await _speech.initialize(
      onError: (error) => _errorSink?.call(error.errorMsg),
      onStatus: (_) {},
    );
    return _available!;
  }

  @override
  Future<void> listen({
    required String locale,
    required Duration listenTimeout,
    required void Function(String, bool) onResult,
  }) async {
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: speechRecognitionLocaleId(locale),
        listenFor: listenTimeout,
        pauseFor: const Duration(seconds: 4),
      ),
      onResult: (SpeechRecognitionResult result) =>
          onResult(result.recognizedWords, result.finalResult),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
